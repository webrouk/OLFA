/**
 * Location & country scope for discovery. Pure functions — unit-tested.
 *
 * Privacy: coordinates are rounded to 2 decimals (~1.1 km) before they are
 * stored, and only a rounded distance ever leaves the server.
 */

export const roundCoord = (x: number) => Math.round(x * 100) / 100;

export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = (d: number) => (d * Math.PI) / 180;
  const a = Math.sin(r(lat2 - lat1) / 2) ** 2 + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(r(lng2 - lng1) / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
}

/** Distance shown to users: whole km, never below 1, hidden beyond 500 km. */
export function publicDistanceKm(km: number | null | undefined, candidateSharesLocation: boolean): number | null {
  if (km == null || !candidateSharesLocation || km > 500) return null;
  return Math.max(1, Math.round(km));
}

/** 0 ≤10 km · 1 ≤50 km · 2 ≤200 km · 3 same country · 4 other country. */
export function proximityTier(km: number | null | undefined, sameCountry: boolean): number {
  if (km != null) {
    if (km <= 10) return 0;
    if (km <= 50) return 1;
    if (km <= 200 && sameCountry) return 2;
  }
  return sameCountry ? 3 : 4;
}

export interface ScopeInput {
  /** Where the viewer is now (detected), falling back to residence. */
  homeCountry: string;
  /** Explicit filter from the request, if any. */
  requestedCountry?: string | null;
  /** Saved partner preferences. */
  prefSameCountryOnly: boolean;
  prefCountries: string[];
  /** Feature entitlement `search_outside_country`. */
  canSearchOutside: boolean;
}

export type Scope = { ok: true; countries: string[] | null } | { ok: false; reason: 'outside_country_requires_plan' };

/**
 * Which countries discovery may return. Free plans stay inside the viewer's
 * own country; asking for another country is refused (the app shows the
 * upgrade sheet), never silently widened.
 */
export function discoveryScope(i: ScopeInput): Scope {
  const home = i.homeCountry.toUpperCase();
  const req = i.requestedCountry?.toUpperCase() ?? null;
  if (!i.canSearchOutside) {
    if (req && req !== home) return { ok: false, reason: 'outside_country_requires_plan' };
    return { ok: true, countries: [home] };
  }
  let countries: string[] | null = null;
  if (i.prefSameCountryOnly) countries = [home];
  else if (i.prefCountries.length) countries = i.prefCountries.map((c) => c.toUpperCase());
  if (req) countries = countries ? countries.filter((c) => c === req) : [req];
  return { ok: true, countries };
}

export interface Placed<T> {
  item: T;
  score: number;
  distanceKm: number | null;
  countryCode: string;
}

/** "Nearest" ordering: proximity tier first, then compatibility, stable. */
export function sortNearest<T>(rows: Placed<T>[], homeCountry: string): Placed<T>[] {
  return rows
    .map((r, i) => ({ r, i, t: proximityTier(r.distanceKm, r.countryCode === homeCountry) }))
    .sort((a, b) => a.t - b.t || b.r.score - a.r.score || (a.r.distanceKm ?? 1e9) - (b.r.distanceKm ?? 1e9) || a.i - b.i)
    .map((x) => x.r);
}
