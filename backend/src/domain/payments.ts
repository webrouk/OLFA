import { createHmac, timingSafeEqual } from 'node:crypto';

/** Platform commission in minor units (half-up), and the counselor's share. */
export function splitFee(priceMinor: number, feePercent: number): { platformMinor: number; counselorMinor: number } {
  if (!Number.isInteger(priceMinor) || priceMinor <= 0) throw new Error('price must be a positive integer of minor units');
  if (feePercent < 0 || feePercent > 100) throw new Error('fee percent out of range');
  const platformMinor = Math.floor((priceMinor * feePercent + 50) / 100);
  return { platformMinor, counselorMinor: priceMinor - platformMinor };
}

/**
 * Stripe webhook signature (`Stripe-Signature: t=…,v1=…`): HMAC-SHA256 of
 * "<t>.<raw body>" with the endpoint secret, constant-time compared, with a
 * replay window.
 */
export function verifyStripeSignature(rawBody: string, header: string | undefined, secret: string, nowSec: number, toleranceSec = 300): boolean {
  if (!header || !secret) return false;
  const parts = Object.fromEntries(header.split(',').map((kv) => kv.split('=', 2) as [string, string]));
  const t = Number(parts.t);
  const sigs = header.split(',').filter((kv) => kv.startsWith('v1=')).map((kv) => kv.slice(3));
  if (!Number.isFinite(t) || !sigs.length || Math.abs(nowSec - t) > toleranceSec) return false;
  const expected = createHmac('sha256', secret).update(`${t}.${rawBody}`).digest();
  return sigs.some((s) => {
    const got = Buffer.from(s, 'hex');
    return got.length === expected.length && timingSafeEqual(got, expected);
  });
}

/** ISO-4217 exponents for the currencies counselors can price in. */
const EXPONENT: Record<string, number> = { AED: 2, SAR: 2, QAR: 2, OMR: 3, KWD: 3, BHD: 3, JOD: 3, EGP: 2, MAD: 2, USD: 2, EUR: 2, GBP: 2 };
export const currencyExponent = (c: string) => {
  const e = EXPONENT[c];
  if (e == null) throw new Error(`unsupported currency ${c}`);
  return e;
};
export const SUPPORTED_CURRENCIES = Object.keys(EXPONENT);
