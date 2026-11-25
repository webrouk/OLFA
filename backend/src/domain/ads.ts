/**
 * Native ads in Discovery (Google AdMob) — the rules in one place.
 *
 *  - Placement: Discovery only, as a card between member cards. Never in chats,
 *    profiles or anywhere else (the app has no other ad slot).
 *  - Audience: the Free plan only. A paid plan never gets ads, whatever the
 *    settings say (also enforced by a DB trigger on feature_entitlements).
 *  - Frequency: first ad after `firstAfter` profiles, then one every `interval`
 *    profiles, at most `maxPerSession` per app session.
 *  - Nothing about the member (age, gender, religion, location…) is sent to the
 *    ad network; `personalized` only controls the npa flag after consent.
 */

export type AdContentRating = 'G' | 'PG' | 'T' | 'MA';

export interface DiscoveryAdsSettings {
  enabled: boolean;
  firstAfter: number;
  interval: number;
  maxPerSession: number;
  preloadAhead: number;
  personalized: boolean;
  maxAdContentRating: AdContentRating;
  units: { android: string; ios: string };
}

export const ADS_DEFAULTS: DiscoveryAdsSettings = {
  enabled: false,
  firstAfter: 4,
  interval: 6,
  maxPerSession: 8,
  preloadAhead: 2,
  personalized: false,
  maxAdContentRating: 'PG',
  units: { android: '', ios: '' },
};

export const ADS_LIMITS = {
  firstAfter: [1, 50],
  interval: [3, 50],
  maxPerSession: [0, 50],
  preloadAhead: [1, 3],
} as const;

/** AdMob ad unit id: ca-app-pub-<16 digits>/<10 digits>. */
export function isAdUnitId(s: string): boolean {
  return /^ca-app-pub-\d{16}\/\d{10}$/.test(s);
}

const RATINGS: AdContentRating[] = ['G', 'PG', 'T', 'MA'];

/** Reads the stored setting leniently (missing / bad fields fall back to defaults). */
export function parseAdsSettings(raw: unknown): DiscoveryAdsSettings {
  const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const int = (k: keyof typeof ADS_LIMITS) => {
    const v = o[k];
    const [lo, hi] = ADS_LIMITS[k];
    return typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi ? v : ADS_DEFAULTS[k];
  };
  const u = o.units && typeof o.units === 'object' ? (o.units as Record<string, unknown>) : {};
  const unit = (k: 'android' | 'ios') => (typeof u[k] === 'string' && isAdUnitId(u[k] as string) ? (u[k] as string) : '');
  return {
    enabled: o.enabled === true,
    firstAfter: int('firstAfter'),
    interval: int('interval'),
    maxPerSession: int('maxPerSession'),
    preloadAhead: int('preloadAhead'),
    personalized: o.personalized === true,
    maxAdContentRating: RATINGS.includes(o.maxAdContentRating as AdContentRating) ? (o.maxAdContentRating as AdContentRating) : ADS_DEFAULTS.maxAdContentRating,
    units: { android: unit('android'), ios: unit('ios') },
  };
}

/** Strict validation for the admin form; returns the field names that are wrong. */
export function invalidAdsFields(s: DiscoveryAdsSettings): string[] {
  const bad: string[] = [];
  for (const k of Object.keys(ADS_LIMITS) as (keyof typeof ADS_LIMITS)[]) {
    const [lo, hi] = ADS_LIMITS[k];
    if (!Number.isInteger(s[k]) || s[k] < lo || s[k] > hi) bad.push(k);
  }
  if (!RATINGS.includes(s.maxAdContentRating)) bad.push('maxAdContentRating');
  for (const k of ['android', 'ios'] as const) if (s.units[k] !== '' && !isAdUnitId(s.units[k])) bad.push(`units.${k}`);
  if (s.enabled && !s.units.android && !s.units.ios) bad.push('units');
  return bad;
}

export type MemberAds =
  | { enabled: false; reason: 'paid_plan' | 'plan_off' | 'switched_off' | 'not_configured' }
  | {
      enabled: true;
      placement: 'discovery';
      firstAfter: number;
      interval: number;
      maxPerSession: number;
      preloadAhead: number;
      personalized: boolean;
      maxAdContentRating: AdContentRating;
      units: { android: string; ios: string };
    };

/** What the app receives in GET /me/entitlements → `ads`. */
export function adsForMember(plan: string, planShowsAds: boolean, s: DiscoveryAdsSettings): MemberAds {
  if (plan !== 'FREE') return { enabled: false, reason: 'paid_plan' };
  if (!planShowsAds) return { enabled: false, reason: 'plan_off' };
  if (!s.enabled) return { enabled: false, reason: 'switched_off' };
  if (!s.units.android && !s.units.ios) return { enabled: false, reason: 'not_configured' };
  return {
    enabled: true,
    placement: 'discovery',
    firstAfter: s.firstAfter,
    interval: s.interval,
    maxPerSession: s.maxPerSession,
    preloadAhead: s.preloadAhead,
    personalized: s.personalized,
    maxAdContentRating: s.maxAdContentRating,
    units: s.units,
  };
}

/**
 * Whether an ad card is due after `decided` profiles this session, given
 * `shown` ads already. Mirrors mobile/lib/features/ads/domain/ad_schedule.dart.
 */
export function adDue(decided: number, shown: number, s: Pick<DiscoveryAdsSettings, 'firstAfter' | 'interval' | 'maxPerSession'>): boolean {
  if (shown >= s.maxPerSession) return false;
  return decided >= s.firstAfter + shown * s.interval;
}
