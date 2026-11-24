import { Body, Controller, Get, HttpCode, Inject, Injectable, Logger, Module, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { PaymentProvider, Prisma, SubscriptionStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsOptional, IsString, MaxLength, ValidateNested } from 'class-validator';
import { timingSafeEqual } from 'node:crypto';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { AllowPending, AuthUser, CurrentUser, MembersOnly, Public, RateLimit } from '../../common/http';
import { AuditService, PrismaService } from '../../common/infra';
import { currencyExponent } from '../../domain/payments';
import { appleSnapshot, classifyChange, deriveStatus, googleSnapshot, manageUrl, PlanLevel, resolveOwner, StoreSnapshot } from '../../domain/store-subscriptions';
import { NotificationsService } from '../notifications/notifications.module';
import { EntitlementsService } from '../quotas/quotas.module';
import { StoreGateway } from './store.gateway';

class AppleVerifyDto {
  @ApiProperty({ description: 'StoreKit 2 signed transaction (JWS)' }) @IsString() @MaxLength(20_000) signedTransaction: string;
  @ApiPropertyOptional({ description: 'Signed renewal info (JWS) from Product.SubscriptionInfo.Status' }) @IsOptional() @IsString() @MaxLength(20_000) signedRenewalInfo?: string;
}
class GoogleVerifyDto {
  @ApiProperty() @IsString() @MaxLength(120) productId: string;
  @ApiProperty() @IsString() @MaxLength(4096) purchaseToken: string;
}
class RestoreDto {
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @MaxLength(20_000, { each: true }) apple?: string[];
  @ApiPropertyOptional({ type: [GoogleVerifyDto] }) @IsOptional() @IsArray() @ArrayMaxSize(20) @ValidateNested({ each: true }) @Type(() => GoogleVerifyDto) google?: GoogleVerifyDto[];
}
class AppleNotificationDto {
  @ApiProperty() @IsString() @MaxLength(100_000) signedPayload: string;
}

type Source = 'purchase' | 'restore' | 'notification';

/**
 * In-app subscriptions (Plus / Premium) on the App Store and Google Play.
 * The store is the source of truth: every purchase, renewal, upgrade,
 * downgrade, cancellation, billing problem, refund and restore is verified
 * with the store and applied from its CURRENT state (domain/store-subscriptions).
 */
@Injectable()
export class SubscriptionsService {
  private readonly log = new Logger('Subscriptions');
  constructor(
    private readonly prisma: PrismaService,
    private readonly store: StoreGateway,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
    private readonly entitlements: EntitlementsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async products() {
    const rows = await this.prisma.planProduct.findMany({ where: { isActive: true, plan: { isActive: true } }, select: { provider: true, productId: true, durationDays: true, plan: { select: { code: true, sortOrder: true } } } });
    return rows.map((r) => ({ plan: r.plan.code, provider: r.provider, productId: r.productId, durationDays: r.durationDays }));
  }

  private async planOf(provider: PaymentProvider, productId: string) {
    const p = await this.prisma.planProduct.findUnique({ where: { provider_productId: { provider, productId } }, select: { planId: true, plan: { select: { code: true } } } });
    if (!p) throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, `unknown product ${productId}`);
    return { planId: p.planId, code: p.plan.code as PlanLevel };
  }

  /** The heart of it: write the store's current state for one subscription. */
  async apply(s: StoreSnapshot, requester: string | null, source: Source) {
    const now = new Date();
    const provider = s.provider as PaymentProvider;
    const plan = await this.planOf(provider, s.productId);
    const pendingPlan = s.pendingProductId ? (await this.planOf(provider, s.pendingProductId).catch(() => null))?.code ?? null : null;
    const existing = await this.prisma.userSubscription.findUnique({
      where: { provider_originalTransactionId: { provider, originalTransactionId: s.originalId } },
      include: { plan: { select: { code: true } } },
    });

    // Who owns it
    let owner: string | null;
    if (requester) {
      const r = resolveOwner({ accountToken: s.accountToken, currentOwner: existing?.userId ?? null, requester, isRestore: source === 'restore' });
      if ('error' in r) throw new AppError(ErrorCode.CONFLICT, 'This purchase belongs to another OLFA account — use Restore purchases while signed in to it');
      owner = r.owner;
      if (r.transferred) await this.audit.record({ actorType: 'USER', actorId: requester, action: 'subscription.transfer', entityType: 'subscription', entityId: existing!.id, before: { userId: existing!.userId } });
    } else {
      owner = existing?.userId ?? (s.accountToken && (await this.prisma.user.findUnique({ where: { id: s.accountToken }, select: { id: true } }))?.id) ?? null;
    }
    if (!owner) {
      this.log.warn(`store event for an unknown subscription ${provider}:${s.originalId.slice(0, 12)}…`);
      return null;
    }

    const d = deriveStatus(s, now, existing?.autoRenew ?? true);
    const change = classifyChange(existing ? { plan: existing.plan.code as PlanLevel, expiresAt: existing.expiresAt, pendingPlan: null } : null, { plan: plan.code, expiresAt: d.expiresAt, pendingPlan });
    const data = {
      userId: owner,
      planId: plan.planId,
      status: d.status as SubscriptionStatus,
      productId: s.productId,
      expiresAt: d.expiresAt,
      autoRenew: d.autoRenew,
      pendingProductId: s.pendingProductId,
      graceUntil: s.graceUntil,
      sandbox: s.sandbox,
      lastVerifiedAt: now,
      latestTransactionId: s.latestTransactionId,
      cancelledAt: d.status === 'CANCELLED' ? existing?.cancelledAt ?? now : null,
    };

    const sub = await this.prisma.$transaction(async (tx) => {
      const row = existing
        ? await tx.userSubscription.update({ where: { id: existing.id }, data })
        : await tx.userSubscription.create({ data: { ...data, provider, originalTransactionId: s.originalId, startsAt: now } });
      // Google: an upgrade/downgrade issues a new token; the old one stops now.
      if (s.replacesOriginalId) {
        await tx.userSubscription.updateMany({
          where: { provider, originalTransactionId: s.replacesOriginalId, replacedBy: null },
          data: { status: 'EXPIRED', expiresAt: now, replacedBy: row.id, autoRenew: false },
        });
      }
      await this.recordPayment(tx, row.id, owner!, provider, s, d.status);
      return row;
    });

    if (s.needsAcknowledge && provider === 'GOOGLE') await this.store.googleAcknowledge(s.productId, s.originalId);
    this.entitlements.invalidate();
    if (change !== 'none' || existing?.status !== d.status) {
      await this.audit.record({ actorType: source === 'notification' ? 'SYSTEM' : 'USER', actorId: requester ?? undefined, action: `subscription.${change === 'none' ? d.status.toLowerCase() : change}`, entityType: 'subscription', entityId: sub.id, before: existing ? { plan: existing.plan.code, status: existing.status } : undefined, after: { plan: plan.code, status: d.status, pending: pendingPlan, expiresAt: d.expiresAt } });
    }
    if (source === 'notification' && existing?.status !== d.status) {
      if (d.status === 'BILLING_RETRY' || d.status === 'ON_HOLD' || d.status === 'GRACE_PERIOD') await this.notifications.notify(owner, 'SUBSCRIPTION', 'push.subscription_billing_issue', { provider });
      if (d.status === 'EXPIRED') await this.notifications.notify(owner, 'SUBSCRIPTION', 'push.subscription_expired', { provider });
    }
    return { id: sub.id, plan: plan.code, status: d.status, entitled: d.entitled, expiresAt: d.expiresAt, autoRenew: d.autoRenew, pendingPlan, change };
  }

  /** One payment row per store transaction/order; refunds update it. */
  private async recordPayment(tx: Prisma.TransactionClient, subscriptionId: string, userId: string, provider: PaymentProvider, s: StoreSnapshot, status: string) {
    if (!s.latestTransactionId) return;
    const key = { provider_providerPaymentId: { provider, providerPaymentId: s.latestTransactionId } };
    const existing = await tx.payment.findUnique({ where: key, select: { id: true, status: true } });
    if (status === 'REFUNDED') {
      if (existing && existing.status !== 'REFUNDED') {
        await tx.payment.update({ where: { id: existing.id }, data: { status: 'REFUNDED', refundedAt: new Date() } });
        await tx.transaction.create({ data: { paymentId: existing.id, type: 'REFUND', amountMinor: -(s.priceMinor ?? 0), currency: s.currency ?? 'USD' } });
      }
      return;
    }
    if (existing || s.state === 'PENDING') return;
    const p = await tx.payment.create({ data: { userId, subscriptionId, provider, providerPaymentId: s.latestTransactionId, amountMinor: s.priceMinor, currency: s.currency, status: 'SUCCEEDED' } });
    if (s.priceMinor != null && s.currency) await tx.transaction.create({ data: { paymentId: p.id, type: 'CHARGE', amountMinor: s.priceMinor, currency: s.currency } });
  }

  // ── client calls ──

  async verifyApple(userId: string, dto: AppleVerifyDto, source: Source = 'purchase') {
    const tx = this.store.appleTransaction(dto.signedTransaction);
    let renewal = dto.signedRenewalInfo ? this.store.appleRenewal(dto.signedRenewalInfo) : null;
    if (renewal && renewal.originalTransactionId !== tx.originalTransactionId) renewal = null;
    // Prefer the server's fresh copy when the App Store Server API is configured.
    const fresh = await this.store.appleStatus(tx.originalTransactionId, tx.environment !== 'Production').catch(() => null);
    const snap = fresh ? appleSnapshot(fresh.transaction, fresh.renewal, new Date(), currencyExponent) : appleSnapshot(tx, renewal, new Date(), currencyExponent);
    return this.apply(snap, userId, source);
  }

  async verifyGoogle(userId: string, dto: GoogleVerifyDto, source: Source = 'purchase') {
    const r = await this.store.googleSubscription(dto.purchaseToken);
    const snap = googleSnapshot(dto.purchaseToken, r, new Date());
    if (!r.lineItems.some((l) => l.productId === dto.productId)) throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, 'product mismatch');
    return this.apply(snap, userId, source);
  }

  /** "Restore purchases": re-verifies everything the device's store account owns. */
  async restore(userId: string, dto: RestoreDto) {
    const results: unknown[] = [];
    const errors: string[] = [];
    for (const jws of dto.apple ?? []) {
      try {
        results.push(await this.verifyApple(userId, { signedTransaction: jws }, 'restore'));
      } catch (e) {
        errors.push(e instanceof AppError ? e.code : 'ERROR');
      }
    }
    for (const g of dto.google ?? []) {
      try {
        results.push(await this.verifyGoogle(userId, g, 'restore'));
      } catch (e) {
        errors.push(e instanceof AppError ? e.code : 'ERROR');
      }
    }
    return { restored: results.length, errors, current: await this.current(userId) };
  }

  async current(userId: string) {
    const ent = await this.entitlements.forUser(userId);
    const sub = await this.prisma.userSubscription.findFirst({
      where: { userId, replacedBy: null, provider: { in: ['APPLE', 'GOOGLE'] } },
      orderBy: [{ expiresAt: 'desc' }],
      include: { plan: { select: { code: true } } },
    });
    const pendingPlan = sub?.pendingProductId ? (await this.planOf(sub.provider, sub.pendingProductId).catch(() => null))?.code ?? null : null;
    const billingIssue = !!sub && ['GRACE_PERIOD', 'BILLING_RETRY', 'ON_HOLD'].includes(sub.status);
    return {
      plan: ent.plan,
      expiresAt: ent.planExpiresAt,
      /** Passed to the store at purchase (appAccountToken / obfuscatedAccountId) so receipts map back to this account. */
      accountToken: userId,
      store: sub
        ? {
            provider: sub.provider,
            productId: sub.productId,
            plan: sub.plan.code,
            status: sub.status,
            autoRenew: sub.autoRenew,
            expiresAt: sub.expiresAt,
            graceUntil: sub.graceUntil,
            pendingPlan,
            billingIssue,
            manageUrl: manageUrl(sub.provider === 'APPLE' ? 'APPLE' : 'GOOGLE', { packageName: this.env.GOOGLE_PACKAGE_NAME, productId: sub.productId ?? undefined }),
          }
        : null,
    };
  }

  // ── store → server ──

  async appleNotification(dto: AppleNotificationDto) {
    const n = this.store.appleNotification(dto.signedPayload);
    const fresh = await this.prisma.purchaseEvent
      .create({ data: { provider: 'APPLE', eventId: n.notificationUUID, eventType: `${n.notificationType}${n.subtype ? ':' + n.subtype : ''}`, payload: { type: n.notificationType, subtype: n.subtype ?? null } } })
      .catch(() => null);
    if (!fresh) return { duplicate: true }; // Apple retries; process once
    try {
      if (n.data?.signedTransactionInfo) {
        const tx = this.store.appleTransaction(n.data.signedTransactionInfo);
        if (tx.expiresDate) {
          const renewal = n.data.signedRenewalInfo ? this.store.appleRenewal(n.data.signedRenewalInfo) : null;
          const r = await this.apply(appleSnapshot(tx, renewal, new Date(), currencyExponent), null, 'notification');
          await this.prisma.purchaseEvent.update({ where: { id: fresh.id }, data: { processedAt: new Date(), userId: r ? (await this.prisma.userSubscription.findUnique({ where: { id: r.id }, select: { userId: true } }))?.userId : null } });
          return { ok: true };
        }
      }
      await this.prisma.purchaseEvent.update({ where: { id: fresh.id }, data: { processedAt: new Date() } });
      return { ok: true };
    } catch (e) {
      await this.prisma.purchaseEvent.update({ where: { id: fresh.id }, data: { error: String(e).slice(0, 500) } });
      throw e;
    }
  }

  /** Google Real-time developer notifications (Pub/Sub push). */
  async googleRtdn(token: string | undefined, body: { message?: { data?: string; messageId?: string } }) {
    const expected = this.env.GOOGLE_RTDN_TOKEN;
    if (!expected || !token || token.length !== expected.length || !timingSafeEqual(Buffer.from(token), Buffer.from(expected))) throw new AppError(ErrorCode.UNAUTHORIZED);
    const raw = body.message?.data ? Buffer.from(body.message.data, 'base64').toString('utf8') : '{}';
    const n = JSON.parse(raw) as {
      packageName?: string;
      subscriptionNotification?: { notificationType: number; purchaseToken: string; subscriptionId: string };
      voidedPurchaseNotification?: { purchaseToken: string; orderId: string; productType: number };
    };
    if (n.packageName && n.packageName !== this.env.GOOGLE_PACKAGE_NAME) return { ignored: true };
    const eventId = body.message?.messageId ?? `${n.subscriptionNotification?.purchaseToken ?? n.voidedPurchaseNotification?.orderId}:${n.subscriptionNotification?.notificationType ?? 'void'}`;
    const fresh = await this.prisma.purchaseEvent
      .create({ data: { provider: 'GOOGLE', eventId: eventId.slice(0, 200), eventType: n.subscriptionNotification ? `SUB:${n.subscriptionNotification.notificationType}` : n.voidedPurchaseNotification ? 'VOIDED' : 'TEST', payload: { type: n.subscriptionNotification?.notificationType ?? null } } })
      .catch(() => null);
    if (!fresh) return { duplicate: true };
    if (n.subscriptionNotification) {
      const t = n.subscriptionNotification.purchaseToken;
      const r = await this.store.googleSubscription(t);
      await this.apply(googleSnapshot(t, r, new Date()), null, 'notification');
    } else if (n.voidedPurchaseNotification) {
      // Refund / chargeback: access ends now.
      const sub = await this.prisma.userSubscription.findUnique({ where: { provider_originalTransactionId: { provider: 'GOOGLE', originalTransactionId: n.voidedPurchaseNotification.purchaseToken } } });
      if (sub) {
        await this.prisma.$transaction([
          this.prisma.userSubscription.update({ where: { id: sub.id }, data: { status: 'REFUNDED', expiresAt: new Date(), autoRenew: false } }),
          this.prisma.payment.updateMany({ where: { provider: 'GOOGLE', providerPaymentId: n.voidedPurchaseNotification.orderId }, data: { status: 'REFUNDED', refundedAt: new Date() } }),
        ]);
        this.entitlements.invalidate();
      }
    }
    await this.prisma.purchaseEvent.update({ where: { id: fresh.id }, data: { processedAt: new Date() } });
    return { ok: true };
  }
}

@ApiTags('subscriptions')
@ApiBearerAuth()
@Controller('v1/subscriptions')
export class SubscriptionsController {
  constructor(private readonly subs: SubscriptionsService) {}

  @AllowPending() @Get('products')
  products() {
    return this.subs.products();
  }

  @AllowPending() @MembersOnly() @Get('me')
  me(@CurrentUser() u: AuthUser) {
    return this.subs.current(u.id);
  }

  @AllowPending() @MembersOnly() @RateLimit(30, 3600) @Post('apple') @HttpCode(200)
  apple(@CurrentUser() u: AuthUser, @Body() dto: AppleVerifyDto) {
    return this.subs.verifyApple(u.id, dto);
  }

  @AllowPending() @MembersOnly() @RateLimit(30, 3600) @Post('google') @HttpCode(200)
  google(@CurrentUser() u: AuthUser, @Body() dto: GoogleVerifyDto) {
    return this.subs.verifyGoogle(u.id, dto);
  }

  @AllowPending() @MembersOnly() @RateLimit(10, 3600) @Post('restore') @HttpCode(200)
  restore(@CurrentUser() u: AuthUser, @Body() dto: RestoreDto) {
    return this.subs.restore(u.id, dto);
  }

  /** App Store Server Notifications V2 (URL configured in App Store Connect). */
  @Public() @RateLimit(600, 60) @Post('apple/notifications') @HttpCode(200)
  appleNotification(@Body() dto: AppleNotificationDto) {
    return this.subs.appleNotification(dto);
  }

  /** Google Play RTDN through a Pub/Sub push subscription: …/google/rtdn?token=<GOOGLE_RTDN_TOKEN>. */
  @Public() @RateLimit(600, 60) @Post('google/rtdn') @HttpCode(200)
  googleRtdn(@Query('token') token: string | undefined, @Body() body: { message?: { data?: string; messageId?: string } }) {
    return this.subs.googleRtdn(token, body);
  }
}

@Module({ controllers: [SubscriptionsController], providers: [SubscriptionsService, StoreGateway] })
export class SubscriptionsModule {}
