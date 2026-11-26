/**
 * Counselor plans — the rules in one place.
 *
 * Licensed professionals (psychologists, family counselors) never use
 * Discovery, likes or member search, and never see ads (ads run in Discovery
 * only). Their paid plans sell visibility and insight instead:
 *   - directory_boost  0 / 1 / 2: placed higher in the counselor directory
 *                      (boost first, then rating, then number of ratings);
 *   - featured_badge   a "Featured counselor" mark on their card and profile;
 *   - profile_insights profile views, unique visitors and paid requests over
 *                      the last 30 days (who looked is never shown).
 * A plan is for members or for professionals, never both; FREE is everyone's base.
 */

export type AccountKind = 'MEMBER' | 'PSYCHOLOGIST' | 'FAMILY_COUNSELOR';
export type Audience = 'MEMBER' | 'PROFESSIONAL';

export const isProfessional = (t: AccountKind | null | undefined): boolean => t === 'PSYCHOLOGIST' || t === 'FAMILY_COUNSELOR';

/** May an account of this type hold this plan? (Also a DB trigger, P0076.) */
export function planFitsAccount(audience: Audience, accountType: AccountKind | null | undefined): boolean {
  if (!accountType) return true; // not chosen yet: nothing to buy before sign-up ends anyway
  return (audience === 'PROFESSIONAL') === isProfessional(accountType);
}

/** Which plan audience an account type shops in. */
export const audienceOf = (t: AccountKind | null | undefined): Audience => (isProfessional(t) ? 'PROFESSIONAL' : 'MEMBER');

/** Directory page cursor: the last row's sort key (boost, rating, ratings count, id). */
export interface DirectoryKey {
  boost: number;
  rating: number;
  count: number;
  id: string;
}

export function encodeDirectoryCursor(k: DirectoryKey): string {
  return Buffer.from(`${k.boost}|${k.rating}|${k.count}|${k.id}`).toString('base64url');
}

/** Lenient: a bad or old-style cursor restarts from the top instead of failing. */
export function decodeDirectoryCursor(s: string | undefined): DirectoryKey | null {
  if (!s) return null;
  const parts = Buffer.from(s, 'base64url').toString('utf8').split('|');
  if (parts.length !== 4) return null;
  const [b, r, c, id] = parts;
  const boost = Number(b), rating = Number(r), count = Number(c);
  if (![0, 1, 2].includes(boost) || !Number.isFinite(rating) || rating < 0 || rating > 5 || !Number.isInteger(count) || count < 0) return null;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  return { boost, rating, count, id };
}

/** Sort order of the directory, as a comparator (tests mirror the SQL with it). */
export function compareDirectory(a: DirectoryKey, b: DirectoryKey): number {
  return b.boost - a.boost || b.rating - a.rating || b.count - a.count || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}

/** Insights over the last 30 days; conversion is requests per unique visitor (0–1, 2 decimals). */
export function insightsSummary(views: number, uniqueVisitors: number, requests: number) {
  const conversion = uniqueVisitors > 0 ? Math.round(Math.min(1, requests / uniqueVisitors) * 100) / 100 : 0;
  return { days: 30, views, uniqueVisitors, requests, conversion };
}
