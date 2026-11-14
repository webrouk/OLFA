import { Body, Controller, Get, HttpCode, Injectable, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Prisma } from '@prisma/client';
import { ArrayMaxSize, IsArray, IsIn, IsOptional, IsString, IsUUID, Length } from 'class-validator';
import { AppError, ErrorCode } from '../../common/errors';
import { AllowPending, AuthAdmin, AuthUser, CurrentAdmin, CurrentUser, RateLimit, RequirePermissions } from '../../common/http';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { MediaModule } from '../media/media.module';
import { StorageService } from '../media/storage.service';
import { NotificationsService } from '../notifications/notifications.module';
import { ProfilesModule, ProfilesService } from '../profiles/profiles.module';

/** Reject codes → localised text + fix steps live in the app (i18n), keyed by code. */
export const REJECT_CODES = ['photo_unclear', 'photo_not_you', 'photo_group', 'photo_inappropriate', 'photo_filtered', 'bio_contact_info', 'bio_inappropriate', 'name_invalid', 'suspected_fake', 'other'] as const;

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

  async status(userId: string) {
    const [last, badges, user] = await Promise.all([
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
    };
  }

  // ───────────── admin ─────────────

  queue(cursor?: string) {
    return this.prisma.verificationRequest.findMany({
      where: { status: 'PENDING', type: 'PROFILE_REVIEW' },
      orderBy: { submittedAt: 'asc' },
      take: 50,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      select: { id: true, userId: true, submittedAt: true, user: { select: { profile: { select: { displayName: true, countryCode: true, city: true } } } } },
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
    return { id: r.id, status: r.status, submittedAt: r.submittedAt, autoResult: r.autoResult, profile: r.user.profile, accountStatus: r.user.status, photos, reportsAgainst: reports };
  }

  /** APPROVED: publish photos to the CDN, grant the badge, activate the account, notify. */
  async approve(requestId: string, admin: AuthAdmin, dto: ApproveDto) {
    const r = await this.prisma.verificationRequest.findUnique({ where: { id: requestId } });
    if (!r || r.status !== 'PENDING') throw new AppError(ErrorCode.CONFLICT, 'Request is not pending');
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
      if (dto.photoIds?.length) {
        await tx.userPhoto.updateMany({ where: { id: { in: dto.photoIds }, userId: r.userId }, data: { status: 'REJECTED', rejectReason: dto.code, reviewedAt: now } });
      }
      // A live account keeps its approved profile; a new one stays hidden.
      await tx.user.updateMany({ where: { id: r.userId, status: 'PENDING_VERIFICATION' }, data: { status: 'REJECTED' } });
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
