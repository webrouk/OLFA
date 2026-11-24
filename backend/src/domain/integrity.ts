import { normalizeDigits, findPhoneNumbers } from './phone-detect';

/**
 * Counselor integrity: protecting clients and the platform from attempts to
 * move consultations (and their payment) outside OLFA to avoid the 15% fee.
 *
 * Signals come from the mandatory post-consultation questionnaire (direct and
 * indirect questions) and from the consultation chat. No single client can
 * get a counselor banned: a case is opened for HUMAN review only when the
 * evidence is corroborated (several clients, or chat evidence plus a client
 * report). The counselor is notified and can respond before any decision.
 */

/** Questionnaire answers (version 1). Direct and indirect anti-circumvention questions. */
export type YesNoUnsure = 'NO' | 'YES' | 'UNSURE';
export type NextSession = 'BOOKED_IN_APP' | 'PLAN_IN_APP' | 'AGREED_OUTSIDE' | 'NOT_DISCUSSED' | 'NO';
export type NextChannel = 'OLFA' | 'DIRECT' | 'OTHER_APP' | 'UNDECIDED';

export interface ReviewAnswers {
  rating: number; // overall 1–5
  quality: number; // professionalism & respect 1–5
  commitment: number; // punctuality & commitment to the agreed time 1–5
  effectiveness: number; // how useful the session was 1–5
  outcome: number; // how far the goals were reached 1–5
  /** Indirect: "Did you agree on another session?" */
  nextSession: NextSession;
  /** Indirect: "How do you expect to book the next session?" */
  nextChannel: NextChannel;
  /** Direct: "Did the counselor share personal contact details or ask for yours?" */
  contactShared: YesNoUnsure;
  /** Direct: "Were you asked to pay any amount outside OLFA?" */
  offPlatformPayment: YesNoUnsure;
  /** Indirect: "Did the counselor suggest continuing through a clinic, website or social account?" */
  externalChannel: YesNoUnsure;
}

export const QUESTIONNAIRE_VERSION = 1;

export type SignalKind =
  | 'REVIEW_CONTACT_SHARED'
  | 'REVIEW_OFFPLATFORM_PAYMENT'
  | 'REVIEW_NEXT_OUTSIDE'
  | 'REVIEW_DIRECT_BOOKING'
  | 'REVIEW_EXTERNAL_CHANNEL'
  | 'REVIEW_UNSURE'
  | 'CHAT_CONTACT_SHARED'
  | 'REPEAT_DROP';

export const SIGNAL_WEIGHT: Record<SignalKind, number> = {
  REVIEW_OFFPLATFORM_PAYMENT: 8,
  REVIEW_CONTACT_SHARED: 5,
  CHAT_CONTACT_SHARED: 4,
  REVIEW_NEXT_OUTSIDE: 4,
  REVIEW_DIRECT_BOOKING: 3,
  REVIEW_EXTERNAL_CHANNEL: 3,
  REVIEW_UNSURE: 1,
  REPEAT_DROP: 1,
};

/** Signals derived from one questionnaire. */
export function signalsFromReview(a: ReviewAnswers): SignalKind[] {
  const out: SignalKind[] = [];
  if (a.offPlatformPayment === 'YES') out.push('REVIEW_OFFPLATFORM_PAYMENT');
  if (a.contactShared === 'YES') out.push('REVIEW_CONTACT_SHARED');
  if (a.nextSession === 'AGREED_OUTSIDE') out.push('REVIEW_NEXT_OUTSIDE');
  if (a.nextChannel === 'DIRECT' || a.nextChannel === 'OTHER_APP') out.push('REVIEW_DIRECT_BOOKING');
  if (a.externalChannel === 'YES') out.push('REVIEW_EXTERNAL_CHANNEL');
  if ([a.offPlatformPayment, a.contactShared, a.externalChannel].some((x) => x === 'UNSURE')) out.push('REVIEW_UNSURE');
  return out;
}

export function validateAnswers(a: ReviewAnswers): string | null {
  for (const k of ['rating', 'quality', 'commitment', 'effectiveness', 'outcome'] as const) {
    const v = a[k];
    if (!Number.isInteger(v) || v < 1 || v > 5) return `${k} must be 1–5`;
  }
  return null;
}

// ── contact details in chat ────────────────────────────────────────

const EMAIL = /[a-z0-9._%+-]+\s*(?:@|\(at\)|\[at\]| at )\s*[a-z0-9.-]+\s*(?:\.|\(dot\)| dot )\s*[a-z]{2,}/i;
const URL = /\b(?:https?:\/\/|www\.)\S+|\b[a-z0-9-]+\.(?:com|net|org|me|io|co|app|clinic|health|info|ae|sa|eg|qa|kw|om|bh|jo|ma)\b/i;
const HANDLE = /(?:^|\s)@[a-z0-9_.]{3,}/i;
const CHANNELS = /\b(?:whats\s?app|wa\.me|telegram|t\.me|signal|insta(?:gram)?|snap(?:chat)?|tik\s?tok|facebook|messenger|imo|viber|botim|zoom|skype)\b|واتس|واتساب|تلغرام|تيليجرام|انستا|انستغرام|سناب|تيك\s?توك|فيسبوك|ماسنجر|زووم|سكايب|بوتيم/i;

export type ContactKind = 'phone' | 'email' | 'url' | 'handle' | 'channel';

/** What kinds of off-platform contact details a message contains. */
export function detectContactInfo(text: string): ContactKind[] {
  const t = normalizeDigits(text);
  const out: ContactKind[] = [];
  if (findPhoneNumbers(t).length) out.push('phone');
  if (EMAIL.test(t)) out.push('email');
  if (URL.test(t)) out.push('url');
  if (HANDLE.test(t) && !EMAIL.test(t)) out.push('handle');
  if (CHANNELS.test(t)) out.push('channel');
  return out;
}

// ── scoring ────────────────────────────────────────────────────────

export interface Signal {
  kind: SignalKind;
  clientId: string | null; // null for chat-detected signals
  consultationId: string | null;
  createdAt: Date;
}

export interface IntegrityAssessment {
  score: number;
  distinctClients: number;
  level: 'none' | 'watch' | 'review';
  reasons: string[];
}

export const INTEGRITY_POLICY = {
  windowDays: 90,
  watchScore: 6,
  reviewScore: 12,
  minClientsForReview: 2,
} as const;

/**
 * Scores a counselor's recent signals. Each (client, kind) pair counts once
 * so a single client cannot inflate the score by repeating answers; chat
 * evidence counts once per consultation.
 */
export function assessIntegrity(signals: Signal[], now: Date, policy = INTEGRITY_POLICY): IntegrityAssessment {
  const since = now.getTime() - policy.windowDays * 86_400_000;
  const recent = signals.filter((s) => s.createdAt.getTime() >= since);
  const seen = new Set<string>();
  let score = 0;
  const clients = new Set<string>();
  for (const s of recent) {
    const who = s.clientId ?? `chat:${s.consultationId ?? 'x'}`;
    const key = `${who}|${s.kind}`;
    if (seen.has(key)) continue;
    seen.add(key);
    score += SIGNAL_WEIGHT[s.kind];
    if (s.clientId && s.kind !== 'REVIEW_UNSURE' && s.kind !== 'REPEAT_DROP') clients.add(s.clientId);
  }
  const reasons: string[] = [];
  // Corroboration inside one consultation: the chat shows contact details AND
  // the client reports being asked to pay outside OLFA.
  const byConsultation = new Map<string, Set<SignalKind>>();
  for (const s of recent) {
    if (!s.consultationId) continue;
    const set = byConsultation.get(s.consultationId) ?? new Set<SignalKind>();
    set.add(s.kind);
    byConsultation.set(s.consultationId, set);
  }
  const corroborated = [...byConsultation.values()].some((k) => k.has('CHAT_CONTACT_SHARED') && (k.has('REVIEW_OFFPLATFORM_PAYMENT') || k.has('REVIEW_NEXT_OUTSIDE')));
  if (corroborated) reasons.push('chat_and_client_report_agree');
  const enough = score >= policy.reviewScore && clients.size >= policy.minClientsForReview;
  if (enough) reasons.push('several_clients_reported');
  const level = enough || corroborated ? 'review' : score >= policy.watchScore ? 'watch' : 'none';
  return { score, distinctClients: clients.size, level, reasons };
}
