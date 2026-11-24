/**
 * Store subscriptions (App Store / Google Play) normalised into one snapshot,
 * then mapped to OLFA's subscription status. Both stores recommend acting on
 * the CURRENT state of a subscription (re-read after every notification)
 * rather than replaying events, so everything here is a pure function of the
 * latest verified store data.
 *
 * Store policy notes encoded here:
 *  • Upgrades take effect immediately (Apple: higher service level in the
 *    group; Google: replacement mode with proration). Downgrades take effect
 *    at the next renewal → `pendingProductId`.
 *  • Cancelling turns auto-renew off; access continues until the period ends.
 *  • Grace period keeps access; billing retry / on hold / paused do not.
 *  • Refunds and revocations remove access immediately.
 *  • Google purchases must be acknowledged within 3 days or Google refunds them.
 */

export type StoreProvider = 'APPLE' | 'GOOGLE';
export type StoreState = 'ACTIVE' | 'GRACE' | 'BILLING_RETRY' | 'ON_HOLD' | 'PAUSED' | 'EXPIRED' | 'REFUNDED' | 'REVOKED' | 'PENDING';

export interface StoreSnapshot {
  provider: StoreProvider;
  /** Apple originalTransactionId · Google purchaseToken */
  originalId: string;
  /** Google: token this purchase replaced (upgrade/downgrade/resubscribe). */
  replacesOriginalId: string | null;
  productId: string;
  expiresAt: Date;
  /** null = unknown (keep the stored value). */
  autoRenew: boolean | null;
  /** Product that takes over at the next renewal (scheduled downgrade/crossgrade). */
  pendingProductId: string | null;
  state: StoreState;
  graceUntil: Date | null;
  /** Apple appAccountToken / Google obfuscatedExternalAccountId — OLFA user id set at purchase. */
  accountToken: string | null;
  latestTransactionId: string | null;
  priceMinor: number | null;
  currency: string | null;
  sandbox: boolean;
  needsAcknowledge: boolean;
}

// ── Apple ──────────────────────────────────────────────────────────

/** JWSTransactionDecodedPayload (fields used). */
export interface AppleTransaction {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  bundleId: string;
  purchaseDate: number;
  expiresDate?: number;
  revocationDate?: number;
  revocationReason?: number;
  appAccountToken?: string;
  environment: 'Production' | 'Sandbox' | string;
  inAppOwnershipType?: 'PURCHASED' | 'FAMILY_SHARED' | string;
  type?: string;
  price?: number; // milliunits
  currency?: string;
}

/** JWSRenewalInfoDecodedPayload (fields used). */
export interface AppleRenewalInfo {
  originalTransactionId: string;
  productId: string;
  autoRenewProductId?: string;
  autoRenewStatus?: 0 | 1;
  isInBillingRetryPeriod?: boolean;
  gracePeriodExpiresDate?: number;
  expirationIntent?: number;
}

/** price is in milliunits of the currency; convert to minor units for the currency's exponent. */
export function milliToMinor(milli: number, exponent: number): number {
  return Math.round((milli / 1000) * 10 ** exponent);
}

export function appleSnapshot(tx: AppleTransaction, renewal: AppleRenewalInfo | null, now: Date, exponentOf?: (c: string) => number): StoreSnapshot {
  if (!tx.expiresDate) throw new Error('not an auto-renewable subscription transaction');
  const expires = new Date(tx.expiresDate);
  const grace = renewal?.gracePeriodExpiresDate ? new Date(renewal.gracePeriodExpiresDate) : null;
  let state: StoreState;
  if (tx.revocationDate) state = tx.inAppOwnershipType === 'FAMILY_SHARED' && tx.revocationReason == null ? 'REVOKED' : 'REFUNDED';
  else if (expires > now) state = 'ACTIVE';
  else if (renewal?.isInBillingRetryPeriod) state = grace && grace > now ? 'GRACE' : 'BILLING_RETRY';
  else state = 'EXPIRED';
  const pending = renewal?.autoRenewProductId && renewal.autoRenewProductId !== tx.productId ? renewal.autoRenewProductId : null;
  let priceMinor: number | null = null;
  if (tx.price != null && tx.currency && exponentOf) {
    try {
      priceMinor = milliToMinor(tx.price, exponentOf(tx.currency));
    } catch {
      priceMinor = null;
    }
  }
  return {
    provider: 'APPLE',
    originalId: tx.originalTransactionId,
    replacesOriginalId: null,
    productId: tx.productId,
    expiresAt: state === 'GRACE' && grace ? grace : expires,
    autoRenew: renewal ? renewal.autoRenewStatus === 1 : null,
    pendingProductId: pending,
    state,
    graceUntil: state === 'GRACE' ? grace : null,
    accountToken: tx.appAccountToken?.toLowerCase() ?? null,
    latestTransactionId: tx.transactionId,
    priceMinor,
    currency: tx.currency ?? null,
    sandbox: tx.environment !== 'Production',
    needsAcknowledge: false,
  };
}

// ── Google ─────────────────────────────────────────────────────────

/** purchases.subscriptionsv2 resource (fields used). */
export interface GoogleSubscriptionV2 {
  subscriptionState: string;
  latestOrderId?: string;
  linkedPurchaseToken?: string;
  acknowledgementState?: string;
  testPurchase?: object;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  lineItems: {
    productId: string;
    expiryTime: string;
    autoRenewingPlan?: { autoRenewEnabled?: boolean };
    deferredItemReplacement?: { productId: string };
  }[];
}

export function googleSnapshot(token: string, r: GoogleSubscriptionV2, now: Date): StoreSnapshot {
  if (!r.lineItems?.length) throw new Error('subscription has no line items');
  const item = [...r.lineItems].sort((a, b) => Date.parse(b.expiryTime) - Date.parse(a.expiryTime))[0];
  const expires = new Date(item.expiryTime);
  const autoRenew = item.autoRenewingPlan ? item.autoRenewingPlan.autoRenewEnabled === true : null;
  let state: StoreState;
  switch (r.subscriptionState) {
    case 'SUBSCRIPTION_STATE_ACTIVE':
    case 'SUBSCRIPTION_STATE_CANCELED': // auto-renew off, still paid until expiry
      state = expires > now ? 'ACTIVE' : 'EXPIRED';
      break;
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD':
      state = expires > now ? 'GRACE' : 'ON_HOLD';
      break;
    case 'SUBSCRIPTION_STATE_ON_HOLD':
      state = 'ON_HOLD';
      break;
    case 'SUBSCRIPTION_STATE_PAUSED':
      state = 'PAUSED';
      break;
    case 'SUBSCRIPTION_STATE_PENDING':
      state = 'PENDING';
      break;
    default: // EXPIRED, PENDING_PURCHASE_CANCELED, UNSPECIFIED
      state = 'EXPIRED';
  }
  return {
    provider: 'GOOGLE',
    originalId: token,
    replacesOriginalId: r.linkedPurchaseToken ?? null,
    productId: item.productId,
    expiresAt: expires,
    autoRenew: r.subscriptionState === 'SUBSCRIPTION_STATE_CANCELED' ? false : autoRenew,
    pendingProductId: item.deferredItemReplacement?.productId ?? null,
    state,
    graceUntil: state === 'GRACE' ? expires : null,
    accountToken: r.externalAccountIdentifiers?.obfuscatedExternalAccountId?.toLowerCase() ?? null,
    latestTransactionId: r.latestOrderId ?? null,
    priceMinor: null,
    currency: null,
    sandbox: !!r.testPurchase,
    needsAcknowledge: r.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' && state !== 'PENDING',
  };
}

// ── OLFA status ────────────────────────────────────────────────────

export type OlfaSubStatus = 'ACTIVE' | 'GRACE_PERIOD' | 'BILLING_RETRY' | 'ON_HOLD' | 'PAUSED' | 'CANCELLED' | 'EXPIRED' | 'REFUNDED' | 'REVOKED' | 'PENDING';

export interface Derived {
  status: OlfaSubStatus;
  entitled: boolean;
  /** The date access ends (or ended). */
  expiresAt: Date;
  autoRenew: boolean;
}

/** Statuses that grant access while expiresAt is in the future (mirrors EntitlementsService). */
export const ENTITLED_STATUSES: OlfaSubStatus[] = ['ACTIVE', 'GRACE_PERIOD', 'CANCELLED'];

export function deriveStatus(s: StoreSnapshot, now: Date, storedAutoRenew = true): Derived {
  const autoRenew = s.autoRenew ?? storedAutoRenew;
  const map: Record<StoreState, OlfaSubStatus> = {
    ACTIVE: autoRenew ? 'ACTIVE' : 'CANCELLED',
    GRACE: 'GRACE_PERIOD',
    BILLING_RETRY: 'BILLING_RETRY',
    ON_HOLD: 'ON_HOLD',
    PAUSED: 'PAUSED',
    EXPIRED: 'EXPIRED',
    REFUNDED: 'REFUNDED',
    REVOKED: 'REVOKED',
    PENDING: 'PENDING',
  };
  const status = map[s.state];
  const entitled = ENTITLED_STATUSES.includes(status) && s.expiresAt > now;
  return { status, entitled, expiresAt: s.expiresAt, autoRenew };
}

export type PlanLevel = 'FREE' | 'PLUS' | 'PREMIUM';
const RANK: Record<PlanLevel, number> = { FREE: 0, PLUS: 1, PREMIUM: 2 };

export type PlanChange = 'new' | 'renewal' | 'upgrade' | 'downgrade_scheduled' | 'downgrade' | 'none';

/**
 * What changed between the stored plan and the store's current data.
 * A downgrade is only ever "scheduled" while the higher plan is still paid for.
 */
export function classifyChange(prev: { plan: PlanLevel; expiresAt: Date; pendingPlan: PlanLevel | null } | null, next: { plan: PlanLevel; expiresAt: Date; pendingPlan: PlanLevel | null }): PlanChange {
  if (!prev) return 'new';
  if (RANK[next.plan] > RANK[prev.plan]) return 'upgrade';
  if (RANK[next.plan] < RANK[prev.plan]) return 'downgrade';
  if (next.pendingPlan && RANK[next.pendingPlan] < RANK[next.plan] && next.pendingPlan !== prev.pendingPlan) return 'downgrade_scheduled';
  if (next.expiresAt.getTime() > prev.expiresAt.getTime()) return 'renewal';
  return 'none';
}

/**
 * Which account a store purchase belongs to. The token set at purchase time
 * (our user id) wins; otherwise the account that restores it. A purchase that
 * already belongs to another OLFA account moves only on an explicit restore
 * by the signed-in user of the same store account.
 */
export function resolveOwner(opts: { accountToken: string | null; currentOwner: string | null; requester: string; isRestore: boolean }): { owner: string; transferred: boolean } | { error: 'belongs_to_another_account' } {
  const { accountToken, currentOwner, requester, isRestore } = opts;
  if (accountToken && accountToken !== requester.toLowerCase()) {
    if (!isRestore) return { error: 'belongs_to_another_account' };
  }
  if (!currentOwner || currentOwner === requester) return { owner: requester, transferred: false };
  return isRestore ? { owner: requester, transferred: true } : { error: 'belongs_to_another_account' };
}

/** Deep links the app opens for "Manage subscription" / "Fix payment". */
export function manageUrl(provider: StoreProvider, opts: { packageName?: string; productId?: string } = {}): string {
  if (provider === 'APPLE') return 'https://apps.apple.com/account/subscriptions';
  const q = opts.productId && opts.packageName ? `?sku=${encodeURIComponent(opts.productId)}&package=${encodeURIComponent(opts.packageName)}` : '';
  return `https://play.google.com/store/account/subscriptions${q}`;
}
