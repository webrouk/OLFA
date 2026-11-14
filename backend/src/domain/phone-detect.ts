/**
 * Detects phone numbers in chat text so both people get a safety note
 * ("get to know this person well before sharing contact details").
 * Handles Arabic-Indic (٠-٩) and Persian (۰-۹) digits, spaces, dots,
 * dashes, brackets and a leading + or 00. A run of 8–15 digits counts;
 * dates, times, prices and short codes do not.
 */
const DIGIT_MAP: Record<string, string> = {};
'٠١٢٣٤٥٦٧٨٩'.split('').forEach((d, i) => (DIGIT_MAP[d] = String(i)));
'۰۱۲۳۴۵۶۷۸۹'.split('').forEach((d, i) => (DIGIT_MAP[d] = String(i)));

export function normalizeDigits(s: string): string {
  return s.replace(/[٠-٩۰-۹]/g, (d) => DIGIT_MAP[d] ?? d);
}

// digits with common separators between them (no letters)
const CANDIDATE = /(?:\+|00)?\(?\d(?:[\s\-.()‏‎]{0,2}\d){6,17}/g;

export function findPhoneNumbers(text: string): string[] {
  const t = normalizeDigits(text);
  const out: string[] = [];
  for (const m of t.matchAll(CANDIDATE)) {
    const raw = m[0];
    const digits = raw.replace(/\D/g, '');
    if (digits.length < 8 || digits.length > 15) continue;
    // dates like 2026-11-14 / 14.11.2026 and times are not phone numbers
    if (/^\d{4}[-./]\d{1,2}[-./]\d{1,2}$/.test(raw.trim()) || /^\d{1,2}[-./]\d{1,2}[-./]\d{2,4}$/.test(raw.trim())) continue;
    // a run of one repeated digit (e.g. 00000000) is not a number someone shares
    if (/^(\d)\1+$/.test(digits)) continue;
    out.push(digits);
  }
  return out;
}

export function containsPhoneNumber(text: string): boolean {
  return findPhoneNumbers(text).length > 0;
}
