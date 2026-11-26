import { Body, Controller, Get, Global, HttpCode, Inject, Injectable, Logger, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { BanIdentityKind, IntegrityCaseStatus, Prisma } from '@prisma/client';
import { IsIn, IsOptional, IsString, Length, MaxLength } from 'class-validator';
import { createHmac } from 'node:crypto';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { AllowPending, AuthAdmin, AuthUser, CurrentAdmin, CurrentUser, ProfessionalsOnly, RequirePermissions } from '../../common/http';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { assessIntegrity, detectContactInfo, ReviewAnswers, SIGNAL_WEIGHT, SignalKind, signalsFromReview } from '../../domain/integrity';
import { NotificationsService } from '../notifications/notifications.module';

// ───────────── bans (re-registration block) ─────────────

/**
 * Identifiers of permanently banned accounts are kept only as HMACs, so the
 * list cannot be read back into phone numbers, devices or bank accounts.
 */
@Injectable()
export class BansService {
  constructor(private readonly prisma: PrismaService, @Inject(ENV) private readonly env: Env) {}

  private secret() {
    // Separate secret when configured; otherwise the OTP secret with a domain prefix.
    return this.env.IDENTITY_HMAC_SECRET ?? `ban:${this.env.OTP_HMAC_SECRET}`;
  }

  hash(kind: BanIdentityKind, value: string): string {
    const v = kind === 'LICENSE' ? value.toUpperCase().replace(/[^A-Z0-9:]/g, '') : value.trim();
    return createHmac('sha256', this.secret()).update(`${kind}:${v}`).digest('hex');
  }

  /** licence identity = issuing country + number (spacing and dashes ignored) */
  licenseValue(country: string, number: string) {
    return `${country}:${number}`;
  }

  async isBanned(kind: BanIdentityKind, value: string, prehashed = false): Promise<boolean> {
    const valueHash = prehashed ? value : this.hash(kind, value);
    return !!(await this.prisma.bannedIdentity.findFirst({ where: { kind, valueHash, liftedAt: null }, select: { id: true } }));
  }

  async assertNotBanned(kind: BanIdentityKind, value: string, prehashed = false) {
    if (await this.isBanned(kind, value, prehashed)) throw new AppError(ErrorCode.ACCOUNT_BANNED);
  }
}

// ───────────── signals, cases, decisions ─────────────

class RespondDto {
  @ApiProperty() @IsString() @Length(20, 3000) response: string;
}
export class DecideDto {
  @ApiProperty({ enum: ['CLEARED', 'WARNED', 'SUSPENDED', 'BANNED'] }) @IsIn(['CLEARED', 'WARNED', 'SUSPENDED', 'BANNED']) decision: 'CLEARED' | 'WARNED' | 'SUSPENDED' | 'BANNED';
  @ApiProperty() @IsString() @Length(10, 1000) reason: string;
}
class CasesQuery {
  @ApiPropertyOptional() @IsOptional() @IsIn(Object.values(IntegrityCaseStatus)) status?: IntegrityCaseStatus;
}
class LiftDto {
  @ApiProperty() @IsString() @MaxLength(300) reason: string;
}

@Injectable()
export class IntegrityService {
  private readonly log = new Logger('Integrity');
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
    private readonly bans: BansService,
  ) {}

  /** Records the questionnaire's signals and re-assesses the counselor. */
  async fromReview(counselorId: string, clientId: string, consultationId: string, a: ReviewAnswers, tx?: Prisma.TransactionClient) {
    const kinds = signalsFromReview(a);
    if (!kinds.length) return;
    const db = tx ?? this.prisma;
    await db.counselorIntegritySignal.createMany({
      data: kinds.map((kind) => ({ counselorId, clientId, consultationId, kind, weight: SIGNAL_WEIGHT[kind], details: { source: 'review', v: 1 } })),
    });
  }

  /**
   * Called for every message a counselor sends in a consultation chat. The
   * message is delivered (the client also sees a safety note); the platform
   * keeps a signal, never the message text.
   */
  async fromCounselorMessage(counselorId: string, consultationId: string, text: string) {
    const kinds = detectContactInfo(text);
    if (!kinds.length) return false;
    await this.prisma.counselorIntegritySignal.create({
      data: { counselorId, consultationId, kind: 'CHAT_CONTACT_SHARED', weight: SIGNAL_WEIGHT.CHAT_CONTACT_SHARED, details: { source: 'chat', contact: kinds } },
    });
    await this.assess(counselorId);
    return true;
  }

  /** Opens a case for human review when the evidence is corroborated (never automatic sanctions). */
  async assess(counselorId: string, now = new Date()) {
    const rows = await this.prisma.counselorIntegritySignal.findMany({
      where: { counselorId, createdAt: { gte: new Date(now.getTime() - 90 * 86_400_000) } },
      select: { kind: true, clientId: true, consultationId: true, createdAt: true },
    });
    const a = assessIntegrity(rows.map((r) => ({ ...r, kind: r.kind as SignalKind })), now);
    if (a.level !== 'review') return a;
    const open = await this.prisma.counselorIntegrityCase.findFirst({ where: { counselorId, status: { in: ['OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW'] } }, select: { id: true } });
    if (open) {
      await this.prisma.counselorIntegrityCase.update({ where: { id: open.id }, data: { score: a.score, reasons: a.reasons } });
      return a;
    }
    const days = await this.settings.get('integrity.responseDays', 7);
    const c = await this.prisma.counselorIntegrityCase
      .create({ data: { counselorId, score: a.score, reasons: a.reasons, status: 'AWAITING_RESPONSE', notifiedAt: now, responseDueAt: new Date(now.getTime() + days * 86_400_000) } })
      .catch(() => null); // a concurrent assessment opened it first (partial unique index)
    if (c) {
      await this.audit.record({ actorType: 'SYSTEM', action: 'integrity.case_open', entityType: 'counselor', entityId: counselorId, after: { caseId: c.id, score: a.score, reasons: a.reasons } });
      await this.notifications.notify(counselorId, 'INTEGRITY_CASE', 'push.integrity_case', { caseId: c.id });
    }
    return a;
  }

  // ── counselor side ──

  async myCase(counselorId: string) {
    return this.prisma.counselorIntegrityCase.findFirst({
      where: { counselorId },
      orderBy: { openedAt: 'desc' },
      // what the counselor may see: never which client reported what
      select: { id: true, status: true, openedAt: true, responseDueAt: true, counselorResponse: true, respondedAt: true, decidedAt: true, decisionReason: true },
    });
  }

  async respond(counselorId: string, caseId: string, dto: RespondDto) {
    const c = await this.prisma.counselorIntegrityCase.findUnique({ where: { id: caseId }, select: { counselorId: true, status: true } });
    if (!c || c.counselorId !== counselorId) throw new AppError(ErrorCode.NOT_FOUND);
    if (c.status !== 'AWAITING_RESPONSE' && c.status !== 'OPEN') throw new AppError(ErrorCode.INVALID_STATE);
    await this.prisma.counselorIntegrityCase.update({ where: { id: caseId }, data: { counselorResponse: dto.response.trim(), respondedAt: new Date(), status: 'UNDER_REVIEW' } });
    await this.audit.record({ actorType: 'USER', actorId: counselorId, action: 'integrity.respond', entityType: 'integrity_case', entityId: caseId });
    return this.myCase(counselorId);
  }

  // ── admin side ──

  cases(status?: IntegrityCaseStatus) {
    return this.prisma.counselorIntegrityCase.findMany({
      where: status ? { status } : { status: { in: ['OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW'] } },
      orderBy: [{ score: 'desc' }, { openedAt: 'asc' }],
      take: 100,
      include: { counselor: { select: { displayName: true, kind: true, ratingAvg: true, ratingCount: true, status: true } } },
    });
  }

  async caseDetail(id: string) {
    const c = await this.prisma.counselorIntegrityCase.findUnique({ where: { id }, include: { counselor: { select: { displayName: true, kind: true, licenseNumber: true, licenseCountry: true, status: true } } } });
    if (!c) throw new AppError(ErrorCode.NOT_FOUND);
    const signals = await this.prisma.counselorIntegritySignal.findMany({ where: { counselorId: c.counselorId }, orderBy: { createdAt: 'desc' }, take: 200 });
    const reviews = await this.prisma.consultationReview.findMany({
      where: { counselorId: c.counselorId, questionnaireVersion: { not: null } },
      orderBy: { createdAt: 'desc' },
      take: 100,
      select: { consultationId: true, rating: true, quality: true, commitment: true, effectiveness: true, outcome: true, nextSession: true, nextChannel: true, contactShared: true, offPlatformPayment: true, externalChannel: true, comment: true, createdAt: true },
    });
    return { ...c, signals, reviews };
  }

  /**
   * Decision after review. BANNED: account banned, counselor suspended, offers
   * off, paid-but-unconfirmed bookings refunded by the consultations service,
   * identifiers added to the re-registration block. Pending earnings are NOT
   * forfeited automatically — finance settles them per the published policy.
   */
  async decide(admin: AuthAdmin, id: string, dto: DecideDto) {
    const c = await this.prisma.counselorIntegrityCase.findUnique({ where: { id }, select: { counselorId: true, status: true } });
    if (!c) throw new AppError(ErrorCode.NOT_FOUND);
    if (!['OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW'].includes(c.status)) throw new AppError(ErrorCode.INVALID_STATE, 'Case already decided');
    const uid = c.counselorId;
    await this.prisma.$transaction(async (tx) => {
      await tx.counselorIntegrityCase.update({ where: { id }, data: { status: dto.decision, decidedBy: admin.id, decidedAt: new Date(), decisionReason: dto.reason } });
      if (dto.decision === 'SUSPENDED' || dto.decision === 'BANNED') {
        await tx.counselorProfile.update({ where: { userId: uid }, data: { status: 'SUSPENDED' } });
        await tx.counselorOffering.updateMany({ where: { counselorId: uid }, data: { active: false } });
      }
      if (dto.decision === 'BANNED') {
        await tx.user.update({ where: { id: uid }, data: { status: 'BANNED' } });
        await tx.userSession.updateMany({ where: { userId: uid, revokedAt: null }, data: { revokedAt: new Date(), revokedReason: 'banned' } });
        await this.banIdentities(tx, uid, id, admin.id, dto.reason);
        await tx.moderationAction.create({ data: { adminId: admin.id, targetUserId: uid, action: 'BAN', targetType: 'counselor', targetId: uid, reason: dto.reason } });
      } else if (dto.decision === 'WARNED') {
        await tx.moderationAction.create({ data: { adminId: admin.id, targetUserId: uid, action: 'WARN', targetType: 'counselor', targetId: uid, reason: dto.reason } });
      }
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: `integrity.${dto.decision.toLowerCase()}`, entityType: 'integrity_case', entityId: id, before: { status: c.status }, reason: dto.reason }, tx);
      await this.notifications.notify(uid, 'INTEGRITY_CASE', 'push.integrity_decision', { caseId: id }, tx);
    });
    await this.notifications.push(uid, 'push.integrity_decision', { caseId: id });
    return this.caseDetail(id);
  }

  /** Phone, every device that signed in, licence and payout accounts → re-registration block. */
  private async banIdentities(tx: Prisma.TransactionClient, userId: string, caseId: string | null, adminId: string, reason: string) {
    const u = await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { phoneE164: true } });
    const devices = await tx.userSession.findMany({ where: { userId }, select: { deviceId: true }, distinct: ['deviceId'] });
    const cp = await tx.counselorProfile.findUnique({ where: { userId }, select: { licenseCountry: true, licenseNumber: true } });
    const payouts = await tx.payoutMethod.findMany({ where: { counselorId: userId }, select: { fingerprint: true } });
    const rows: { kind: BanIdentityKind; valueHash: string }[] = [
      { kind: 'PHONE', valueHash: this.bans.hash('PHONE', u.phoneE164) },
      ...devices.filter((d) => d.deviceId).map((d) => ({ kind: 'DEVICE' as const, valueHash: this.bans.hash('DEVICE', d.deviceId) })),
      ...(cp ? [{ kind: 'LICENSE' as const, valueHash: this.bans.hash('LICENSE', this.bans.licenseValue(cp.licenseCountry, cp.licenseNumber)) }] : []),
      ...payouts.map((p) => ({ kind: 'PAYOUT' as const, valueHash: p.fingerprint })),
    ];
    for (const r of rows) {
      const live = await tx.bannedIdentity.findFirst({ where: { kind: r.kind, valueHash: r.valueHash, liftedAt: null }, select: { id: true } });
      if (!live) await tx.bannedIdentity.create({ data: { ...r, userId, caseId, reason, createdBy: adminId } });
    }
  }

  /** Lifting a ban (appeal accepted) — reversible and audited. */
  async liftBan(admin: AuthAdmin, userId: string, dto: LiftDto) {
    await this.prisma.$transaction(async (tx) => {
      await tx.bannedIdentity.updateMany({ where: { userId, liftedAt: null }, data: { liftedAt: new Date(), liftedBy: admin.id } });
      await tx.user.update({ where: { id: userId }, data: { status: 'ACTIVE' } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'integrity.lift_ban', entityType: 'user', entityId: userId, reason: dto.reason }, tx);
    });
    return { userId, lifted: true };
  }

  /** Daily: cases whose response window passed move to review (the counselor did not answer). */
  async expireResponses(now = new Date()) {
    const r = await this.prisma.counselorIntegrityCase.updateMany({ where: { status: 'AWAITING_RESPONSE', responseDueAt: { lt: now } }, data: { status: 'UNDER_REVIEW' } });
    return r.count;
  }
}

@ApiTags('integrity')
@ApiBearerAuth()
@Controller('v1')
export class IntegrityController {
  constructor(private readonly integrity: IntegrityService) {}

  @AllowPending() @ProfessionalsOnly() @Get('counselors/me/integrity')
  mine(@CurrentUser() u: AuthUser) {
    return this.integrity.myCase(u.id);
  }

  @AllowPending() @ProfessionalsOnly() @Post('counselors/me/integrity/:id/respond') @HttpCode(200)
  respond(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RespondDto) {
    return this.integrity.respond(u.id, id, dto);
  }
}

@ApiTags('admin')
@ApiBearerAuth()
@Controller('v1/admin')
export class IntegrityAdminController {
  constructor(private readonly integrity: IntegrityService) {}

  @RequirePermissions('integrity.manage') @Get('integrity/cases')
  cases(@Query() q: CasesQuery) {
    return this.integrity.cases(q.status);
  }

  @RequirePermissions('integrity.manage') @Get('integrity/cases/:id')
  detail(@Param('id', ParseUUIDPipe) id: string) {
    return this.integrity.caseDetail(id);
  }

  // POST integrity/cases/:id/decide lives in ConsultationsAdminController (it also refunds open bookings).

  @RequirePermissions('integrity.manage') @Post('users/:id/lift-ban') @HttpCode(200)
  lift(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: LiftDto) {
    return this.integrity.liftBan(a, id, dto);
  }
}

@Global()
@Module({
  controllers: [IntegrityController, IntegrityAdminController],
  providers: [BansService, IntegrityService],
  exports: [BansService, IntegrityService],
})
export class IntegrityModule {}
