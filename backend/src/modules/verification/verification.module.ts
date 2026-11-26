import { Body, Controller, Get, HttpCode, Injectable, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Prisma } from '@prisma/client';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, Length, Max, Min, ValidateNested } from 'class-validator';
import { randomInt } from 'node:crypto';
import sharp from 'sharp';
import { failedSelfieChecks, SELFIE_CRITERIA, SELFIE_GESTURES, SELFIE_LIMITS, SELFIE_REJECT_CODES } from '../../domain/selfie';
import { AppError, ErrorCode } from '../../common/errors';
import { AllowPending, AuthAdmin, AuthUser, CurrentAdmin, CurrentUser, RateLimit, RequirePermissions } from '../../common/http';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { MediaModule } from '../media/media.module';
import { StorageService } from '../media/storage.service';
import { NotificationsService } from '../notifications/notifications.module';
import { ProfilesModule, ProfilesService } from '../profiles/profiles.module';

/** Reject codes → localised text + fix steps live in the app (i18n), keyed by code. */
export const REJECT_CODES = ['photo_unclear', 'photo_not_you', 'photo_group', 'photo_inappropriate', 'photo_filtered', 'bio_contact_info', 'bio_inappropriate', 'name_invalid', 'suspected_fake', ...SELFIE_REJECT_CODES, 'other'] as const;

class DeviceChecksDto {
  @ApiProperty() @IsInt() @Min(0) @Max(20) faces: number;
  @ApiProperty() @IsNumber() @Min(0) @Max(1) faceRatio: number;
  @ApiProperty() @IsNumber() @Min(-180) @Max(180) yaw: number;
  @ApiProperty() @IsNumber() @Min(-180) @Max(180) roll: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) @Max(1) leftEyeOpen?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) @Max(1) rightEyeOpen?: number;
}

class SelfieDto {
  @ApiProperty() @IsUUID() challengeId: string;
  @ApiProperty({ type: DeviceChecksDto }) @ValidateNested() @Type(() => DeviceChecksDto) deviceChecks: DeviceChecksDto;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() preferFemaleReviewer?: boolean;
}

class RejectDto {
  @ApiProperty({ enum: REJECT_CODES }) @IsIn(REJECT_CODES as unknown as string[]) code: string;
  @ApiProperty() @IsString() @Length(5, 300) reason: string;
  @ApiPropertyOptional({ type: [String], description: 'Photos to reject; others remain pending' })
  @IsOptional() @IsArray() @ArrayMaxSize(6) @IsUUID('4', { each: true }) photoIds?: string[];
}

class ApproveDto {
  @ApiPropertyOptional({ type: [String], description: 'Photos to reject while approving the rest' })
  @IsOptional() @IsArray() @ArrayMaxSize(6) @IsUUID('4', { each: true }) rejectPhotoIds?: string[];
}

@Injectable()
export class VerificationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    private readonly storage: StorageService,
    private readonly notifications: NotificationsService,
    private readonly profiles: ProfilesService,
  ) {}

  /** PENDING: profile + photos are submitted for human review. */
  async submit(userId: string) {
    const [profile, user] = await Promise.all([
      this.prisma.userProfile.findUnique({ where: { userId }, select: { userId: true } }),
      this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { status: true, ageConfirmedAt: true } }),
    ]);
    if (!profile || !user.ageConfirmedAt) throw new AppError(ErrorCode.VALIDATION, 'Complete your profile first');
    const minPhotos = await this.settings.get('profile.minPhotos', 2);
    const ready = await this.prisma.userPhoto.count({ where: { userId, deletedAt: null, status: { in: ['PENDING_REVIEW', 'APPROVED'] } } });
    if (ready < minPhotos) throw new AppError(ErrorCode.VALIDATION, `At least ${minPhotos} processed photos are required`, { minPhotos });

    // First sign-up: a live selfie (taken right after the photos) must be waiting or approved.
    if ((await this.settings.get('verification.selfieRequired', 1)) && !(await this.hasSelfie(userId))) {
      throw new AppError(ErrorCode.SELFIE_REQUIRED, 'Take the verification selfie first');
    }
    const open = await this.prisma.verificationRequest.findFirst({ where: { userId, type: 'PROFILE_REVIEW', status: 'PENDING' } });
    if (open) return this.status(userId);
    const photos = await this.prisma.userPhoto.findMany({ where: { userId, deletedAt: null }, select: { id: true, moderation: true } });
    await this.prisma.verificationRequest.create({
      data: { userId, type: 'PROFILE_REVIEW', autoResult: { photos: photos.map((p) => ({ id: p.id, scan: p.moderation })) } as Prisma.InputJsonValue },
    });
    if (user.status === 'REJECTED') await this.prisma.user.update({ where: { id: userId }, data: { status: 'PENDING_VERIFICATION' } });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'verification.submit', entityType: 'user', entityId: userId });
    return this.status(userId);
  }

  /** Approved before (badge) or one waiting for review. */
  private async hasSelfie(userId: string) {
    const [badge, pending] = await Promise.all([
      this.prisma.userVerification.count({ where: { userId, type: 'LIVENESS', revokedAt: null } }),
      this.prisma.verificationRequest.count({ where: { userId, type: 'LIVENESS', status: 'PENDING' } }),
    ]);
    return badge + pending > 0;
  }

  /** Step 1: a one-time capture — random gesture + private upload slot, valid 10 minutes. */
  async selfieChallenge(userId: string) {
    const gesture = SELFIE_GESTURES[randomInt(SELFIE_GESTURES.length)];
    const id = (await this.prisma.$queryRaw<{ id: string }[]>`SELECT gen_random_uuid()::text AS id`)[0].id;
    const storageKey = `v/${userId}/${id}.jpg`;
    const expiresAt = new Date(Date.now() + SELFIE_LIMITS.challengeMinutes * 60_000);
    await this.prisma.selfieChallenge.create({ data: { id, userId, gesture, storageKey, expiresAt } });
    return {
      challengeId: id,
      gesture,
      expiresAt,
      criteria: SELFIE_CRITERIA,
      limits: SELFIE_LIMITS,
      upload: await this.storage.presignUpload(storageKey, 'image/jpeg', SELFIE_LIMITS.maxBytes),
    };
  }

  /**
   * Step 2: the picture is uploaded — check it and queue it for the verification team.
   * Automatic checks (phone face detection + server image checks) refuse clear failures
   * with the criteria to fix; the reviewer confirms gesture, same person and a live capture.
   */
  async submitSelfie(userId: string, dto: SelfieDto) {
    const c = await this.prisma.selfieChallenge.findUnique({ where: { id: dto.challengeId } });
    if (!c || c.userId !== userId) throw new AppError(ErrorCode.NOT_FOUND);
    if (c.usedAt) throw new AppError(ErrorCode.CONFLICT, 'This capture was already used');
    // a little grace for slow uploads; a stale capture means a new gesture
    if (c.expiresAt.getTime() + 5 * 60_000 < Date.now()) throw new AppError(ErrorCode.SELFIE_CHECKS_FAILED, 'The capture expired — take a new selfie', { failed: ['live'] });
    let original: Buffer;
    try {
      original = await this.storage.getPrivate(c.storageKey);
    } catch {
      throw new AppError(ErrorCode.VALIDATION, 'The selfie was not uploaded');
    }
    if (original.length > SELFIE_LIMITS.maxBytes) throw new AppError(ErrorCode.SELFIE_CHECKS_FAILED, 'File too large', { failed: ['quality'] });
    let stats: { width: number; height: number; format: string; brightness: number; entropy: number; sharpness: number; hadMetadata: boolean };
    try {
      const img = sharp(original, { failOn: 'error', limitInputPixels: 40_000_000 });
      const meta = await img.metadata();
      const st = await sharp(original).rotate().greyscale().stats();
      stats = {
        width: meta.width ?? 0,
        height: meta.height ?? 0,
        format: meta.format ?? 'unknown',
        brightness: Math.round(st.channels[0].mean),
        entropy: Math.round(st.entropy * 100) / 100,
        sharpness: Math.round(st.sharpness * 100) / 100,
        hadMetadata: !!(meta.exif || meta.icc || meta.xmp),
      };
    } catch {
      throw new AppError(ErrorCode.SELFIE_CHECKS_FAILED, 'Not a readable photo', { failed: ['quality'] });
    }
    const failed = failedSelfieChecks(dto.deviceChecks, stats);
    if (failed.length) {
      await this.prisma.selfieChallenge.update({ where: { id: c.id }, data: { usedAt: new Date() } });
      throw new AppError(ErrorCode.SELFIE_CHECKS_FAILED, 'The selfie does not meet the criteria', { failed });
    }
    // never keep location or device metadata
    if (stats.hadMetadata) await this.storage.putPrivate(c.storageKey, await sharp(original).rotate().jpeg({ quality: 90 }).toBuffer(), 'image/jpeg');

    await this.prisma.$transaction(async (tx) => {
      const now = new Date();
      await tx.selfieChallenge.update({ where: { id: c.id }, data: { usedAt: now } });
      // a new selfie replaces one still waiting
      await tx.verificationRequest.updateMany({ where: { userId, type: 'LIVENESS', status: 'PENDING' }, data: { status: 'CANCELLED', reviewedAt: now } });
      await tx.verificationRequest.create({
        data: {
          userId,
          type: 'LIVENESS',
          selfieKey: c.storageKey,
          challengeGesture: c.gesture,
          preferFemaleReviewer: dto.preferFemaleReviewer ?? false,
          autoResult: { criteriaVersion: 1, device: { ...dto.deviceChecks }, image: stats, passed: ['oneFace', 'visible', 'straight', 'quality'] } as unknown as Prisma.InputJsonValue,
        },
      });
      await this.audit.record({ actorType: 'USER', actorId: userId, action: 'verification.selfie', entityType: 'user', entityId: userId }, tx);
    });
    // A profile already sent back for its selfie goes to review again with the new one.
    const last = await this.prisma.verificationRequest.findFirst({ where: { userId, type: 'PROFILE_REVIEW' }, orderBy: { submittedAt: 'desc' } });
    if (last?.status === 'REJECTED' && last.rejectCode?.startsWith('selfie_')) await this.submit(userId);
    return this.status(userId);
  }

  async status(userId: string) {
    const [selfie, last, badges, user] = await Promise.all([
      this.prisma.verificationRequest.findFirst({ where: { userId, type: 'LIVENESS', status: { not: 'CANCELLED' } }, orderBy: { submittedAt: 'desc' } }),
      this.prisma.verificationRequest.findFirst({ where: { userId, type: 'PROFILE_REVIEW' }, orderBy: { submittedAt: 'desc' } }),
      this.prisma.userVerification.findMany({ where: { userId, revokedAt: null }, select: { type: true, verifiedAt: true } }),
      this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { status: true } }),
    ]);
    return {
      accountStatus: user.status,
      request: last && { id: last.id, status: last.status, submittedAt: last.submittedAt, reviewedAt: last.reviewedAt, rejectCode: last.rejectCode, rejectReason: last.rejectReason },
      badges: {
        photosReviewed: badges.some((b) => b.type === 'PROFILE_REVIEW'),
        realPerson: badges.some((b) => b.type === 'LIVENESS'),
        identityVerified: badges.some((b) => b.type === 'IDENTITY'), // only set by an ID-check provider
      },
      canResubmit: last?.status === 'REJECTED',
      selfie: {
        required: !!(await this.settings.get('verification.selfieRequired', 1)) && !badges.some((b) => b.type === 'LIVENESS'),
        status: selfie?.status ?? null,
        rejectCode: selfie?.rejectCode ?? null,
        submittedAt: selfie?.submittedAt ?? null,
      },
    };
  }

  // ───────────── admin ─────────────

  queue(cursor?: string) {
    return this.prisma.verificationRequest.findMany({
      // profile reviews and stand-alone selfies (e.g. professionals); a member's selfie is decided with the profile
      where: { status: 'PENDING', type: { in: ['PROFILE_REVIEW', 'LIVENESS'] } },
      orderBy: { submittedAt: 'asc' },
      take: 50,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      select: { id: true, type: true, userId: true, submittedAt: true, preferFemaleReviewer: true, user: { select: { profile: { select: { displayName: true, countryCode: true, city: true } } } } },
    });
  }

  async detail(requestId: string) {
    const r = await this.prisma.verificationRequest.findUnique({ where: { id: requestId }, include: { user: { include: { profile: true, photos: { where: { deletedAt: null }, orderBy: { position: 'asc' } } } } } });
    if (!r) throw new AppError(ErrorCode.NOT_FOUND);
    const photos = await Promise.all(
      r.user.photos.map(async (p) => {
        const v = (p.variants ?? {}) as Record<string, string>;
        const key = v.full ?? p.storageKey;
        return { id: p.id, position: p.position, status: p.status, moderation: p.moderation, url: await this.storage.signedPrivateUrl(key.startsWith('p/') ? p.storageKey : key) };
      }),
    );
    const reports = await this.prisma.report.count({ where: { reportedUserId: r.userId } });
    // the selfie to compare with the photos (criteria C6–C8 are checked by the reviewer)
    const s = r.type === 'LIVENESS' ? r : await this.prisma.verificationRequest.findFirst({ where: { userId: r.userId, type: 'LIVENESS', status: { in: ['PENDING', 'APPROVED'] } }, orderBy: { submittedAt: 'desc' } });
    const selfie = s && {
      requestId: s.id,
      status: s.status,
      gesture: s.challengeGesture,
      preferFemaleReviewer: s.preferFemaleReviewer,
      checks: s.autoResult,
      url: s.selfieKey ? await this.storage.signedPrivateUrl(s.selfieKey) : null,
      criteria: SELFIE_CRITERIA,
    };
    return { id: r.id, type: r.type, status: r.status, submittedAt: r.submittedAt, autoResult: r.autoResult, profile: r.user.profile, accountStatus: r.user.status, photos, selfie, reportsAgainst: reports };
  }

  /** Approves a stand-alone selfie request. */
  private async approveSelfie(r: { id: string; userId: string }, admin: AuthAdmin) {
    await this.prisma.$transaction(async (tx) => {
      const now = new Date();
      await tx.verificationRequest.update({ where: { id: r.id }, data: { status: 'APPROVED', reviewedBy: admin.id, reviewedAt: now } });
      await tx.userVerification.upsert({
        where: { userId_type: { userId: r.userId, type: 'LIVENESS' } },
        create: { userId: r.userId, type: 'LIVENESS', reference: r.id },
        update: { revokedAt: null, verifiedAt: now, reference: r.id },
      });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'verification.selfie_approve', entityType: 'verification_request', entityId: r.id }, tx);
    });
    return this.status(r.userId);
  }

  /** APPROVED: publish photos to the CDN, grant the badge, activate the account, notify. */
  async approve(requestId: string, admin: AuthAdmin, dto: ApproveDto) {
    const r = await this.prisma.verificationRequest.findUnique({ where: { id: requestId } });
    if (!r || r.status !== 'PENDING') throw new AppError(ErrorCode.CONFLICT, 'Request is not pending');
    if (r.type === 'LIVENESS') return this.approveSelfie(r, admin);
    // the member's selfie is decided together with the profile
    const selfie = await this.prisma.verificationRequest.findFirst({ where: { userId: r.userId, type: 'LIVENESS', status: 'PENDING' } });
    if ((await this.settings.get('verification.selfieRequired', 1)) && !selfie && !(await this.hasSelfie(r.userId))) {
      throw new AppError(ErrorCode.SELFIE_REQUIRED, 'This profile has no selfie to compare — reject with selfie_not_live or wait');
    }
    const photos = await this.prisma.userPhoto.findMany({ where: { userId: r.userId, deletedAt: null, status: { in: ['PENDING_REVIEW', 'APPROVED'] } } });
    const rejectIds = new Set(dto.rejectPhotoIds ?? []);
    const toPublish = photos.filter((p) => p.status === 'PENDING_REVIEW' && !rejectIds.has(p.id));
    const minPhotos = await this.settings.get('profile.minPhotos', 2);
    if (photos.filter((p) => !rejectIds.has(p.id)).length < minPhotos) throw new AppError(ErrorCode.VALIDATION, `Approving requires at least ${minPhotos} photos`);

    // Copy to the public bucket BEFORE the DB commit, so approved = reachable.
    const published = new Map<string, Record<string, string>>();
    for (const p of toPublish) {
      const v = (p.variants ?? {}) as Record<string, string>;
      const out: Record<string, string> = {};
      for (const [name, key] of Object.entries(v)) {
        const publicKey = `p/${p.userId}/${p.id}/${name}.webp`;
        await this.storage.publish(key, publicKey);
        out[name] = publicKey;
      }
      published.set(p.id, out);
    }

    const pending = (r.autoResult as { pendingChanges?: { displayName?: string } } | null)?.pendingChanges;
    await this.prisma.$transaction(async (tx) => {
      const now = new Date();
      await tx.verificationRequest.update({ where: { id: r.id }, data: { status: 'APPROVED', reviewedBy: admin.id, reviewedAt: now } });
      for (const p of toPublish) {
        await tx.userPhoto.update({ where: { id: p.id }, data: { status: 'APPROVED', variants: published.get(p.id)!, reviewedAt: now } });
      }
      if (rejectIds.size) await tx.userPhoto.updateMany({ where: { id: { in: [...rejectIds] }, userId: r.userId }, data: { status: 'REJECTED', rejectReason: 'rejected_in_review', reviewedAt: now } });
      if (pending?.displayName) await tx.userProfile.update({ where: { userId: r.userId }, data: { displayName: pending.displayName } });
      if (selfie) {
        await tx.verificationRequest.update({ where: { id: selfie.id }, data: { status: 'APPROVED', reviewedBy: admin.id, reviewedAt: now } });
        await tx.userVerification.upsert({
          where: { userId_type: { userId: r.userId, type: 'LIVENESS' } },
          create: { userId: r.userId, type: 'LIVENESS', reference: selfie.id },
          update: { revokedAt: null, verifiedAt: now, reference: selfie.id },
        });
      }
      await tx.userVerification.upsert({
        where: { userId_type: { userId: r.userId, type: 'PROFILE_REVIEW' } },
        create: { userId: r.userId, type: 'PROFILE_REVIEW', reference: r.id },
        update: { revokedAt: null, verifiedAt: now, reference: r.id },
      });
      await tx.user.updateMany({ where: { id: r.userId, status: { in: ['PENDING_VERIFICATION', 'REJECTED'] } }, data: { status: 'ACTIVE' } });
      await tx.moderationAction.create({ data: { adminId: admin.id, targetUserId: r.userId, action: 'APPROVE_PROFILE', targetType: 'verification_request', targetId: r.id } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'verification.approve', entityType: 'verification_request', entityId: r.id, after: { publishedPhotos: toPublish.length, rejectedPhotos: rejectIds.size } }, tx);
      await this.notifications.notify(r.userId, 'VERIFICATION_APPROVED', 'push.verification_approved', {}, tx);
    });
    await this.notifications.push(r.userId, 'push.verification_approved', {});
    await this.profiles.refreshCompleteness(r.userId);
    return this.status(r.userId);
  }

  /** REJECTED: record the reason, notify, allow resubmission. */
  async reject(requestId: string, admin: AuthAdmin, dto: RejectDto) {
    const r = await this.prisma.verificationRequest.findUnique({ where: { id: requestId } });
    if (!r || r.status !== 'PENDING') throw new AppError(ErrorCode.CONFLICT, 'Request is not pending');
    await this.prisma.$transaction(async (tx) => {
      const now = new Date();
      await tx.verificationRequest.update({ where: { id: r.id }, data: { status: 'REJECTED', rejectCode: dto.code, rejectReason: dto.reason, reviewedBy: admin.id, reviewedAt: now } });
      // a selfie reason sends the selfie back too: the app asks for a new one (new gesture)
      if (dto.code.startsWith('selfie_') && r.type === 'PROFILE_REVIEW') {
        await tx.verificationRequest.updateMany({ where: { userId: r.userId, type: 'LIVENESS', status: 'PENDING' }, data: { status: 'REJECTED', rejectCode: dto.code, rejectReason: dto.reason, reviewedBy: admin.id, reviewedAt: now } });
      }
      if (dto.photoIds?.length) {
        await tx.userPhoto.updateMany({ where: { id: { in: dto.photoIds }, userId: r.userId }, data: { status: 'REJECTED', rejectReason: dto.code, reviewedAt: now } });
      }
      // A live account keeps its approved profile; a new one stays hidden.
      if (r.type === 'PROFILE_REVIEW') await tx.user.updateMany({ where: { id: r.userId, status: 'PENDING_VERIFICATION' }, data: { status: 'REJECTED' } });
      await tx.moderationAction.create({ data: { adminId: admin.id, targetUserId: r.userId, action: 'REJECT_PROFILE', targetType: 'verification_request', targetId: r.id, reason: `${dto.code}: ${dto.reason}` } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'verification.reject', entityType: 'verification_request', entityId: r.id, reason: dto.reason, after: { code: dto.code } }, tx);
      await this.notifications.notify(r.userId, 'VERIFICATION_REJECTED', 'push.verification_rejected', { code: dto.code }, tx);
    });
    await this.notifications.push(r.userId, 'push.verification_rejected', { code: dto.code });
    return this.status(r.userId);
  }
}

@ApiTags('verification')
@ApiBearerAuth()
@Controller('v1/me/verification')
export class VerificationController {
  constructor(private readonly v: VerificationService) {}

  @AllowPending() @Get()
  status(@CurrentUser() u: AuthUser) {
    return this.v.status(u.id);
  }

  @AllowPending() @RateLimit(10, 86400) @Post('submit') @HttpCode(200)
  submit(@CurrentUser() u: AuthUser) {
    return this.v.submit(u.id);
  }

  /** Selfie step 1: one-time capture with a random gesture (10 minutes). */
  @AllowPending() @RateLimit(12, 86400) @Post('selfie/challenge')
  selfieChallenge(@CurrentUser() u: AuthUser) {
    return this.v.selfieChallenge(u.id);
  }

  /** Selfie step 2: after the upload — automatic checks, then the verification team. */
  @AllowPending() @RateLimit(12, 86400) @Post('selfie') @HttpCode(200)
  selfie(@CurrentUser() u: AuthUser, @Body() dto: SelfieDto) {
    return this.v.submitSelfie(u.id, dto);
  }
}

@ApiTags('admin')
@ApiBearerAuth()
@Controller('v1/admin/verification')
export class AdminVerificationController {
  constructor(private readonly v: VerificationService) {}

  @RequirePermissions('verification.review') @Get('queue')
  queue(@Query('cursor') cursor?: string) {
    return this.v.queue(cursor);
  }

  @RequirePermissions('verification.review') @Get(':id')
  detail(@Param('id', ParseUUIDPipe) id: string) {
    return this.v.detail(id);
  }

  @RequirePermissions('verification.review') @Post(':id/approve') @HttpCode(200)
  approve(@Param('id', ParseUUIDPipe) id: string, @CurrentAdmin() a: AuthAdmin, @Body() dto: ApproveDto) {
    return this.v.approve(id, a, dto);
  }

  @RequirePermissions('verification.review') @Post(':id/reject') @HttpCode(200)
  reject(@Param('id', ParseUUIDPipe) id: string, @CurrentAdmin() a: AuthAdmin, @Body() dto: RejectDto) {
    return this.v.reject(id, a, dto);
  }
}

@Module({
  imports: [MediaModule, ProfilesModule],
  controllers: [VerificationController, AdminVerificationController],
  providers: [VerificationService],
})
export class VerificationModule {}
