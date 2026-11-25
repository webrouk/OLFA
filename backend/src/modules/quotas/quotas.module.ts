import { Controller, Get, Global, Injectable, Module } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Prisma, PlanCode } from '@prisma/client';
import { fromPgError } from '../../common/errors';
import { AllowPending, AuthUser, CurrentUser, Public } from '../../common/http';
import { PrismaService, SettingsService } from '../../common/infra';
import { adsForMember, parseAdsSettings } from '../../domain/ads';
import { dayWindow, DayWindow, monthWindow } from '../../domain/quota-period';

export interface Entitlements {
  plan: PlanCode;
  planExpiresAt: Date | null;
  dailyLikes: number;
  dailyMessages: number;
  dailyUndos: number;
  advancedFilters: boolean;
  seeWhoLikedYou: boolean;
  incognito: boolean;
  priorityVisibility: boolean;
  /** Discovery outside the country the user is in (Free: own country only). */
  searchOutsideCountry: boolean;
  /** Conversations visible in Messages + Archive; -1 = unlimited. */
  visibleConversations: number;
  /** Compliments (a message sent with a like) per calendar month. */
  monthlyCompliments: number;
  /** Voice notes a member may send in one conversation; -1 = unlimited. */
  voiceNotesPerConversation: number;
  /** Native ads in Discovery: only ever true on the Free plan. */
  showAds: boolean;
}

/** Resolves the user's effective plan and its feature values from the DB. */
@Injectable()
export class EntitlementsService {
  private planCache = new Map<PlanCode, { values: Record<string, unknown>; at: number }>();
  constructor(private readonly prisma: PrismaService) {}

  async forUser(userId: string): Promise<Entitlements> {
    const sub = await this.prisma.userSubscription.findFirst({
      where: { userId, status: { in: ['ACTIVE', 'GRACE_PERIOD', 'CANCELLED'] }, expiresAt: { gt: new Date() } },
      orderBy: { expiresAt: 'desc' },
      select: { expiresAt: true, plan: { select: { code: true } } },
    });
    const plan = sub?.plan.code ?? 'FREE';
    const v = await this.planValues(plan);
    const num = (k: string) => (typeof v[k] === 'number' ? (v[k] as number) : 0);
    const bool = (k: string) => v[k] === true;
    return {
      plan,
      planExpiresAt: sub?.expiresAt ?? null,
      dailyLikes: num('daily_likes'),
      dailyMessages: num('daily_messages'),
      dailyUndos: num('daily_undos'),
      advancedFilters: bool('advanced_filters'),
      seeWhoLikedYou: bool('see_who_liked_you'),
      incognito: bool('incognito'),
      priorityVisibility: bool('priority_visibility'),
      searchOutsideCountry: bool('search_outside_country'),
      visibleConversations: typeof v['visible_conversations'] === 'number' ? (v['visible_conversations'] as number) : 5,
      monthlyCompliments: num('monthly_compliments'),
      voiceNotesPerConversation: typeof v['voice_notes_per_conversation'] === 'number' ? (v['voice_notes_per_conversation'] as number) : 10,
      showAds: plan === 'FREE' && bool('show_ads'),
    };
  }

  invalidate() {
    this.planCache.clear();
  }

  private async planValues(code: PlanCode): Promise<Record<string, unknown>> {
    const hit = this.planCache.get(code);
    if (hit && Date.now() - hit.at < 30_000) return hit.values;
    const rows = await this.prisma.featureEntitlement.findMany({ where: { plan: { code } }, select: { featureKey: true, value: true } });
    const values = Object.fromEntries(rows.map((r) => [r.featureKey, r.value]));
    this.planCache.set(code, { values, at: Date.now() });
    return values;
  }
}

export type CounterKey = 'likes' | 'messages' | 'undos' | 'compliments' | `msg:${string}`;

/** Server-side daily quotas. UTC storage, user-local reset. */
@Injectable()
export class QuotaService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
    private readonly settings: SettingsService,
  ) {}

  async window(userId: string, now = new Date()): Promise<DayWindow> {
    const u = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { timezone: true } });
    return dayWindow(now, u.timezone);
  }

  /** Atomically consume one unit (throws QUOTA_EXCEEDED). Returns remaining. */
  async consume(userId: string, key: CounterKey, limit: number, ref?: { type: string; id: string }, tx?: Prisma.TransactionClient, period?: DayWindow): Promise<number> {
    const w = period ?? (await this.window(userId));
    const db = tx ?? this.prisma;
    try {
      const rows = await db.$queryRaw<{ remaining: number }[]>`
        SELECT olfa_consume_quota(${userId}::uuid, ${key}, ${w.start}, ${w.end}, ${limit}, ${ref?.type ?? null}, ${ref?.id ?? null}) AS remaining`;
      return rows[0].remaining;
    } catch (e) {
      throw fromPgError(e) ?? e;
    }
  }

  async used(userId: string, key: CounterKey, w: DayWindow): Promise<number> {
    const row = await this.prisma.usageCounter.findUnique({
      where: { userId_counterKey_periodStart: { userId, counterKey: key, periodStart: w.start } },
      select: { used: true },
    });
    return row?.used ?? 0;
  }

  async status(userId: string) {
    const [e, w] = await Promise.all([this.entitlements.forUser(userId), this.window(userId)]);
    const acct = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { timezone: true, status: true } });
    const tz = acct.timezone;
    const mw = monthWindow(new Date(), tz);
    const [likes, messages, undos, compliments] = await Promise.all([
      this.used(userId, 'likes', w),
      this.used(userId, 'messages', w),
      this.used(userId, 'undos', w),
      this.used(userId, 'compliments', mw),
    ]);
    const c = (used: number, limit: number) => ({ used, limit, remaining: Math.max(0, limit - used) });
    const ads = adsForMember(e.plan, e.showAds, parseAdsSettings(await this.settings.get('ads.discovery', {})));
    return {
      plan: e.plan,
      planExpiresAt: e.planExpiresAt,
      // PENDING_VERIFICATION: discovery is read-only until the profile is approved
      accountStatus: acct.status,
      resetsAt: w.end, // client renders in local time
      likes: c(likes, e.dailyLikes),
      messages: c(messages, e.dailyMessages),
      undos: c(undos, e.dailyUndos),
      compliments: { ...c(compliments, e.monthlyCompliments), resetsAt: mw.end, period: 'month' },
      features: {
        advancedFilters: e.advancedFilters,
        seeWhoLikedYou: e.seeWhoLikedYou,
        incognito: e.incognito,
        priorityVisibility: e.priorityVisibility,
        searchOutsideCountry: e.searchOutsideCountry,
        visibleConversations: e.visibleConversations,
        voiceNotesPerConversation: e.voiceNotesPerConversation,
        monthlyCompliments: e.monthlyCompliments,
      },
      // Discovery native ads (Free plan only); the app re-reads this after any plan change.
      ads,
    };
  }
}

@ApiTags('entitlements')
@ApiBearerAuth()
@Controller('v1/me/entitlements')
export class EntitlementsController {
  constructor(private readonly quotas: QuotaService) {}

  /** Plan, feature flags and today's quotas — the app's single source of truth. */
  @AllowPending()
  @Get()
  get(@CurrentUser() u: AuthUser) {
    return this.quotas.status(u.id);
  }
}

@ApiTags('entitlements')
@Controller('v1')
export class PlansController {
  constructor(private readonly prisma: PrismaService) {}

  /** Plans and their (admin-managed) features. Prices come from the stores at purchase time. */
  @Public() @Get('plans')
  async plans() {
    const plans = await this.prisma.subscriptionPlan.findMany({
      where: { isActive: true },
      orderBy: { sortOrder: 'asc' },
      select: { code: true, nameAr: true, nameEn: true, entitlements: { select: { featureKey: true, value: true } }, products: { where: { isActive: true }, select: { provider: true, productId: true, durationDays: true } } },
    });
    return plans.map((p) => ({ ...p, entitlements: Object.fromEntries(p.entitlements.map((e) => [e.featureKey, e.value])) }));
  }

  @ApiBearerAuth() @AllowPending() @Get('me/payments')
  payments(@CurrentUser() u: AuthUser) {
    return this.prisma.payment.findMany({
      where: { userId: u.id },
      orderBy: { createdAt: 'desc' },
      take: 100,
      select: { id: true, provider: true, amountMinor: true, currency: true, status: true, createdAt: true, subscription: { select: { plan: { select: { code: true } } } } },
    });
  }
}

@Global()
@Module({
  controllers: [EntitlementsController, PlansController],
  providers: [EntitlementsService, QuotaService],
  exports: [EntitlementsService, QuotaService],
})
export class QuotasModule {}
