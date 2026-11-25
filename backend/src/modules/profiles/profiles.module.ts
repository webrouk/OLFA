import { Body, Controller, Delete, Get, HttpCode, Inject, Injectable, Module, Param, ParseUUIDPipe, Patch, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Prisma } from '@prisma/client';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode, fromPgError } from '../../common/errors';
import { AllowPending, AuthUser, CurrentUser, MembersOnly, Public, RateLimit } from '../../common/http';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { ageOn, profileCompleteness } from '../../domain/security';
import { profileInclude, toOwnProfile, toPublicProfile } from './profile.mapper';
import { AccountTypeDto, CreateProfileDto, DeleteAccountDto, FreezeDto, LocaleDto, PreferencesDto, PrivacyDto, UpdateProfileDto, LocationDto } from './profiles.dto';
import { privacyOf } from '../../domain/privacy';
import { EntitlementsService } from '../quotas/quotas.module';
import { defaultNationality, isQualifiedSect, isSectOf } from '../../domain/reference';
import { roundCoord } from '../../domain/proximity';

@Injectable()
export class ProfilesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    private readonly entitlements: EntitlementsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async me(userId: string) {
    const u = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, include: profileInclude });
    if (!u.profile) return { id: u.id, accountType: u.accountType, status: u.status, profile: null, preferences: null };
    const prefs = await this.prisma.userPreference.findUnique({ where: { userId } });
    return { ...toOwnProfile(u, this.env.CDN_BASE_URL), accountType: u.accountType, preferences: prefs };
  }

  /**
   * Sign-up step after gender: marriage member, psychologist or family
   * counselor. Can be changed until a profile is created, then it is locked
   * (DB trigger) — a professional and a member are separate accounts.
   */
  async setAccountType(userId: string, dto: AccountTypeDto) {
    await this.prisma.user.update({ where: { id: userId }, data: { accountType: dto.accountType } }).catch((e: unknown) => {
      throw fromPgError(e) ?? e;
    });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'account.type', entityType: 'user', entityId: userId, after: { accountType: dto.accountType } });
    return { accountType: dto.accountType };
  }

  private religionFields(dto: { religion?: string; sect?: string | null; religionConsent?: boolean }, current?: { religionConsentAt: Date | null }) {
    if (dto.religion === undefined) {
      if (dto.sect !== undefined) throw new AppError(ErrorCode.VALIDATION, 'Send the religion with the sect');
      return {};
    }
    const sect = dto.sect ?? null;
    if (sect && !isSectOf(dto.religion, sect)) throw new AppError(ErrorCode.VALIDATION, 'The sect does not belong to the chosen religion');
    const needsConsent = dto.religion !== 'undisclosed';
    if (needsConsent && !dto.religionConsent && !current?.religionConsentAt) throw new AppError(ErrorCode.VALIDATION, 'Consent is required to save your religion');
    return {
      religion: dto.religion,
      sect: dto.religion === 'undisclosed' ? null : sect,
      religionConsentAt: needsConsent ? current?.religionConsentAt ?? new Date() : null,
    };
  }

  async create(userId: string, dto: CreateProfileDto) {
    const minAge = await this.settings.get('profile.minAge', 18);
    const birth = new Date(`${dto.birthDate}T00:00:00Z`);
    if (ageOn(birth, new Date()) < minAge) throw new AppError(ErrorCode.UNDERAGE);
    const interestIds = await this.interestIds(dto.interests);
    const religion = this.religionFields(dto);
    const acct = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { accountType: true } });
    if (acct.accountType && acct.accountType !== 'MEMBER') throw new AppError(ErrorCode.FORBIDDEN, 'Professional accounts complete the professional profile instead');

    await this.prisma.$transaction(async (tx) => {
      const exists = await tx.userProfile.findUnique({ where: { userId }, select: { userId: true } });
      if (exists) throw new AppError(ErrorCode.CONFLICT, 'Profile already exists');
      await tx.userProfile.create({
        data: {
          userId,
          displayName: dto.displayName.trim(),
          birthDate: birth,
          gender: dto.gender,
          countryCode: dto.countryCode,
          nationality: dto.nationality ?? defaultNationality(dto.countryCode),
          city: dto.city.trim(),
          showLocation: dto.showLocation ?? true,
          maritalStatus: dto.maritalStatus,
          hasChildren: dto.hasChildren,
          wantsChildren: dto.wantsChildren,
          education: dto.education,
          occupation: dto.occupation,
          heightCm: dto.heightCm ?? null,
          weightKg: dto.weightKg ?? null,
          ...religion,
          marriageTimeline: dto.marriageTimeline,
          smoking: dto.smoking,
          willingToRelocate: dto.willingToRelocate,
          bio: dto.bio.trim(),
          completeness: profileCompleteness({ bio: dto.bio, interests: interestIds.length, approvedPhotos: 0, occupation: dto.occupation, hasLifestyle: dto.smoking != null }),
        },
      });
      await tx.userInterest.createMany({ data: interestIds.map((interestId) => ({ userId, interestId })) });
      await tx.userPreference.upsert({ where: { userId }, create: { userId, ageMin: Math.max(18, ageOn(birth, new Date()) - 6), ageMax: Math.min(99, ageOn(birth, new Date()) + 8) }, update: {} });
      await tx.user.update({ where: { id: userId }, data: { ageConfirmedAt: new Date(), termsVersion: dto.termsVersion, termsAcceptedAt: new Date() } });
    });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'profile.create', entityType: 'user', entityId: userId });
    return this.me(userId);
  }

  async update(userId: string, dto: UpdateProfileDto) {
    if (dto.gender !== undefined || dto.birthDate !== undefined) {
      throw new AppError(ErrorCode.FORBIDDEN, 'Gender and birth date can only be changed through Support');
    }
    const current = await this.prisma.userProfile.findUnique({ where: { userId } });
    if (!current) throw new AppError(ErrorCode.NOT_FOUND, 'Create the profile first');
    const reReview = await this.settings.get('profile.reReviewOnNameOrPhotoChange', true);
    const nameChanged = dto.displayName !== undefined && dto.displayName.trim() !== current.displayName;

    const data: Prisma.UserProfileUpdateInput = {
      city: dto.city?.trim(),
      countryCode: dto.countryCode,
      nationality: dto.nationality,
      showLocation: dto.showLocation,
      maritalStatus: dto.maritalStatus,
      hasChildren: dto.hasChildren,
      wantsChildren: dto.wantsChildren,
      education: dto.education,
      occupation: dto.occupation,
      heightCm: dto.heightCm,
      weightKg: dto.weightKg,
      marriageTimeline: dto.marriageTimeline,
      smoking: dto.smoking,
      willingToRelocate: dto.willingToRelocate,
      bio: dto.bio?.trim(),
      ...this.religionFields(dto, current),
      // A name change waits for review when the account is already live.
      displayName: nameChanged && !reReview ? dto.displayName!.trim() : undefined,
    };

    await this.prisma.$transaction(async (tx) => {
      await tx.userProfile.update({ where: { userId }, data });
      if (dto.interests) {
        const ids = await this.interestIds(dto.interests);
        await tx.userInterest.deleteMany({ where: { userId } });
        await tx.userInterest.createMany({ data: ids.map((interestId) => ({ userId, interestId })) });
      }
      if (nameChanged && reReview) {
        const pendingChanges = { pendingChanges: { displayName: dto.displayName!.trim() } };
        const open = await tx.verificationRequest.findFirst({ where: { userId, type: 'PROFILE_REVIEW', status: 'PENDING' }, select: { id: true } });
        if (open) await tx.verificationRequest.update({ where: { id: open.id }, data: { autoResult: pendingChanges } });
        else await tx.verificationRequest.create({ data: { userId, type: 'PROFILE_REVIEW', autoResult: pendingChanges } });
      }
    });
    await this.refreshCompleteness(userId);
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'profile.update', entityType: 'user', entityId: userId, after: { ...dto } });
    return this.me(userId);
  }

  async preferences(userId: string) {
    const p = await this.prisma.userPreference.findUnique({ where: { userId } });
    return (
      p ?? { userId, ageMin: 18, ageMax: 60, sameCountryOnly: false, countryCodes: [], cities: [], maritalStatuses: [], educationLevels: [], occupations: [], wantsChildren: null, religions: [], sects: [], updatedAt: null }
    );
  }

  async setPreferences(userId: string, dto: PreferencesDto) {
    if (dto.ageMin > dto.ageMax) throw new AppError(ErrorCode.VALIDATION, 'ageMin must be <= ageMax');
    const religions = dto.religions ?? [];
    const sects = dto.sects ?? [];
    if (sects.some((x) => !isQualifiedSect(x) || (religions.length > 0 && !religions.includes(x.split('.')[0])))) {
      throw new AppError(ErrorCode.VALIDATION, 'Each sect must belong to one of the accepted religions');
    }
    const data = {
      ageMin: dto.ageMin,
      ageMax: dto.ageMax,
      sameCountryOnly: dto.sameCountryOnly ?? false,
      countryCodes: dto.countryCodes ?? [],
      cities: dto.cities ?? [],
      maritalStatuses: dto.maritalStatuses ?? [],
      educationLevels: dto.educationLevels ?? [],
      occupations: dto.occupations ?? [],
      wantsChildren: dto.wantsChildren ?? null,
      religions,
      sects,
    };
    // Preference changes invalidate cached scores for this viewer.
    await this.prisma.$transaction([
      this.prisma.userPreference.upsert({ where: { userId }, create: { userId, ...data }, update: data }),
      this.prisma.compatibilityScore.deleteMany({ where: { viewerId: userId } }),
    ]);
    return this.prisma.userPreference.findUnique({ where: { userId } });
  }

  /** Public profile for another user — never exposes private fields. */
  /** Stores an approximate location (2 decimals ≈ 1 km) for "nearest first". */
  async setLocation(userId: string, dto: LocationDto) {
    const lat = roundCoord(dto.latitude), lng = roundCoord(dto.longitude);
    const acct = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { accountType: true } });
    if (acct.accountType === 'PSYCHOLOGIST' || acct.accountType === 'FAMILY_COUNSELOR') {
      // professionals: used to show counselors near the client and their country
      await this.prisma.counselorProfile.update({ where: { userId }, data: { latitude: lat, longitude: lng, countryCode: dto.countryCode ?? undefined } });
      return { locationCountry: dto.countryCode ?? null };
    }
    await this.prisma.userProfile.update({
      where: { userId },
      data: { latitude: lat, longitude: lng, locationCountry: dto.countryCode ?? undefined, locationUpdatedAt: new Date() },
    });
    return { locationCountry: dto.countryCode ?? null };
  }

  async privacy(userId: string) {
    const [row, p] = await Promise.all([
      this.prisma.userPrivacySettings.findUnique({ where: { userId } }),
      this.prisma.userProfile.findUnique({ where: { userId }, select: { showLocation: true } }),
    ]);
    return { ...privacyOf(row), showCity: p?.showLocation ?? true };
  }

  /** Applied by every endpoint that shows one member to another (discovery, profiles, chat). */
  async setPrivacy(userId: string, dto: PrivacyDto) {
    if (dto.incognito === true) {
      const ent = await this.entitlements.forUser(userId);
      if (!ent.incognito) throw new AppError(ErrorCode.ENTITLEMENT_REQUIRED, 'Incognito is a Premium feature', { feature: 'incognito' });
    }
    const { showCity, ...rest } = dto;
    await this.prisma.$transaction(async (tx) => {
      await tx.userPrivacySettings.upsert({ where: { userId }, create: { userId, ...rest }, update: rest });
      if (showCity !== undefined) await tx.userProfile.updateMany({ where: { userId }, data: { showLocation: showCity } });
    });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'privacy.update', entityType: 'user', entityId: userId, after: dto as Record<string, unknown> });
    return this.privacy(userId);
  }

  /**
   * Temporary freeze instead of deletion: hidden from discovery, likes and
   * search; matches, conversations, photos and the subscription stay as they
   * are. Store subscriptions keep renewing until cancelled in the store.
   */
  async freeze(userId: string, reason?: string) {
    await this.prisma.user.update({ where: { id: userId }, data: { frozenAt: new Date(), freezeReason: reason ?? null } });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'user.freeze', entityType: 'user', entityId: userId, reason });
    return { frozen: true };
  }

  /** Push notifications and SMS use the same language as the app. */
  async setLocale(userId: string, locale: 'ar' | 'en' | 'fr') {
    await this.prisma.user.update({ where: { id: userId }, data: { locale } });
    return { locale };
  }

  /**
   * Personal data export (JSON): profile, preferences, privacy, photos
   * metadata, likes sent, matches, own messages and payments.
   */
  async exportData(userId: string) {
    const [me, likes, matches, messages, payments, consultations] = await Promise.all([
      this.me(userId),
      this.prisma.like.findMany({ where: { fromUserId: userId }, select: { toUserId: true, createdAt: true, compliment: true } }),
      this.prisma.match.findMany({ where: { OR: [{ userAId: userId }, { userBId: userId }] }, select: { id: true, status: true, createdAt: true, endedAt: true } }),
      this.prisma.message.findMany({ where: { senderId: userId, deletedAt: null }, select: { conversationId: true, body: true, createdAt: true }, orderBy: { createdAt: 'asc' } }),
      this.prisma.payment.findMany({ where: { userId }, select: { provider: true, amountMinor: true, currency: true, status: true, createdAt: true } }),
      this.prisma.consultation.findMany({ where: { clientId: userId }, select: { id: true, service: true, language: true, durationMinutes: true, status: true, createdAt: true } }),
    ]);
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'user.export', entityType: 'user', entityId: userId });
    return { exportedAt: new Date(), account: me, likesSent: likes, matches, messagesSent: messages, payments, consultations };
  }

  async unfreeze(userId: string) {
    await this.prisma.user.update({ where: { id: userId }, data: { frozenAt: null, freezeReason: null, lastActiveAt: new Date() } });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'user.unfreeze', entityType: 'user', entityId: userId });
    return this.me(userId);
  }

  async publicProfile(viewerId: string, targetId: string) {
    if (viewerId === targetId) throw new AppError(ErrorCode.NOT_FOUND);
    const blocked = await this.prisma.blockedUser.findFirst({
      where: { OR: [{ blockerId: viewerId, blockedId: targetId }, { blockerId: targetId, blockedId: viewerId }] },
    });
    if (blocked) throw new AppError(ErrorCode.NOT_FOUND);
    const u = await this.prisma.user.findFirst({ where: { id: targetId, status: 'ACTIVE', deletedAt: null, frozenAt: null }, include: profileInclude });
    if (!u?.profile) throw new AppError(ErrorCode.NOT_FOUND);
    const [a, b] = [viewerId, targetId].sort();
    const [score, viewer, match] = await Promise.all([
      this.prisma.compatibilityScore.findUnique({ where: { viewerId_candidateId: { viewerId, candidateId: targetId } }, select: { score: true } }),
      this.prisma.userPrivacySettings.findUnique({ where: { userId: viewerId } }),
      this.prisma.match.findUnique({ where: { userAId_userBId: { userAId: a, userBId: b } }, select: { status: true } }),
    ]);
    return toPublicProfile(u, this.env.CDN_BASE_URL, { compatibility: score?.score, viewer: privacyOf(viewer), matched: match?.status === 'ACTIVE' });
  }

  async refreshCompleteness(userId: string) {
    const p = await this.prisma.userProfile.findUnique({ where: { userId } });
    if (!p) return;
    const [interests, approvedPhotos] = await Promise.all([
      this.prisma.userInterest.count({ where: { userId } }),
      this.prisma.userPhoto.count({ where: { userId, status: 'APPROVED', deletedAt: null } }),
    ]);
    await this.prisma.userProfile.update({
      where: { userId },
      data: { completeness: profileCompleteness({ bio: p.bio, interests, approvedPhotos, occupation: p.occupation, hasLifestyle: p.smoking != null }) },
    });
  }

  /** Hide now, purge after 30 days (worker job, Phase 4). Signing in within 30 days restores. */
  async requestDeletion(userId: string, reason?: string) {
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: userId }, data: { deletionRequestedAt: new Date() } }),
      this.prisma.userSession.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date(), revokedReason: 'account_deletion' } }),
    ]);
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'user.delete_request', entityType: 'user', entityId: userId, reason });
  }

  listInterests() {
    return this.prisma.interest.findMany({ where: { isActive: true }, select: { key: true, nameAr: true, nameEn: true, category: true, isBasic: true }, orderBy: { id: 'asc' } });
  }

  private async interestIds(keys: string[]): Promise<number[]> {
    const rows = await this.prisma.interest.findMany({ where: { key: { in: keys }, isActive: true }, select: { id: true } });
    if (rows.length !== new Set(keys).size) throw new AppError(ErrorCode.VALIDATION, 'Unknown interest', { field: 'interests' });
    return rows.map((r) => r.id);
  }
}

@ApiTags('profiles')
@ApiBearerAuth()
@Controller('v1')
export class ProfilesController {
  constructor(private readonly profiles: ProfilesService) {}

  @AllowPending() @Get('me')
  me(@CurrentUser() u: AuthUser) {
    return this.profiles.me(u.id);
  }

  @AllowPending() @RateLimit(20, 3600) @Put('me/account-type') @HttpCode(200)
  setAccountType(@CurrentUser() u: AuthUser, @Body() dto: AccountTypeDto) {
    return this.profiles.setAccountType(u.id, dto);
  }

  @AllowPending() @MembersOnly() @RateLimit(10, 3600) @Post('me/profile')
  create(@CurrentUser() u: AuthUser, @Body() dto: CreateProfileDto) {
    return this.profiles.create(u.id, dto);
  }

  @AllowPending() @RateLimit(30, 3600) @Patch('me/profile')
  update(@CurrentUser() u: AuthUser, @Body() dto: UpdateProfileDto) {
    return this.profiles.update(u.id, dto);
  }

  /** Saved partner preferences (defaults when none yet) — the app's "Partner preferences" page edits these. */
  @AllowPending() @MembersOnly() @Get('me/preferences')
  getPreferences(@CurrentUser() u: AuthUser) {
    return this.profiles.preferences(u.id);
  }

  @AllowPending() @MembersOnly() @Put('me/preferences') @HttpCode(200)
  preferences(@CurrentUser() u: AuthUser, @Body() dto: PreferencesDto) {
    return this.profiles.setPreferences(u.id, dto);
  }

  @AllowPending() @Get('me/privacy')
  getPrivacy(@CurrentUser() u: AuthUser) {
    return this.profiles.privacy(u.id);
  }

  @AllowPending() @RateLimit(60, 3600) @Put('me/privacy') @HttpCode(200)
  putPrivacy(@CurrentUser() u: AuthUser, @Body() dto: PrivacyDto) {
    return this.profiles.setPrivacy(u.id, dto);
  }

  /** Take a break instead of deleting: everything is kept, including the subscription. */
  @AllowPending() @RateLimit(10, 86400) @Post('me/freeze') @HttpCode(200)
  freeze(@CurrentUser() u: AuthUser, @Body() dto: FreezeDto) {
    return this.profiles.freeze(u.id, dto.reason);
  }

  @AllowPending() @Put('me/locale') @HttpCode(200)
  locale(@CurrentUser() u: AuthUser, @Body() dto: LocaleDto) {
    return this.profiles.setLocale(u.id, dto.locale);
  }

  @AllowPending() @RateLimit(5, 86400) @Get('me/export')
  export(@CurrentUser() u: AuthUser) {
    return this.profiles.exportData(u.id);
  }

  @AllowPending() @Post('me/unfreeze') @HttpCode(200)
  unfreeze(@CurrentUser() u: AuthUser) {
    return this.profiles.unfreeze(u.id);
  }

  @AllowPending() @RateLimit(60, 3600) @Put('me/location') @HttpCode(200)
  location(@CurrentUser() u: AuthUser, @Body() dto: LocationDto) {
    return this.profiles.setLocation(u.id, dto);
  }

  @MembersOnly() @RateLimit(300, 3600) @Get('profiles/:id')
  profile(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.profiles.publicProfile(u.id, id);
  }

  @AllowPending() @Delete('me') @HttpCode(204)
  async deleteMe(@CurrentUser() u: AuthUser, @Body() body: DeleteAccountDto) {
    await this.profiles.requestDeletion(u.id, body?.reason);
  }

  @Public() @Get('interests')
  interests() {
    return this.profiles.listInterests();
  }
}

@Module({ controllers: [ProfilesController], providers: [ProfilesService], exports: [ProfilesService] })
export class ProfilesModule {}
