import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';

/** OTP policy (values overridable through system_settings). */
export const OTP_POLICY = {
  length: 6,
  ttlSeconds: 300,
  resendCooldownSeconds: 45,
  maxVerifyAttempts: 5,
  perPhoneWindowSeconds: 600,
  perPhoneMaxRequests: 3,
  perIpWindowSeconds: 3600,
  perIpMaxRequests: 10,
} as const;

export function generateOtp(length: number = OTP_POLICY.length): string {
  let s = '';
  for (let i = 0; i < length; i++) s += String(randomInt(0, 10));
  return s;
}

/** OTPs are stored only as HMAC(secret, phone:code). */
export function hashOtp(secret: string, phoneE164: string, code: string): string {
  return createHmac('sha256', secret).update(`${phoneE164}:${code}`).digest('hex');
}

export function safeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}

export type OtpCheck = 'ok' | 'expired' | 'consumed' | 'locked' | 'mismatch';

export interface OtpChallengeState {
  codeHash: string;
  attempts: number;
  maxAttempts: number;
  expiresAt: Date;
  consumedAt: Date | null;
}

export function checkOtp(c: OtpChallengeState, providedHash: string, now: Date): OtpCheck {
  if (c.consumedAt) return 'consumed';
  if (c.attempts >= c.maxAttempts) return 'locked';
  if (now.getTime() >= c.expiresAt.getTime()) return 'expired';
  return safeEqualHex(c.codeHash, providedHash) ? 'ok' : 'mismatch';
}

/** Opaque refresh token (returned once) and its storage hash. */
export function newRefreshToken(): { token: string; hash: string } {
  const token = randomBytes(32).toString('base64url');
  return { token, hash: sha256(token) };
}

export function sha256(s: string): string {
  return createHash('sha256').update(s).digest('hex');
}

/** Privacy-preserving IP fingerprint for rate limits and logs. */
export function hashIp(pepper: string, ip: string): string {
  return createHmac('sha256', pepper).update(ip).digest('hex');
}

/** Minimal E.164 normaliser: dial code + national number (leading 0 trunk prefix removed). */
export function toE164(dialCode: string, national: string): string | null {
  const cc = dialCode.replace(/\D/g, '');
  let n = national.replace(/\D/g, '');
  if (n.startsWith(cc) && n.length > cc.length + 6) n = n.slice(cc.length); // pasted with country code
  n = n.replace(/^0+/, '');
  const e = `+${cc}${n}`;
  return /^\+[1-9]\d{6,14}$/.test(e) ? e : null;
}

export function ageOn(birth: Date, now: Date): number {
  let a = now.getUTCFullYear() - birth.getUTCFullYear();
  const m = now.getUTCMonth() - birth.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < birth.getUTCDate())) a--;
  return a;
}

/** Profile completeness 0–100 (drives the UI meter and ranking hygiene). */
export function profileCompleteness(p: {
  bio: string;
  interests: number;
  approvedPhotos: number;
  occupation: string;
  hasLifestyle: boolean;
}): number {
  let s = 40; // required fields are enforced at creation
  s += Math.min(p.approvedPhotos, 4) * 7.5; // up to 30
  s += Math.min(p.interests, 5) * 2; // up to 10
  if (p.bio.trim().length >= 80) s += 10;
  if (p.occupation.trim()) s += 5;
  if (p.hasLifestyle) s += 5;
  return Math.min(100, Math.round(s));
}
