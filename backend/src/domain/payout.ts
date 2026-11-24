import { createCipheriv, createDecipheriv, createHmac, randomBytes } from 'node:crypto';
import { currencyExponent } from './payments';

/**
 * Counselor payout destinations. Account numbers are never stored in plain
 * text: the details are sealed with AES-256-GCM (key from the environment),
 * a masked form is kept for display, and an HMAC fingerprint lets us detect
 * duplicates and banned accounts without decrypting.
 */
export type PayoutKind = 'BANK_IBAN' | 'BANK_SWIFT' | 'WISE' | 'PAYPAL' | 'PAYONEER';

export interface PayoutDetails {
  kind: PayoutKind;
  holderName: string;
  /** BANK_IBAN */
  iban?: string;
  /** BANK_SWIFT (accounts outside IBAN countries) */
  accountNumber?: string;
  bic?: string;
  bankName?: string;
  /** WISE / PAYPAL / PAYONEER */
  email?: string;
}

// IBAN lengths per country (ISO 13616 registry, the countries we serve + common ones).
const IBAN_LEN: Record<string, number> = {
  AE: 23, SA: 24, QA: 29, KW: 30, BH: 22, OM: 23, JO: 30, EG: 29, LB: 28, IQ: 23, PS: 29, TN: 24, MR: 27, LY: 25, SD: 18, DZ: 26, MA: 28, YE: 30,
  TR: 26, GB: 22, DE: 22, FR: 27, NL: 18, BE: 16, ES: 24, IT: 27, IE: 22, SE: 24, NO: 15, DK: 18, FI: 18, AT: 20, CH: 21, PT: 25, PL: 28, GR: 27, CY: 28, PK: 24, AZ: 28, GE: 22, KZ: 20,
};

export function normalizeIban(s: string): string {
  return s.replace(/[\s-]/g, '').toUpperCase();
}

/** ISO 7064 mod-97-10 check plus the country length table. */
export function isValidIban(raw: string): boolean {
  const iban = normalizeIban(raw);
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$/.test(iban)) return false;
  const len = IBAN_LEN[iban.slice(0, 2)];
  if (len !== undefined && iban.length !== len) return false;
  const moved = iban.slice(4) + iban.slice(0, 4);
  let rem = 0;
  for (const ch of moved) {
    const v = ch >= 'A' && ch <= 'Z' ? String(ch.charCodeAt(0) - 55) : ch;
    for (const d of v) rem = (rem * 10 + Number(d)) % 97;
  }
  return rem === 1;
}

export const isValidBic = (s: string) => /^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$/.test(s.trim().toUpperCase());
export const isValidEmail = (s: string) => /^[^\s@]{1,64}@[^\s@]{1,190}\.[a-z]{2,}$/i.test(s.trim());

export function validatePayout(d: PayoutDetails): string | null {
  if (!d.holderName || d.holderName.trim().length < 3 || d.holderName.length > 120) return 'holderName';
  switch (d.kind) {
    case 'BANK_IBAN':
      return d.iban && isValidIban(d.iban) ? null : 'iban';
    case 'BANK_SWIFT':
      if (!d.bic || !isValidBic(d.bic)) return 'bic';
      if (!d.accountNumber || !/^[A-Z0-9]{5,34}$/i.test(d.accountNumber.replace(/[\s-]/g, ''))) return 'accountNumber';
      return null;
    case 'WISE':
    case 'PAYPAL':
    case 'PAYONEER':
      return d.email && isValidEmail(d.email) ? null : 'email';
  }
}

/** The value that identifies the destination (used for the fingerprint and the mask). */
export function payoutIdentity(d: PayoutDetails): string {
  switch (d.kind) {
    case 'BANK_IBAN':
      return normalizeIban(d.iban!);
    case 'BANK_SWIFT':
      return `${d.bic!.trim().toUpperCase()}:${d.accountNumber!.replace(/[\s-]/g, '').toUpperCase()}`;
    default:
      return d.email!.trim().toLowerCase();
  }
}

export function maskPayout(d: PayoutDetails): string {
  const id = payoutIdentity(d);
  if (d.kind === 'BANK_IBAN') return `${id.slice(0, 4)} •••• ${id.slice(-4)}`;
  if (d.kind === 'BANK_SWIFT') return `${id.split(':')[0]} •••• ${id.slice(-4)}`;
  const [u, dom] = id.split('@');
  return `${u.slice(0, 2)}•••@${dom}`;
}

export function payoutFingerprint(secret: string, d: PayoutDetails): string {
  return createHmac('sha256', secret).update(`payout:${d.kind === 'BANK_SWIFT' || d.kind === 'BANK_IBAN' ? 'bank' : d.kind}:${payoutIdentity(d)}`).digest('hex');
}

// ── sealed storage ─────────────────────────────────────────────────

/** key: 32 bytes. Output: version(1) | iv(12) | tag(16) | ciphertext. */
export function seal(key: Buffer, plaintext: string, aad = 'olfa:payout'): Buffer {
  if (key.length !== 32) throw new Error('seal key must be 32 bytes');
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', key, iv);
  c.setAAD(Buffer.from(aad));
  const ct = Buffer.concat([c.update(plaintext, 'utf8'), c.final()]);
  return Buffer.concat([Buffer.from([1]), iv, c.getAuthTag(), ct]);
}

export function open(key: Buffer, box: Buffer, aad = 'olfa:payout'): string {
  if (box[0] !== 1) throw new Error('unknown box version');
  const d = createDecipheriv('aes-256-gcm', key, box.subarray(1, 13));
  d.setAAD(Buffer.from(aad));
  d.setAuthTag(box.subarray(13, 29));
  return Buffer.concat([d.update(box.subarray(29)), d.final()]).toString('utf8');
}

// ── withdrawal rules ───────────────────────────────────────────────

/** Minimum withdrawal: 50 major units of the currency (e.g. 50 AED = 5000 fils). */
export function minWithdrawalMinor(currency: string, major = 50): number {
  return major * 10 ** currencyExponent(currency);
}

export interface WalletEntryLike {
  amountMinor: number;
  availableAt: Date;
}

/** Pending = earnings still in the hold period; available = can be withdrawn now. */
export function walletBalance(entries: WalletEntryLike[], now: Date): { availableMinor: number; pendingMinor: number } {
  let available = 0;
  let pending = 0;
  for (const e of entries) {
    if (e.availableAt.getTime() <= now.getTime() || e.amountMinor < 0) available += e.amountMinor;
    else pending += e.amountMinor;
  }
  return { availableMinor: available, pendingMinor: pending };
}
