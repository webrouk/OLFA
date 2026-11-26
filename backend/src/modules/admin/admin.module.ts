import { Body, Controller, Get, HttpCode, Inject, Injectable, Module, Param, ParseEnumPipe, ParseUUIDPipe, Post, Put, Query } from '@nestjs/common';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { PlanCode, Prisma } from '@prisma/client';
import * as argon2 from 'argon2';
import { Type } from 'class-transformer';
import { IsBoolean, IsDateString, IsEmail, IsIn, IsInt, IsObject, IsOptional, IsString, Length, Max, Min, ValidateNested } from 'class-validator';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { AdminMfaSetup, AuthAdmin, CurrentAdmin, OlfaRequest, Public, RateLimit, Req, RequirePermissions } from '../../common/http';
import * as box from '../../domain/payout';
import { newTotpSecret, otpauthUrl, verifyTotp } from '../../domain/totp';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { parseWeights } from '../../domain/matching';
import { adsForMember, ADS_LIMITS, AdContentRating, invalidAdsFields, parseAdsSettings } from '../../domain/ads';
import { EntitlementsService } from '../quotas/quotas.module';

class AdminLoginDto {
  @ApiProperty() @IsEmail() email: string;
  @ApiProperty() @IsString() @Length(12, 200) password: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(6, 6) totp?: string;
}

/** Admin panel: close an account permanently, or for a period (until a date). */
class TotpCodeDto {
  @ApiProperty() @IsString() @Length(6, 6) code!: string;
}

class UsersQuery {
  @ApiPropertyOptional({ description: 'name, phone or user id' }) @IsOptional() @IsString() @Length(1, 80) q?: string;
  @ApiPropertyOptional() @IsOptional() @IsIn(['PENDING_VERIFICATION', 'ACTIVE', 'REJECTED', 'SUSPENDED', 'RESTRICTED', 'BANNED', 'DELETED']) status?: string;
  @ApiPropertyOptional() @IsOptional() @IsIn(['MEMBER', 'PSYCHOLOGIST', 'FAMILY_COUNSELOR']) accountType?: string;
  @ApiPropertyOptional({ default: 1 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) page = 1;
}

class ReportsQuery {
  @ApiPropertyOptional() @IsOptional() @IsIn(['OPEN', 'IN_REVIEW', 'ACTION_TAKEN', 'DISMISSED']) status?: string;
}

class ResolveReportDto {
  @ApiProperty({ enum: ['ACTION_TAKEN', 'DISMISSED'] }) @IsIn(['ACTION_TAKEN', 'DISMISSED']) status!: 'ACTION_TAKEN' | 'DISMISSED';
  @ApiProperty() @IsString() @Length(3, 300) resolution!: string;
}

class RestrictDto {
  @ApiProperty({ enum: ['ban', 'suspend'] }) @IsIn(['ban', 'suspend']) action!: 'ban' | 'suspend';
  /** Required for 'suspend' with a period; omitted = until lifted by an admin. */
  @ApiPropertyOptional() @IsOptional() @IsDateString() until?: string;
  /** Shown to the user on the closed-account screen. */
  @ApiProperty() @IsString() @Length(3, 300) reason!: string;
}
class UnrestrictDto {
  @ApiProperty() @IsString() @Length(3, 300) reason!: string;
}

class WeightsDto {
  @ApiProperty() @IsInt() @Min(0) @Max(100) interests: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) timeline: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) location: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) lifestyle: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) education: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) preferenceFit: number;
}

class EntitlementsDto {
  @ApiProperty({ example: { daily_likes: 10, daily_messages: 1, advanced_filters: false } }) @IsObject() values: Record<string, number | boolean>;
}

const FEATURE_KEYS: Record<string, 'number' | 'boolean'> = {
  daily_likes: 'number',
  daily_messages: 'number',
  daily_undos: 'number',
  advanced_filters: 'boolean',
  see_who_liked_you: 'boolean',
  incognito: 'boolean',
  priority_visibility: 'boolean',
  show_ads: 'boolean', // Free plan only — refused for paid plans here and by a DB trigger
  // counselor plans (DB trigger P0077: only on FREE = off, and PRO_* plans)
  directory_boost: 'number',
  featured_badge: 'boolean',
  profile_insights: 'boolean',
};
const PRO_KEYS = new Set(['directory_boost', 'featured_badge', 'profile_insights']);

class AdUnitsDto {
  @ApiProperty({ description: 'AdMob native ad unit id for Android, or empty' }) @IsString() @Length(0, 60) android!: string;
  @ApiProperty({ description: 'AdMob native ad unit id for iOS, or empty' }) @IsString() @Length(0, 60) ios!: string;
}

class AdsDto {
  @ApiProperty() @IsBoolean() enabled!: boolean;
  @ApiProperty({ description: 'Show ads to Free-plan members (paid plans never see ads)' }) @IsBoolean() freePlanShowsAds!: boolean;
  @ApiProperty() @IsInt() @Min(ADS_LIMITS.firstAfter[0]) @Max(ADS_LIMITS.firstAfter[1]) firstAfter!: number;
  @ApiProperty() @IsInt() @Min(ADS_LIMITS.interval[0]) @Max(ADS_LIMITS.interval[1]) interval!: number;
  @ApiProperty() @IsInt() @Min(ADS_LIMITS.maxPerSession[0]) @Max(ADS_LIMITS.maxPerSession[1]) maxPerSession!: number;
  @ApiProperty() @IsInt() @Min(ADS_LIMITS.preloadAhead[0]) @Max(ADS_LIMITS.preloadAhead[1]) preloadAhead!: number;
  @ApiProperty() @IsBoolean() personalized!: boolean;
  @ApiProperty({ enum: ['G', 'PG', 'T', 'MA'] }) @IsIn(['G', 'PG', 'T', 'MA']) maxAdContentRating!: AdContentRating;
  @ApiProperty({ type: AdUnitsDto }) @ValidateNested() @Type(() => AdUnitsDto) units!: AdUnitsDto;
}

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly settings: SettingsService,
    private readonly entitlements: EntitlementsService,
    private readonly audit: AuditService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async login(dto: AdminLoginDto, ipHash: string) {
    const admin = await this.prisma.adminUser.findUnique({ where: { email: dto.email.toLowerCase() } });
    // Constant-ish work whether or not the account exists.
    const ok = admin?.isActive ? await argon2.verify(admin.passwordHash, dto.password) : (await argon2.hash(dto.password), false);
    if (!admin || !ok) throw new AppError(ErrorCode.UNAUTHORIZED);
    // Two-factor: once set up, every sign-in needs the current authenticator code (used once).
    let mfa = false;
    if (admin.totpConfirmedAt && admin.totpSecretEnc) {
      if (!dto.totp) throw new AppError(ErrorCode.UNAUTHORIZED, 'Authenticator code required', { totpRequired: true });
      const step = verifyTotp(this.totpSecret(admin.totpSecretEnc), dto.totp);
      if (step === null || (admin.totpLastStep !== null && BigInt(step) <= admin.totpLastStep)) {
        await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'admin.login_totp_failed', entityType: 'admin', entityId: admin.id, ipHash });
        throw new AppError(ErrorCode.UNAUTHORIZED, 'Invalid authenticator code', { totpRequired: true });
      }
      await this.prisma.adminUser.update({ where: { id: admin.id }, data: { totpLastStep: BigInt(step) } });
      mfa = true;
    }
    await this.prisma.adminUser.update({ where: { id: admin.id }, data: { lastLoginAt: new Date() } });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'admin.login', entityType: 'admin', entityId: admin.id, ipHash });
    return { accessToken: await this.token(admin.id, mfa), mfa, totpSetupRequired: !mfa && this.env.ADMIN_REQUIRE_TOTP };
  }

  private token(id: string, mfa: boolean) {
    return this.jwt.signAsync({ sub: id, typ: 'admin', mfa }, { secret: this.env.ADMIN_JWT_SECRET, expiresIn: '8h' });
  }

  private totpKey() {
    if (!this.env.ADMIN_TOTP_KEY) throw new AppError(ErrorCode.INVALID_STATE, 'ADMIN_TOTP_KEY is not configured on the server');
    return Buffer.from(this.env.ADMIN_TOTP_KEY, 'base64');
  }

  private totpSecret(enc: string) {
    return box.open(this.totpKey(), Buffer.from(enc, 'base64'), 'olfa:admin-totp');
  }

  async me(a: AuthAdmin) {
    const x = await this.prisma.adminUser.findUniqueOrThrow({ where: { id: a.id }, select: { id: true, email: true, name: true, totpConfirmedAt: true, lastLoginAt: true } });
    return { ...x, totpEnrolled: !!x.totpConfirmedAt, permissions: a.permissions };
  }

  /** Step 1 of two-factor set-up: a new secret for the authenticator app (QR / key). */
  async totpSetup(a: AuthAdmin) {
    const x = await this.prisma.adminUser.findUniqueOrThrow({ where: { id: a.id }, select: { email: true, totpConfirmedAt: true } });
    if (x.totpConfirmedAt) throw new AppError(ErrorCode.CONFLICT, 'Two-factor sign-in is already set up');
    const secret = newTotpSecret();
    await this.prisma.adminUser.update({ where: { id: a.id }, data: { totpSecretEnc: box.seal(this.totpKey(), secret, 'olfa:admin-totp').toString('base64'), totpLastStep: null } });
    return { secret, otpauthUrl: otpauthUrl(secret, x.email) };
  }

  /** Step 2: the first valid code confirms it; returns a full (two-factor) session. */
  async totpConfirm(a: AuthAdmin, dto: TotpCodeDto) {
    const x = await this.prisma.adminUser.findUniqueOrThrow({ where: { id: a.id }, select: { totpSecretEnc: true, totpConfirmedAt: true } });
    if (x.totpConfirmedAt || !x.totpSecretEnc) throw new AppError(ErrorCode.INVALID_STATE);
    const step = verifyTotp(this.totpSecret(x.totpSecretEnc), dto.code);
    if (step === null) throw new AppError(ErrorCode.VALIDATION, 'Invalid authenticator code', { field: 'code' });
    await this.prisma.adminUser.update({ where: { id: a.id }, data: { totpConfirmedAt: new Date(), totpLastStep: BigInt(step) } });
    await this.audit.record({ actorType: 'ADMIN', actorId: a.id, action: 'admin.totp_enabled', entityType: 'admin', entityId: a.id });
    return { accessToken: await this.token(a.id, true), mfa: true };
  }

  /** Overview counters for the dashboard home. */
  async stats() {
    const day = 86_400_000;
    const n = (q: Promise<number>) => q;
    const [users, active, pendingProfiles, pendingSelfies, newUsers7d, reports, tickets, disputes, withdrawals, counselors, banned, suspended] = await Promise.all([
      n(this.prisma.user.count({ where: { deletedAt: null } })),
      n(this.prisma.user.count({ where: { deletedAt: null, status: 'ACTIVE', lastActiveAt: { gt: new Date(Date.now() - 7 * day) } } })),
      n(this.prisma.verificationRequest.count({ where: { status: 'PENDING', type: 'PROFILE_REVIEW' } })),
      n(this.prisma.verificationRequest.count({ where: { status: 'PENDING', type: 'LIVENESS' } })),
      n(this.prisma.user.count({ where: { createdAt: { gt: new Date(Date.now() - 7 * day) } } })),
      n(this.prisma.report.count({ where: { status: { in: ['OPEN', 'IN_REVIEW'] } } })),
      n(this.prisma.supportTicket.count({ where: { status: 'OPEN' } })),
      n(this.prisma.consultation.count({ where: { escrowStatus: 'DISPUTED' } })),
      n(this.prisma.withdrawal.count({ where: { status: { in: ['REQUESTED', 'PROCESSING'] } } })),
      n(this.prisma.counselorProfile.count({ where: { status: 'PENDING' } })),
      n(this.prisma.user.count({ where: { status: 'BANNED' } })),
      n(this.prisma.user.count({ where: { status: 'SUSPENDED' } })),
    ]);
    return { users, activeLast7Days: active, newUsers7d, banned, suspended, queues: { profiles: pendingProfiles, selfies: pendingSelfies, reports, tickets, disputes, withdrawals, counselors } };
  }

  /** User search (name, phone or id); phone numbers are masked except the last 4 digits. */
  async users(q: UsersQuery) {
    const take = 25;
    const term = q.q?.trim();
    const where: Prisma.UserWhereInput = {
      ...(q.status ? { status: q.status as Prisma.UserWhereInput['status'] } : { deletedAt: null }),
      ...(q.accountType ? { accountType: q.accountType as Prisma.UserWhereInput['accountType'] } : {}),
      ...(term
        ? {
            OR: [
              ...(/^[0-9a-f-]{36}$/i.test(term) ? [{ id: term }] : []),
              ...(/^\+?[0-9 ]{4,}$/.test(term) ? [{ phoneE164: { contains: term.replace(/\s/g, '') } }] : []),
              { profile: { displayName: { contains: term, mode: 'insensitive' as const } } },
            ],
          }
        : {}),
    };
    const [total, rows] = await Promise.all([
      this.prisma.user.count({ where }),
      this.prisma.user.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (q.page - 1) * take,
        take,
        select: { id: true, phoneE164: true, status: true, accountType: true, createdAt: true, lastActiveAt: true, suspendedUntil: true, profile: { select: { displayName: true, gender: true, countryCode: true, city: true } } },
      }),
    ]);
    return { total, page: q.page, pageSize: take, items: rows.map(({ phoneE164, ...r }) => ({ ...r, phone: maskPhone(phoneE164) })) };
  }

  async user(id: string) {
    const u = await this.prisma.user.findUnique({
      where: { id },
      select: {
        id: true, phoneE164: true, phoneCountry: true, status: true, accountType: true, locale: true, createdAt: true, lastActiveAt: true, frozenAt: true,
        suspendedUntil: true, restrictionReason: true, restrictedAt: true, deletionRequestedAt: true,
        profile: { select: { displayName: true, gender: true, birthDate: true, countryCode: true, city: true, maritalStatus: true, occupation: true, bio: true } },
        verifications: { where: { revokedAt: null }, select: { type: true, verifiedAt: true } },
        // managed on someone's behalf: manager name and relation (admins see the name; the public sees the relation only)
        accountManager: { select: { managerName: true, relation: true, phoneHolder: true, ownerConsentAt: true, createdAt: true, revokedAt: true, revokedBy: true } },
      },
    });
    if (!u) throw new AppError(ErrorCode.NOT_FOUND);
    const [reportsAgainst, reportsMade, openTickets, history] = await Promise.all([
      this.prisma.report.count({ where: { reportedUserId: id } }),
      this.prisma.report.count({ where: { reporterId: id } }),
      this.prisma.supportTicket.count({ where: { userId: id, status: { not: 'CLOSED' } } }),
      this.prisma.auditLog.findMany({ where: { entityType: 'user', entityId: id }, orderBy: { createdAt: 'desc' }, take: 20, select: { action: true, actorType: true, reason: true, createdAt: true } }),
    ]);
    const { phoneE164, ...rest } = u;
    return { ...rest, phone: maskPhone(phoneE164), reportsAgainst, reportsMade, openTickets, history };
  }

  reports(q: ReportsQuery) {
    return this.prisma.report.findMany({
      where: { status: (q.status ?? { in: ['OPEN', 'IN_REVIEW'] }) as Prisma.ReportWhereInput['status'] },
      orderBy: [{ priority: 'desc' }, { createdAt: 'asc' }],
      take: 100,
      select: {
        id: true, reason: true, details: true, status: true, priority: true, targetType: true, createdAt: true, resolution: true,
        reportedUser: { select: { id: true, status: true, profile: { select: { displayName: true } } } },
        reporter: { select: { id: true, profile: { select: { displayName: true } } } },
      },
    });
  }

  async resolveReport(id: string, dto: ResolveReportDto, a: AuthAdmin) {
    const r = await this.prisma.report.findUnique({ where: { id }, select: { status: true } });
    if (!r) throw new AppError(ErrorCode.NOT_FOUND);
    if (r.status === 'ACTION_TAKEN' || r.status === 'DISMISSED') throw new AppError(ErrorCode.CONFLICT, 'Already resolved');
    await this.prisma.$transaction(async (tx) => {
      await tx.report.update({ where: { id }, data: { status: dto.status, resolution: dto.resolution, handledBy: a.id, resolvedAt: new Date() } });
      await this.audit.record({ actorType: 'ADMIN', actorId: a.id, action: 'report.resolve', entityType: 'report', entityId: id, reason: dto.resolution, after: { status: dto.status } }, tx);
    });
    return { id, status: dto.status };
  }

  /** FAQ with all three languages, for editing. */
  faqAll() {
    return this.prisma.faqEntry.findMany({ orderBy: [{ category: 'asc' }, { sortOrder: 'asc' }] });
  }

  async getWeights() {
    return this.settings.get('matching.weights', {});
  }

  async setWeights(dto: WeightsDto, admin: AuthAdmin) {
    const before = (await this.settings.get<{ version?: number }>('matching.weights', {})) ?? {};
    const next = parseWeights({ ...dto, version: (before.version ?? 0) + 1 });
    await this.settings.set('matching.weights', next as unknown as Prisma.InputJsonValue, admin.id);
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'settings.matching_weights', entityType: 'system_setting', entityId: 'matching.weights', before, after: next });
    return next;
  }

  async plans() {
    return this.prisma.subscriptionPlan.findMany({ orderBy: { sortOrder: 'asc' }, include: { entitlements: { select: { featureKey: true, value: true } } } });
  }

  /** Quota / feature edits apply to all users of the plan within ~30 s, no app update needed. */
  async setEntitlements(code: PlanCode, dto: EntitlementsDto, admin: AuthAdmin) {
    if (code !== 'FREE' && dto.values.show_ads === true) throw new AppError(ErrorCode.VALIDATION, 'Paid plans never show ads', { field: 'show_ads' });
    const pro = code.startsWith('PRO_');
    for (const k of Object.keys(dto.values)) {
      if (PRO_KEYS.has(k) && !pro && code !== 'FREE') throw new AppError(ErrorCode.VALIDATION, 'Counselor features belong to counselor plans', { field: k });
      if (pro && !PRO_KEYS.has(k) && k !== 'show_ads') throw new AppError(ErrorCode.VALIDATION, 'Member features belong to member plans', { field: k });
    }
    if (dto.values.directory_boost !== undefined && ((dto.values.directory_boost as number) > 2 || (code === 'FREE' && dto.values.directory_boost !== 0))) throw new AppError(ErrorCode.VALIDATION, 'Boost is 0–2, and 0 on the free plan', { field: 'directory_boost' });
    for (const [k, v] of Object.entries(dto.values)) {
      const t = FEATURE_KEYS[k];
      if (!t || typeof v !== t || (t === 'number' && (!Number.isInteger(v) || (v as number) < 0 || (v as number) > 10000))) {
        throw new AppError(ErrorCode.VALIDATION, `Invalid value for ${k}`);
      }
    }
    const plan = await this.prisma.subscriptionPlan.findUniqueOrThrow({ where: { code }, include: { entitlements: true } });
    const before = Object.fromEntries(plan.entitlements.map((e) => [e.featureKey, e.value]));
    await this.prisma.$transaction(
      Object.entries(dto.values).map(([featureKey, value]) =>
        this.prisma.featureEntitlement.upsert({ where: { planId_featureKey: { planId: plan.id, featureKey } }, create: { planId: plan.id, featureKey, value }, update: { value } }),
      ),
    );
    this.entitlements.invalidate();
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'plan.entitlements', entityType: 'subscription_plan', entityId: code, before, after: dto.values });
    return this.plans();
  }

  /** Discovery ads: settings, the Free-plan switch and what a Free member gets right now. */
  async ads() {
    const settings = parseAdsSettings(await this.settings.get('ads.discovery', {}));
    const row = await this.prisma.featureEntitlement.findFirst({ where: { featureKey: 'show_ads', plan: { code: 'FREE' } }, select: { value: true } });
    const freePlanShowsAds = row?.value === true;
    return { ...settings, freePlanShowsAds, effective: adsForMember('FREE', freePlanShowsAds, settings) };
  }

  async setAds(dto: AdsDto, admin: AuthAdmin) {
    const { freePlanShowsAds, ...rest } = dto;
    const next = { ...rest, units: { android: dto.units.android.trim(), ios: dto.units.ios.trim() } };
    const bad = invalidAdsFields(next);
    if (bad.length) throw new AppError(ErrorCode.VALIDATION, `Invalid: ${bad.join(', ')}`, { fields: bad });
    const before = await this.ads();
    const free = await this.prisma.subscriptionPlan.findUniqueOrThrow({ where: { code: 'FREE' }, select: { id: true } });
    await this.prisma.featureEntitlement.upsert({
      where: { planId_featureKey: { planId: free.id, featureKey: 'show_ads' } },
      create: { planId: free.id, featureKey: 'show_ads', value: freePlanShowsAds },
      update: { value: freePlanShowsAds },
    });
    await this.settings.set('ads.discovery', next as unknown as Prisma.InputJsonValue, admin.id);
    this.entitlements.invalidate();
    const after = await this.ads();
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'settings.ads', entityType: 'system_setting', entityId: 'ads.discovery', before, after });
    return after;
  }

  /** Ban (permanent) or suspend (temporary) — sessions are revoked, the app shows the closed-account screen. */
  /** End a managed-account arrangement (e.g. the owner says they did not agree). */
  async revokeManager(userId: string, reason: string, admin: AuthAdmin) {
    const r = await this.prisma.accountManager.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date(), revokedBy: 'ADMIN' } });
    if (!r.count) throw new AppError(ErrorCode.NOT_FOUND, 'no active manager');
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'account.manager_revoked', entityType: 'user', entityId: userId, reason });
  }

  async restrict(userId: string, dto: RestrictDto, admin: AuthAdmin) {
    const until = dto.until ? new Date(dto.until) : null;
    if (dto.action === 'suspend' && until && until.getTime() <= Date.now()) throw new AppError(ErrorCode.VALIDATION, 'until must be in the future');
    const before = await this.prisma.user.findUnique({ where: { id: userId }, select: { status: true, suspendedUntil: true } });
    if (!before) throw new AppError(ErrorCode.NOT_FOUND);
    const now = new Date();
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: dto.action === 'ban'
          ? { status: 'BANNED', suspendedUntil: null, restrictionReason: dto.reason, restrictedAt: now }
          : { status: 'SUSPENDED', suspendedUntil: until, restrictionReason: dto.reason, restrictedAt: now },
      });
      await tx.userSession.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: now, revokedReason: `admin_${dto.action}` } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: `user.${dto.action}`, entityType: 'user', entityId: userId, reason: dto.reason, before, after: { until: until?.toISOString() ?? null } }, tx);
    });
    return { userId, status: dto.action === 'ban' ? 'BANNED' : 'SUSPENDED', until: until?.toISOString() ?? null };
  }

  async unrestrict(userId: string, dto: UnrestrictDto, admin: AuthAdmin) {
    const before = await this.prisma.user.findUnique({ where: { id: userId }, select: { status: true } });
    if (!before) throw new AppError(ErrorCode.NOT_FOUND);
    if (before.status !== 'BANNED' && before.status !== 'SUSPENDED') throw new AppError(ErrorCode.INVALID_STATE);
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: userId }, data: { status: 'ACTIVE', suspendedUntil: null, restrictionReason: null, restrictedAt: null } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'user.unrestrict', entityType: 'user', entityId: userId, reason: dto.reason, before }, tx);
    });
    return { userId, status: 'ACTIVE' };
  }

  async setSetting(key: string, value: Prisma.InputJsonValue, admin: AuthAdmin) {
    const known = await this.prisma.systemSetting.findUnique({ where: { key } });
    if (!known) throw new AppError(ErrorCode.NOT_FOUND, 'Unknown setting');
    if (typeof value !== typeof known.value) throw new AppError(ErrorCode.VALIDATION, 'Type must match the current value');
    await this.settings.set(key, value, admin.id);
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'settings.update', entityType: 'system_setting', entityId: key, before: known.value, after: value });
  }

  listSettings() {
    return this.prisma.systemSetting.findMany({ orderBy: { key: 'asc' } });
  }
}

/** +971 50 •••• 1234 style: enough to recognise, not to reuse. */
export function maskPhone(e164: string): string {
  return e164.length <= 6 ? '••••' : `${e164.slice(0, 4)} •••• ${e164.slice(-4)}`;
}

@ApiTags('admin')
@Controller('v1/admin')
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Public() @RateLimit(10, 900) @Post('auth/login') @HttpCode(200)
  login(@Body() dto: AdminLoginDto, @Req() req: OlfaRequest) {
    return this.admin.login(dto, req.ipHash);
  }

  @ApiBearerAuth() @RequirePermissions() @AdminMfaSetup() @Get('me')
  me(@CurrentAdmin() a: AuthAdmin) {
    return this.admin.me(a);
  }

  @ApiBearerAuth() @RequirePermissions() @AdminMfaSetup() @RateLimit(10, 900) @Post('auth/totp/setup') @HttpCode(200)
  totpSetup(@CurrentAdmin() a: AuthAdmin) {
    return this.admin.totpSetup(a);
  }

  @ApiBearerAuth() @RequirePermissions() @AdminMfaSetup() @RateLimit(10, 900) @Post('auth/totp/confirm') @HttpCode(200)
  totpConfirm(@CurrentAdmin() a: AuthAdmin, @Body() dto: TotpCodeDto) {
    return this.admin.totpConfirm(a, dto);
  }

  @ApiBearerAuth() @RequirePermissions() @Get('stats')
  stats() {
    return this.admin.stats();
  }

  @ApiBearerAuth() @RequirePermissions('users.read') @Get('users')
  users(@Query() q: UsersQuery) {
    return this.admin.users(q);
  }

  @ApiBearerAuth() @RequirePermissions('users.read') @Get('users/:id')
  user(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.user(id);
  }

  @ApiBearerAuth() @RequirePermissions('reports.manage') @Get('reports')
  reports(@Query() q: ReportsQuery) {
    return this.admin.reports(q);
  }

  @ApiBearerAuth() @RequirePermissions('reports.manage') @Post('reports/:id/resolve') @HttpCode(200)
  resolveReport(@Param('id', ParseUUIDPipe) id: string, @Body() dto: ResolveReportDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.resolveReport(id, dto, a);
  }

  @ApiBearerAuth() @RequirePermissions('support.manage') @Get('support/faq')
  faq() {
    return this.admin.faqAll();
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Get('settings')
  settings() {
    return this.admin.listSettings();
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Put('settings/:key') @HttpCode(204)
  async setting(@Param('key') key: string, @Body() body: { value: Prisma.InputJsonValue }, @CurrentAdmin() a: AuthAdmin) {
    await this.admin.setSetting(key, body.value, a);
  }

  @ApiBearerAuth() @RequirePermissions('users.manage') @Post('users/:id/restrict') @HttpCode(200)
  restrict(@Param('id') id: string, @Body() dto: RestrictDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.restrict(id, dto, a);
  }

  @ApiBearerAuth() @RequirePermissions('users.manage') @Post('users/:id/unrestrict') @HttpCode(200)
  unrestrict(@Param('id') id: string, @Body() dto: UnrestrictDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.unrestrict(id, dto, a);
  }

  @ApiBearerAuth() @RequirePermissions('users.manage') @Post('users/:id/manager/revoke') @HttpCode(204)
  revokeManager(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UnrestrictDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.revokeManager(id, dto.reason, a);
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Get('matching/weights')
  weights() {
    return this.admin.getWeights();
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Put('matching/weights')
  setWeights(@Body() dto: WeightsDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.setWeights(dto, a);
  }

  @ApiBearerAuth() @RequirePermissions('plans.manage') @Get('plans')
  plans() {
    return this.admin.plans();
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Get('ads')
  ads() {
    return this.admin.ads();
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Put('ads')
  setAds(@Body() dto: AdsDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.setAds(dto, a);
  }

  @ApiBearerAuth() @RequirePermissions('plans.manage') @Put('plans/:code/entitlements')
  setEntitlements(@Param('code', new ParseEnumPipe(PlanCode)) code: PlanCode, @Body() dto: EntitlementsDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.setEntitlements(code, dto, a);
  }
}

@Module({ imports: [JwtModule.register({})], controllers: [AdminController], providers: [AdminService] })
export class AdminModule {}
