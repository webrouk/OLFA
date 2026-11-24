import { Body, Controller, Get, Headers, HttpCode, Inject, Injectable, Logger, Module, Param, ParseUUIDPipe, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { ConsultationStatus, Prisma } from '@prisma/client';
import { IsIn, IsString, Length } from 'class-validator';
import { randomUUID } from 'node:crypto';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode, fromPgError } from '../../common/errors';
import { AllowPending, AuthAdmin, AuthUser, CurrentAdmin, CurrentUser, MembersOnly, OlfaRequest, ProfessionalsOnly, Public, RateLimit, Req, RequirePermissions } from '../../common/http';
import { QUESTIONNAIRE_VERSION } from '../../domain/integrity';
import { BansService, IntegrityService } from '../integrity/integrity.module';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { splitFee } from '../../domain/payments';
import { MediaModule } from '../media/media.module';
import { StorageService } from '../media/storage.service';
import { NotificationsService } from '../notifications/notifications.module';
import {
  AdminQueueQuery,
  AdminRejectDto,
  BookDto,
  ConfirmDto,
  CounselorApplyDto,
  CounselorListQuery,
  CredentialUploadDto,
  OfferingDto,
  ReasonDto,
  ReviewDto,
} from './consultations.dto';
import { PAYMENT_GATEWAY, PaymentGateway, StripeGateway, TestGateway } from './payment.gateway';

const OPEN: ConsultationStatus[] = ['AWAITING_PAYMENT', 'PAID', 'CONFIRMED'];
const PAGE = 20;

const publicCounselor = {
  userId: true,
  kind: true,
  displayName: true,
  headline: true,
  bio: true,
  yearsExperience: true,
  licenseAuthority: true,
  licenseCountry: true,
  languages: true,
  services: true,
  ratingAvg: true,
  ratingCount: true,
  offerings: { where: { active: true }, orderBy: [{ service: 'asc' }, { durationMinutes: 'asc' }] },
} satisfies Prisma.CounselorProfileSelect;

@Injectable()
export class ConsultationsService {
  private readonly log = new Logger('Consultations');
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
    private readonly storage: StorageService,
    @Inject(PAYMENT_GATEWAY) private readonly gateway: PaymentGateway,
    @Inject(ENV) private readonly env: Env,
    private readonly integrity: IntegrityService,
    private readonly bans: BansService,
  ) {}

  private wrap = <T>(p: Promise<T>) =>
    p.catch((e: unknown) => {
      throw fromPgError(e) ?? e;
    });

  // ── counselor side ───────────────────────────────────────────────

  /** Private upload of a licence / certificate; only moderators can view it. */
  async credentialUploadUrl(userId: string, dto: CredentialUploadDto) {
    const key = `credentials/${userId}/${randomUUID()}`;
    return { key, upload: await this.storage.presignUpload(key, dto.mime, 8 * 1024 * 1024) };
  }

  /** Apply (or re-apply after rejection). An approved profile edits go back to review. */
  async apply(userId: string, dto: CounselorApplyDto) {
    if (dto.credentialKeys.some((k) => !k.startsWith(`credentials/${userId}/`))) throw new AppError(ErrorCode.FORBIDDEN, 'Foreign credential key');
    for (const k of dto.credentialKeys) await this.storage.head(k).catch(() => { throw new AppError(ErrorCode.VALIDATION, `Credential not uploaded: ${k}`); });
    const existing = await this.prisma.counselorProfile.findUnique({ where: { userId }, select: { status: true } });
    if (existing?.status === 'SUSPENDED') throw new AppError(ErrorCode.FORBIDDEN, 'Counselor account suspended');
    // A licence that belonged to a permanently banned account cannot register again.
    await this.bans.assertNotBanned('LICENSE', this.bans.licenseValue(dto.licenseCountry, dto.licenseNumber));
    const policyVersion = await this.settings.get('counselor.policyVersion', '2026-11');
    if (dto.policyVersion !== policyVersion) throw new AppError(ErrorCode.VALIDATION, 'Please accept the current professional policy', { field: 'policyVersion', current: policyVersion });
    const data = {
      kind: dto.kind,
      displayName: dto.displayName.trim(),
      headline: dto.headline.trim(),
      bio: dto.bio.trim(),
      yearsExperience: dto.yearsExperience,
      licenseNumber: dto.licenseNumber.trim(),
      licenseAuthority: dto.licenseAuthority.trim(),
      licenseCountry: dto.licenseCountry,
      credentialKeys: dto.credentialKeys,
      languages: dto.languages,
      services: dto.services,
      gender: dto.gender ?? null,
      countryCode: dto.countryCode ?? dto.licenseCountry,
      city: dto.city?.trim() ?? null,
      policyVersion,
      policyAcceptedAt: new Date(),
      status: 'PENDING' as const,
      rejectReason: null,
    };
    await this.prisma.counselorProfile.upsert({ where: { userId }, create: { userId, ...data }, update: data }).catch((e: unknown) => {
      throw fromPgError(e) ?? e;
    });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: existing ? 'counselor.reapply' : 'counselor.apply', entityType: 'counselor', entityId: userId });
    return this.mine(userId);
  }

  async mine(userId: string) {
    const p = await this.prisma.counselorProfile.findUnique({
      where: { userId },
      select: { ...publicCounselor, status: true, rejectReason: true, licenseNumber: true, licenseCountry: true, gender: true, countryCode: true, city: true, policyVersion: true, policyAcceptedAt: true, offerings: { orderBy: [{ service: 'asc' }, { durationMinutes: 'asc' }] } },
    });
    return p ?? null;
  }

  private async approvedCounselor(userId: string) {
    const p = await this.prisma.counselorProfile.findUnique({ where: { userId }, select: { status: true, languages: true, services: true } });
    if (!p) throw new AppError(ErrorCode.NOT_FOUND, 'Not a counselor');
    if (p.status !== 'APPROVED') throw new AppError(ErrorCode.FORBIDDEN, 'Counselor profile is not approved');
    return p;
  }

  /** Each offering = service × language × duration with its own price. */
  async upsertOffering(userId: string, dto: OfferingDto) {
    const p = await this.approvedCounselor(userId);
    if (!p.services.includes(dto.service) || !p.languages.includes(dto.language)) throw new AppError(ErrorCode.VALIDATION, 'Service and language must be in your approved profile');
    const allowed = await this.settings.get<number[]>('consultations.durations', [30, 45, 60, 90]);
    if (!allowed.includes(dto.durationMinutes)) throw new AppError(ErrorCode.VALIDATION, 'Duration not allowed');
    const key = { counselorId: userId, service: dto.service, language: dto.language, durationMinutes: dto.durationMinutes };
    return this.prisma.counselorOffering.upsert({
      where: { counselorId_service_language_durationMinutes: key },
      create: { ...key, priceMinor: dto.priceMinor, currency: dto.currency, active: dto.active ?? true },
      update: { priceMinor: dto.priceMinor, currency: dto.currency, active: dto.active ?? true },
    });
  }

  async counselorBookings(userId: string, status?: string) {
    await this.approvedCounselor(userId);
    return this.prisma.consultation.findMany({
      where: { counselorId: userId, status: status ? (status as ConsultationStatus) : { not: 'AWAITING_PAYMENT' } },
      orderBy: { createdAt: 'desc' },
      take: 100,
      select: {
        id: true, service: true, language: true, durationMinutes: true, priceMinor: true, currency: true, status: true,
        clientNote: true, preferredTime: true, scheduledAt: true, createdAt: true, paidAt: true,
        platformFeePercent: true, platformFeeMinor: true, counselorNetMinor: true, completedAt: true,
        conversation: { select: { id: true } },
        client: { select: { id: true, profile: { select: { displayName: true } } } },
      },
    });
  }

  /** Counselor accepts a paid booking: schedules it and opens the chat (counselor may write first). */
  async confirm(userId: string, id: string, dto: ConfirmDto) {
    const scheduledAt = new Date(dto.scheduledAt);
    if (scheduledAt.getTime() < Date.now() - 5 * 60_000) throw new AppError(ErrorCode.VALIDATION, 'scheduledAt is in the past');
    const k = await this.prisma.consultation.findUnique({ where: { id }, select: { counselorId: true, clientId: true, status: true } });
    if (!k || k.counselorId !== userId) throw new AppError(ErrorCode.NOT_FOUND);
    if (k.status !== 'PAID') throw new AppError(ErrorCode.INVALID_STATE, 'Only paid bookings can be confirmed');
    const conversationId = await this.wrap(
      this.prisma.$transaction(async (tx) => {
        await tx.consultation.update({ where: { id }, data: { status: 'CONFIRMED', scheduledAt, confirmedAt: new Date() } });
        const conv = await tx.conversation.create({
          data: { kind: 'CONSULTATION', consultationId: id, startedBy: userId, members: { create: [{ userId }, { userId: k.clientId }] } },
          select: { id: true },
        });
        await this.notifications.notify(k.clientId, 'CONSULTATION_CONFIRMED', 'push.consultation_confirmed', { consultationId: id, conversationId: conv.id }, tx);
        return conv.id;
      }),
    );
    await this.notifications.push(k.clientId, 'push.consultation_confirmed', { consultationId: id, conversationId });
    return { id, status: 'CONFIRMED', conversationId };
  }

  /** Counselor declines a paid booking → full refund. */
  async decline(userId: string, id: string, dto: ReasonDto) {
    const k = await this.prisma.consultation.findUnique({ where: { id }, include: { payment: true } });
    if (!k || k.counselorId !== userId) throw new AppError(ErrorCode.NOT_FOUND);
    if (k.status !== 'PAID') throw new AppError(ErrorCode.INVALID_STATE);
    await this.refundAndClose(k.id, k.payment, 'DECLINED', { declineReason: dto.reason ?? null });
    await this.notifications.notify(k.clientId, 'CONSULTATION_DECLINED', 'push.consultation_declined', { consultationId: id });
    return { id, status: 'REFUNDED' };
  }

  async complete(userId: string, id: string) {
    const k = await this.prisma.consultation.findUnique({ where: { id }, select: { counselorId: true, clientId: true, status: true } });
    if (!k || k.counselorId !== userId) throw new AppError(ErrorCode.NOT_FOUND);
    if (k.status !== 'CONFIRMED') throw new AppError(ErrorCode.INVALID_STATE);
    await this.wrap(this.prisma.consultation.update({ where: { id }, data: { status: 'COMPLETED', completedAt: new Date() } }));
    // The client must answer the questionnaire before booking again (DB gate).
    await this.notifications.notify(k.clientId, 'REVIEW_REQUIRED', 'push.review_required', { consultationId: id });
    return { id, status: 'COMPLETED' };
  }

  // ── client side ──────────────────────────────────────────────────

  async list(q: CounselorListQuery) {
    const where: Prisma.CounselorProfileWhereInput = {
      status: 'APPROVED',
      user: { status: 'ACTIVE', deletedAt: null },
      kind: q.kind,
      offerings: { some: { active: true, service: q.service, language: q.language, durationMinutes: q.durationMinutes } },
    };
    const items = await this.prisma.counselorProfile.findMany({
      where,
      select: publicCounselor,
      orderBy: [{ ratingAvg: 'desc' }, { ratingCount: 'desc' }, { userId: 'asc' }],
      take: PAGE + 1,
      ...(q.cursor ? { cursor: { userId: q.cursor }, skip: 1 } : {}),
    });
    const more = items.length > PAGE;
    return { items: items.slice(0, PAGE), nextCursor: more ? items[PAGE - 1].userId : null };
  }

  async details(id: string) {
    const p = await this.prisma.counselorProfile.findFirst({ where: { userId: id, status: 'APPROVED' }, select: publicCounselor });
    if (!p) throw new AppError(ErrorCode.NOT_FOUND);
    const reviews = await this.prisma.consultationReview.findMany({
      where: { counselorId: id, hidden: false },
      orderBy: { createdAt: 'desc' },
      take: 20,
      select: { rating: true, comment: true, createdAt: true, client: { select: { profile: { select: { displayName: true } } } } },
    });
    // reviewers are shown by first name only
    return { ...p, reviews: reviews.map((r) => ({ rating: r.rating, comment: r.comment, createdAt: r.createdAt, by: r.client.profile?.displayName.split(' ')[0] ?? null })) };
  }

  /**
   * Creates the booking with a price snapshot and a payment intent.
   * The booking is NOT sent to the counselor until the payment succeeds.
   */
  async book(userId: string, dto: BookDto) {
    const o = await this.prisma.counselorOffering.findUnique({ where: { id: dto.offeringId }, include: { counselor: { select: { status: true, userId: true } } } });
    if (!o || !o.active || o.counselor.status !== 'APPROVED') throw new AppError(ErrorCode.NOT_FOUND, 'Offering not available');
    if (o.counselorId === userId) throw new AppError(ErrorCode.VALIDATION, 'You cannot book yourself');
    const windowMin = await this.settings.get('consultations.paymentWindowMinutes', 30);
    const k = await this.wrap(
      this.prisma.consultation.create({
        data: {
          clientId: userId,
          counselorId: o.counselorId,
          offeringId: o.id,
          service: o.service,
          language: o.language,
          durationMinutes: o.durationMinutes,
          priceMinor: o.priceMinor,
          currency: o.currency,
          clientNote: dto.note?.trim() || null,
          preferredTime: dto.preferredTime ? new Date(dto.preferredTime) : null,
          expiresAt: new Date(Date.now() + windowMin * 60_000),
        },
      }),
    ).catch((e: unknown) => {
      if (e instanceof AppError && e.code === ErrorCode.CONFLICT) throw new AppError(ErrorCode.CONFLICT, 'You already have an open booking with this counselor');
      throw e;
    });
    const intent = await this.gateway.createIntent({ amountMinor: k.priceMinor, currency: k.currency, consultationId: k.id, userId });
    await this.prisma.payment.create({
      data: { userId, consultationId: k.id, provider: 'WEB', providerPaymentId: intent.providerPaymentId, amountMinor: k.priceMinor, currency: k.currency, status: 'PENDING' },
    });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'consultation.book', entityType: 'consultation', entityId: k.id });
    return {
      id: k.id,
      status: k.status,
      expiresAt: k.expiresAt,
      amountMinor: k.priceMinor,
      currency: k.currency,
      payment: { provider: this.gateway.name, clientSecret: intent.clientSecret },
    };
  }

  /** Development only: simulates the provider webhook for the test gateway. */
  async testPay(userId: string, id: string) {
    if (this.gateway.name !== 'test' || this.env.NODE_ENV === 'production') throw new AppError(ErrorCode.NOT_FOUND);
    const pay = await this.prisma.payment.findFirst({ where: { consultationId: id, userId, status: 'PENDING' } });
    if (!pay) throw new AppError(ErrorCode.NOT_FOUND);
    await this.onPaymentSucceeded(pay.providerPaymentId, pay.amountMinor ?? 0, pay.currency ?? '');
    return this.mineOne(userId, id);
  }

  async myBookings(userId: string) {
    return this.prisma.consultation.findMany({
      where: { clientId: userId },
      orderBy: { createdAt: 'desc' },
      take: 100,
      select: {
        id: true, service: true, language: true, durationMinutes: true, priceMinor: true, currency: true, status: true,
        scheduledAt: true, expiresAt: true, createdAt: true, completedAt: true, declineReason: true,
        conversation: { select: { id: true } },
        review: { select: { rating: true } },
        counselor: { select: { userId: true, displayName: true, kind: true } },
      },
    });
  }

  async mineOne(userId: string, id: string) {
    const k = await this.prisma.consultation.findFirst({ where: { id, OR: [{ clientId: userId }, { counselorId: userId }] }, include: { conversation: { select: { id: true } }, review: true, counselor: { select: { displayName: true, kind: true } } } });
    if (!k) throw new AppError(ErrorCode.NOT_FOUND);
    return k;
  }

  /** Client cancels: unpaid → just cancelled; paid but not yet confirmed → refunded. */
  async cancel(userId: string, id: string) {
    const k = await this.prisma.consultation.findUnique({ where: { id }, include: { payment: true } });
    if (!k || k.clientId !== userId) throw new AppError(ErrorCode.NOT_FOUND);
    if (k.status === 'AWAITING_PAYMENT') {
      await this.wrap(this.prisma.consultation.update({ where: { id }, data: { status: 'CANCELLED', cancelledAt: new Date() } }));
      return { id, status: 'CANCELLED' };
    }
    if (k.status !== 'PAID') throw new AppError(ErrorCode.INVALID_STATE, 'Confirmed consultations are cancelled through Support');
    await this.refundAndClose(id, k.payment, 'CANCELLED', {});
    return { id, status: 'REFUNDED' };
  }

  /**
   * Mandatory questionnaire: only the client, only after completion, once
   * (DB trigger + unique). Anti-circumvention answers become integrity signals;
   * the counselor sees the star rating and comment, never the other answers.
   */
  async review(userId: string, id: string, dto: ReviewDto) {
    const k = await this.prisma.consultation.findUnique({ where: { id }, select: { clientId: true, counselorId: true, status: true } });
    if (!k || k.clientId !== userId) throw new AppError(ErrorCode.NOT_FOUND);
    if (k.status !== 'COMPLETED') throw new AppError(ErrorCode.INVALID_STATE, 'You can rate after the consultation is completed');
    await this.wrap(
      this.prisma.$transaction(async (tx) => {
        await tx.consultationReview.create({
          data: {
            consultationId: id, clientId: userId, counselorId: k.counselorId, rating: dto.rating, comment: dto.comment?.trim() || null,
            questionnaireVersion: QUESTIONNAIRE_VERSION, quality: dto.quality, commitment: dto.commitment, effectiveness: dto.effectiveness, outcome: dto.outcome,
            nextSession: dto.nextSession, nextChannel: dto.nextChannel, contactShared: dto.contactShared, offPlatformPayment: dto.offPlatformPayment, externalChannel: dto.externalChannel,
          },
        });
        await this.integrity.fromReview(k.counselorId, userId, id, dto, tx);
      }),
    ).catch((e: unknown) => {
      if (e instanceof AppError && e.code === ErrorCode.CONFLICT) throw new AppError(ErrorCode.CONFLICT, 'Already reviewed');
      throw e;
    });
    await this.integrity.assess(k.counselorId).catch((e: unknown) => this.log.warn(`integrity assessment failed: ${String(e)}`));
    return { ok: true };
  }

  /** Completed consultations still waiting for the client's questionnaire (the app shows them first). */
  pendingReviews(userId: string) {
    return this.prisma.consultation.findMany({
      where: { clientId: userId, status: 'COMPLETED', review: null },
      orderBy: { completedAt: 'asc' },
      select: { id: true, service: true, durationMinutes: true, completedAt: true, counselor: { select: { userId: true, displayName: true, kind: true } } },
    });
  }

  /**
   * After a suspension or ban: paid requests the counselor never confirmed are
   * refunded in full and offers switched off. Confirmed sessions are left to
   * Support so the client can choose a refund or another counselor.
   */
  async closeForSuspended(counselorId: string) {
    const open = await this.prisma.consultation.findMany({ where: { counselorId, status: 'PAID' }, include: { payment: true } });
    for (const k of open) {
      await this.refundAndClose(k.id, k.payment, 'CANCELLED', {});
      await this.notifications.notify(k.clientId, 'CONSULTATION_DECLINED', 'push.consultation_declined', { consultationId: k.id });
    }
    return open.length;
  }

  // ── payments ─────────────────────────────────────────────────────

  async webhook(rawBody: Buffer | undefined, signature: string | undefined) {
    if (!rawBody) throw new AppError(ErrorCode.VALIDATION, 'Missing body');
    const evt = this.gateway.parseWebhook(rawBody.toString('utf8'), signature);
    if (evt.type === 'succeeded') await this.onPaymentSucceeded(evt.providerPaymentId, evt.amountMinor, evt.currency);
    if (evt.type === 'failed') await this.prisma.payment.updateMany({ where: { provider: 'WEB', providerPaymentId: evt.providerPaymentId, status: 'PENDING' }, data: { status: 'FAILED' } });
    return { received: true };
  }

  /** Idempotent: a replayed webhook is a no-op. The DB trigger re-checks amount and currency. */
  private async onPaymentSucceeded(providerPaymentId: string, amountMinor: number, currency: string) {
    const pay = await this.prisma.payment.findUnique({ where: { provider_providerPaymentId: { provider: 'WEB', providerPaymentId } } });
    if (!pay?.consultationId) return;
    if (pay.amountMinor !== amountMinor || pay.currency !== currency) {
      this.log.error(`Payment ${pay.id} amount mismatch: got ${amountMinor} ${currency}`);
      return;
    }
    const k = await this.prisma.consultation.findUnique({ where: { id: pay.consultationId }, select: { id: true, status: true, counselorId: true, clientId: true, priceMinor: true } });
    if (!k) return;
    const feePct = await this.settings.get('consultations.platformFeePercent', 15);
    const { platformMinor: fee, counselorMinor: net } = splitFee(amountMinor, feePct);
    await this.prisma.$transaction(async (tx) => {
      const upd = await tx.payment.updateMany({ where: { id: pay.id, status: 'PENDING' }, data: { status: 'SUCCEEDED' } });
      if (upd.count === 0) return; // already processed
      await tx.transaction.create({ data: { paymentId: pay.id, type: 'CHARGE', amountMinor, currency } });
      await this.audit.record({ actorType: 'SYSTEM', action: 'consultation.paid', entityType: 'consultation', entityId: k.id, after: { amountMinor, currency, platformFeeMinor: fee, counselorNetMinor: net } }, tx);
      if (k.status === 'AWAITING_PAYMENT') {
        await tx.consultation.update({ where: { id: k.id }, data: { status: 'PAID', paymentId: pay.id, paidAt: new Date() } });
        await this.notifications.notify(k.counselorId, 'CONSULTATION_REQUEST', 'push.consultation_request', { consultationId: k.id }, tx);
      }
    });
    const after = await this.prisma.consultation.findUnique({ where: { id: k.id }, select: { status: true, paymentId: true } });
    if (after?.status === 'PAID' && after.paymentId === pay.id) {
      await this.notifications.push(k.counselorId, 'push.consultation_request', { consultationId: k.id });
    } else if (after && after.paymentId !== pay.id) {
      // paid after expiry/cancellation → give the money back
      await this.gateway.refund(providerPaymentId);
      await this.prisma.payment.update({ where: { id: pay.id }, data: { status: 'REFUNDED', refundedAt: new Date() } });
    }
  }

  private async refundAndClose(id: string, payment: { id: string; providerPaymentId: string; amountMinor: number | null; currency: string | null } | null, status: 'DECLINED' | 'CANCELLED', extra: Prisma.ConsultationUpdateInput) {
    if (payment) await this.gateway.refund(payment.providerPaymentId);
    await this.wrap(
      this.prisma.$transaction(async (tx) => {
        await tx.consultation.update({ where: { id }, data: { status, cancelledAt: new Date(), ...extra } });
        if (payment) {
          await tx.payment.update({ where: { id: payment.id }, data: { status: 'REFUNDED', refundedAt: new Date() } });
          await tx.transaction.create({ data: { paymentId: payment.id, type: 'REFUND', amountMinor: -(payment.amountMinor ?? 0), currency: payment.currency ?? 'USD' } });
          await tx.consultation.update({ where: { id }, data: { status: 'REFUNDED' } });
        }
      }),
    );
  }

  // ── admin ────────────────────────────────────────────────────────

  adminQueue(q: AdminQueueQuery) {
    return this.prisma.counselorProfile.findMany({
      where: { status: (q.status as never) ?? 'PENDING' },
      orderBy: { createdAt: 'asc' },
      take: 100,
      select: { ...publicCounselor, status: true, licenseNumber: true, credentialKeys: true, createdAt: true, rejectReason: true },
    });
  }

  async adminCredential(userId: string, index: number) {
    const p = await this.prisma.counselorProfile.findUnique({ where: { userId }, select: { credentialKeys: true } });
    const key = p?.credentialKeys[index];
    if (!key) throw new AppError(ErrorCode.NOT_FOUND);
    return { url: await this.storage.signedPrivateUrl(key, 300) };
  }

  async adminDecide(admin: AuthAdmin, userId: string, approve: boolean, reason?: string) {
    const p = await this.prisma.counselorProfile.findUnique({ where: { userId }, select: { status: true } });
    if (!p) throw new AppError(ErrorCode.NOT_FOUND);
    await this.prisma.$transaction(async (tx) => {
      await tx.counselorProfile.update({ where: { userId }, data: { status: approve ? 'APPROVED' : 'REJECTED', rejectReason: approve ? null : reason, reviewedBy: admin.id, reviewedAt: new Date() } });
      await tx.moderationAction.create({ data: { adminId: admin.id, targetUserId: userId, action: approve ? 'APPROVE_COUNSELOR' : 'REJECT_COUNSELOR', targetType: 'counselor', targetId: userId, reason: reason ?? null } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: approve ? 'counselor.approve' : 'counselor.reject', entityType: 'counselor', entityId: userId, before: { status: p.status }, reason }, tx);
      await this.notifications.notify(userId, approve ? 'COUNSELOR_APPROVED' : 'COUNSELOR_REJECTED', approve ? 'push.counselor_approved' : 'push.counselor_rejected', {}, tx);
    });
    await this.notifications.push(userId, approve ? 'push.counselor_approved' : 'push.counselor_rejected', {});
    return { userId, status: approve ? 'APPROVED' : 'REJECTED' };
  }

  async adminConsultations(status?: string) {
    return this.prisma.consultation.findMany({
      where: status ? { status: status as ConsultationStatus } : {},
      orderBy: { createdAt: 'desc' },
      take: 200,
      select: { id: true, status: true, service: true, language: true, durationMinutes: true, priceMinor: true, currency: true, createdAt: true, scheduledAt: true, clientId: true, counselor: { select: { userId: true, displayName: true } } },
    });
  }

  /** Daily: unpaid bookings past their window → EXPIRED. */
  async expireUnpaid(now = new Date()) {
    const r = await this.prisma.consultation.updateMany({ where: { status: 'AWAITING_PAYMENT', expiresAt: { lt: now } }, data: { status: 'EXPIRED' } });
    return r.count;
  }
}

@ApiTags('consultations')
@ApiBearerAuth()
@Controller('v1')
export class ConsultationsController {
  constructor(private readonly svc: ConsultationsService) {}

  // counselor (professional accounts; pending ones can complete their application)
  @AllowPending() @ProfessionalsOnly() @RateLimit(20, 3600) @Post('counselors/me/credentials/upload-url')
  credential(@CurrentUser() u: AuthUser, @Body() dto: CredentialUploadDto) {
    return this.svc.credentialUploadUrl(u.id, dto);
  }
  @AllowPending() @ProfessionalsOnly() @RateLimit(10, 86400) @Put('counselors/me') @HttpCode(200)
  apply(@CurrentUser() u: AuthUser, @Body() dto: CounselorApplyDto) {
    return this.svc.apply(u.id, dto);
  }
  @AllowPending() @ProfessionalsOnly() @Get('counselors/me')
  mine(@CurrentUser() u: AuthUser) {
    return this.svc.mine(u.id);
  }
  @ProfessionalsOnly() @Put('counselors/me/offerings') @HttpCode(200)
  offering(@CurrentUser() u: AuthUser, @Body() dto: OfferingDto) {
    return this.svc.upsertOffering(u.id, dto);
  }
  @ProfessionalsOnly() @Get('counselors/me/bookings')
  desk(@CurrentUser() u: AuthUser, @Query('status') status?: string) {
    return this.svc.counselorBookings(u.id, status);
  }
  @ProfessionalsOnly() @Post('consultations/:id/confirm') @HttpCode(200)
  confirm(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ConfirmDto) {
    return this.svc.confirm(u.id, id, dto);
  }
  @ProfessionalsOnly() @Post('consultations/:id/decline') @HttpCode(200)
  decline(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReasonDto) {
    return this.svc.decline(u.id, id, dto);
  }
  @ProfessionalsOnly() @Post('consultations/:id/complete') @HttpCode(200)
  complete(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.complete(u.id, id);
  }

  // client
  @Get('counselors')
  list(@Query() q: CounselorListQuery) {
    return this.svc.list(q);
  }
  @Get('counselors/:id')
  details(@Param('id', ParseUUIDPipe) id: string) {
    return this.svc.details(id);
  }
  @MembersOnly() @RateLimit(20, 3600) @Post('consultations')
  book(@CurrentUser() u: AuthUser, @Body() dto: BookDto) {
    return this.svc.book(u.id, dto);
  }
  @MembersOnly() @Get('consultations/pending-review')
  pending(@CurrentUser() u: AuthUser) {
    return this.svc.pendingReviews(u.id);
  }
  @MembersOnly() @Get('consultations')
  my(@CurrentUser() u: AuthUser) {
    return this.svc.myBookings(u.id);
  }
  @Get('consultations/:id')
  one(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.mineOne(u.id, id);
  }
  @MembersOnly() @Post('consultations/:id/cancel') @HttpCode(200)
  cancel(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.cancel(u.id, id);
  }
  @MembersOnly() @Post('consultations/:id/review') @HttpCode(201)
  review(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReviewDto) {
    return this.svc.review(u.id, id, dto);
  }
  /** Non-production only (test gateway). */
  @Post('consultations/:id/test-pay') @HttpCode(200)
  testPay(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.testPay(u.id, id);
  }

  // provider → server (signature-verified, no auth header)
  @Public() @RateLimit(600, 60) @Post('payments/webhook/stripe') @HttpCode(200)
  webhook(@Req() req: OlfaRequest & { rawBody?: Buffer }, @Headers('stripe-signature') sig?: string) {
    return this.svc.webhook(req.rawBody, sig);
  }
}

class IntegrityDecisionDto {
  @ApiProperty({ enum: ['CLEARED', 'WARNED', 'SUSPENDED', 'BANNED'] }) @IsIn(['CLEARED', 'WARNED', 'SUSPENDED', 'BANNED']) decision: 'CLEARED' | 'WARNED' | 'SUSPENDED' | 'BANNED';
  @ApiProperty() @IsString() @Length(10, 1000) reason: string;
}

@ApiTags('admin')
@ApiBearerAuth()
@Controller('v1/admin')
export class ConsultationsAdminController {
  constructor(private readonly svc: ConsultationsService, private readonly integrity: IntegrityService) {}

  /** Integrity decision; suspensions and bans also refund the counselor's unconfirmed paid requests. */
  @RequirePermissions('integrity.manage') @Post('integrity/cases/:id/decide') @HttpCode(200)
  async decide(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: IntegrityDecisionDto) {
    const out = await this.integrity.decide(a, id, dto);
    if (dto.decision === 'SUSPENDED' || dto.decision === 'BANNED') await this.svc.closeForSuspended(out.counselorId);
    return out;
  }

  @RequirePermissions('counselors.review') @Get('counselors')
  queue(@Query() q: AdminQueueQuery) {
    return this.svc.adminQueue(q);
  }
  @RequirePermissions('counselors.review') @Get('counselors/:id/credentials/:index')
  credential(@Param('id', ParseUUIDPipe) id: string, @Param('index') index: string) {
    return this.svc.adminCredential(id, Number(index));
  }
  @RequirePermissions('counselors.review') @Post('counselors/:id/approve') @HttpCode(200)
  approve(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.adminDecide(a, id, true);
  }
  @RequirePermissions('counselors.review') @Post('counselors/:id/reject') @HttpCode(200)
  reject(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: AdminRejectDto) {
    return this.svc.adminDecide(a, id, false, dto.reason);
  }
  @RequirePermissions('consultations.manage') @Get('consultations')
  consultations(@Query('status') status?: string) {
    return this.svc.adminConsultations(status);
  }
}

@Module({
  imports: [MediaModule],
  controllers: [ConsultationsController, ConsultationsAdminController],
  providers: [
    ConsultationsService,
    StripeGateway,
    TestGateway,
    {
      provide: PAYMENT_GATEWAY,
      inject: [ENV, StripeGateway, TestGateway],
      useFactory: (env: Env, stripe: StripeGateway, test: TestGateway) => (env.PAYMENT_PROVIDER === 'stripe' ? stripe : test),
    },
  ],
  exports: [ConsultationsService],
})
export class ConsultationsModule {}
