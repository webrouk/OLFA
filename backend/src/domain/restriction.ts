/**
 * Account restrictions decided by the admin panel:
 *  - BANNED                       → permanently closed (cannot be reopened)
 *  - SUSPENDED with suspendedUntil → closed until that date, then active again
 *  - SUSPENDED without a date      → closed until an admin lifts it
 * The app shows a closed-account screen (like the frozen-account one) from these details.
 */
export type Restriction =
  | { kind: 'none' }
  | { kind: 'banned'; reason: string | null; since: Date | null }
  | { kind: 'suspended'; until: Date | null; reason: string | null; since: Date | null };

export interface RestrictableUser {
  status: string;
  suspendedUntil?: Date | null;
  restrictionReason?: string | null;
  restrictedAt?: Date | null;
}

export function restrictionOf(u: RestrictableUser, now = new Date()): Restriction {
  if (u.status === 'BANNED') return { kind: 'banned', reason: u.restrictionReason ?? null, since: u.restrictedAt ?? null };
  if (u.status === 'SUSPENDED') {
    const until = u.suspendedUntil ?? null;
    if (until && until.getTime() <= now.getTime()) return { kind: 'none' }; // expired: active again
    return { kind: 'suspended', until, reason: u.restrictionReason ?? null, since: u.restrictedAt ?? null };
  }
  return { kind: 'none' };
}

/** Error details sent to the app (no internal notes). */
export function restrictionDetails(r: Restriction): Record<string, unknown> | undefined {
  if (r.kind === 'banned') return { permanent: true, reason: r.reason, since: r.since?.toISOString() ?? null };
  if (r.kind === 'suspended') return { permanent: false, until: r.until?.toISOString() ?? null, reason: r.reason, since: r.since?.toISOString() ?? null };
  return undefined;
}
