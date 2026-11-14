/**
 * OLFA matching engine — pure, framework-free, deterministic.
 *
 * 1. Mutual hard filters (both users must fit each other's base preferences).
 * 2. Compatibility score 0–100 from admin-tunable weights.
 * 3. Ranking with a deterministic daily tie-break (fair rotation).
 *
 * Deliberately NOT used: religion, ethnicity, appearance, income, popularity
 * or any inferred trait. Only what users declared about themselves and what
 * they asked for in a partner.
 */

export type Gender = 'MALE' | 'FEMALE';
export type MaritalStatus = 'NEVER_MARRIED' | 'DIVORCED' | 'WIDOWED';
export type Education = 'HIGH_SCHOOL' | 'DIPLOMA' | 'BACHELOR' | 'MASTER' | 'DOCTORATE';
export type Timeline = 'WITHIN_6_MONTHS' | 'WITHIN_1_YEAR' | 'WITHIN_2_YEARS' | 'NOT_SURE';

export interface MatchProfile {
  id: string;
  gender: Gender;
  age: number;
  countryCode: string;
  city: string;
  maritalStatus: MaritalStatus;
  education: Education;
  occupation: string;
  interests: string[];
  marriageTimeline: Timeline;
  hasChildren?: boolean | null;
  wantsChildren?: boolean | null;
  smoking?: boolean | null;
  willingToRelocate?: boolean | null;
}

export interface MatchPreferences {
  ageMin: number;
  ageMax: number;
  sameCountryOnly: boolean;
  countryCodes: string[]; // empty = any
  cities: string[]; // soft preference
  maritalStatuses: MaritalStatus[]; // empty = any
  educationLevels: Education[]; // empty = any
  occupations: string[]; // soft preference
  wantsChildren?: boolean | null; // true = partner must not say "no children"
}

export interface Member {
  profile: MatchProfile;
  prefs: MatchPreferences;
}

export interface Weights {
  version: number;
  interests: number;
  timeline: number;
  location: number;
  lifestyle: number;
  education: number;
  preferenceFit: number;
}

export const DEFAULT_WEIGHTS: Weights = {
  version: 1,
  interests: 30,
  timeline: 20,
  location: 15,
  lifestyle: 15,
  education: 10,
  preferenceFit: 10,
};

export type HardFilterReason =
  | 'same_gender'
  | 'age'
  | 'country'
  | 'marital_status'
  | 'education'
  | 'children';

const EDU_ORDER: Education[] = ['HIGH_SCHOOL', 'DIPLOMA', 'BACHELOR', 'MASTER', 'DOCTORATE'];
const TIMELINE_ORDER: Timeline[] = ['WITHIN_6_MONTHS', 'WITHIN_1_YEAR', 'WITHIN_2_YEARS'];

/** Does `other` satisfy `viewer`'s hard preferences? Returns the failing rule or null. */
export function acceptsOneWay(viewer: Member, other: Member): HardFilterReason | null {
  const p = viewer.prefs;
  const o = other.profile;
  if (o.gender === viewer.profile.gender) return 'same_gender';
  if (o.age < p.ageMin || o.age > p.ageMax) return 'age';
  if (p.sameCountryOnly && o.countryCode !== viewer.profile.countryCode) return 'country';
  if (p.countryCodes.length > 0 && !p.countryCodes.includes(o.countryCode)) return 'country';
  if (p.maritalStatuses.length > 0 && !p.maritalStatuses.includes(o.maritalStatus)) return 'marital_status';
  if (p.educationLevels.length > 0 && !p.educationLevels.includes(o.education)) return 'education';
  if (p.wantsChildren === true && o.wantsChildren === false) return 'children';
  return null;
}

/** Mutual hard filter: both directions must pass. */
export function mutuallyCompatible(a: Member, b: Member): boolean {
  return acceptsOneWay(a, b) === null && acceptsOneWay(b, a) === null;
}

const clamp01 = (x: number) => Math.max(0, Math.min(1, x));
const norm = (s: string) => s.trim().toLocaleLowerCase();

export function jaccard(a: string[], b: string[]): number {
  const A = new Set(a);
  const B = new Set(b);
  if (A.size === 0 && B.size === 0) return 0;
  let inter = 0;
  for (const x of A) if (B.has(x)) inter++;
  return inter / (A.size + B.size - inter);
}

function timelineScore(a: Timeline, b: Timeline): number {
  if (a === 'NOT_SURE' || b === 'NOT_SURE') return 0.5;
  const d = Math.abs(TIMELINE_ORDER.indexOf(a) - TIMELINE_ORDER.indexOf(b));
  return 1 - d / 2;
}

function locationScore(a: MatchProfile, b: MatchProfile): number {
  if (a.countryCode === b.countryCode && norm(a.city) === norm(b.city)) return 1;
  if (a.countryCode === b.countryCode) return 0.6;
  if (a.willingToRelocate || b.willingToRelocate) return 0.4;
  return 0;
}

function lifestyleScore(a: MatchProfile, b: MatchProfile): number {
  const parts: number[] = [];
  if (a.smoking != null && b.smoking != null) parts.push(a.smoking === b.smoking ? 1 : 0);
  if (a.wantsChildren != null && b.wantsChildren != null) parts.push(a.wantsChildren === b.wantsChildren ? 1 : 0);
  return parts.length === 0 ? 0.5 : parts.reduce((s, x) => s + x, 0) / parts.length;
}

function educationScore(a: Education, b: Education): number {
  return 1 - Math.abs(EDU_ORDER.indexOf(a) - EDU_ORDER.indexOf(b)) / (EDU_ORDER.length - 1);
}

/** Soft preferences (cities, occupations) — how well each fits the other's wishes. */
function softFit(viewer: Member, other: Member): number {
  const scores: number[] = [];
  if (viewer.prefs.cities.length > 0) {
    scores.push(viewer.prefs.cities.map(norm).includes(norm(other.profile.city)) ? 1 : 0);
  }
  if (viewer.prefs.occupations.length > 0) {
    const occ = norm(other.profile.occupation);
    scores.push(viewer.prefs.occupations.some((x) => occ.includes(norm(x))) ? 1 : 0);
  }
  return scores.length === 0 ? 1 : scores.reduce((s, x) => s + x, 0) / scores.length;
}

export interface ScoreBreakdown {
  interests: number;
  timeline: number;
  location: number;
  lifestyle: number;
  education: number;
  preferenceFit: number;
}

export interface ScoreResult {
  score: number; // 0..100 integer
  breakdown: ScoreBreakdown; // each 0..1, explainable to admins
  weightsVersion: number;
}

/** Symmetric compatibility score. */
export function compatibility(a: Member, b: Member, w: Weights = DEFAULT_WEIGHTS): ScoreResult {
  const breakdown: ScoreBreakdown = {
    interests: clamp01(jaccard(a.profile.interests, b.profile.interests)),
    timeline: clamp01(timelineScore(a.profile.marriageTimeline, b.profile.marriageTimeline)),
    location: clamp01(locationScore(a.profile, b.profile)),
    lifestyle: clamp01(lifestyleScore(a.profile, b.profile)),
    education: clamp01(educationScore(a.profile.education, b.profile.education)),
    preferenceFit: clamp01((softFit(a, b) + softFit(b, a)) / 2),
  };
  const keys = Object.keys(breakdown) as (keyof ScoreBreakdown)[];
  const totalW = keys.reduce((s, k) => s + Math.max(0, w[k]), 0);
  const raw = totalW === 0 ? 0 : keys.reduce((s, k) => s + Math.max(0, w[k]) * breakdown[k], 0) / totalW;
  return { score: Math.round(raw * 100), breakdown, weightsVersion: w.version };
}

/** FNV-1a — stable, fast tie-break hash. */
function fnv1a(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h;
}

export interface RankOptions {
  weights?: Weights;
  exclude?: Set<string>; // blocked, already liked/passed, already shown today…
  minScore?: number; // optional paid filter
  dayKey?: string; // e.g. "2026-11-14" — rotates equal-score ordering daily
  limit?: number;
}

export interface Ranked {
  member: Member;
  result: ScoreResult;
}

/** Hard-filter, score, rank and de-duplicate candidates for a viewer. */
export function rankCandidates(viewer: Member, candidates: Member[], opts: RankOptions = {}): Ranked[] {
  const w = opts.weights ?? DEFAULT_WEIGHTS;
  const seen = new Set<string>(opts.exclude ?? []);
  seen.add(viewer.profile.id);
  const out: Ranked[] = [];
  for (const c of candidates) {
    if (seen.has(c.profile.id)) continue;
    seen.add(c.profile.id); // de-duplicate
    if (!mutuallyCompatible(viewer, c)) continue;
    const result = compatibility(viewer, c, w);
    if (opts.minScore != null && result.score < opts.minScore) continue;
    out.push({ member: c, result });
  }
  const day = opts.dayKey ?? '';
  out.sort(
    (x, y) =>
      y.result.score - x.result.score ||
      fnv1a(`${day}:${viewer.profile.id}:${x.member.profile.id}`) - fnv1a(`${day}:${viewer.profile.id}:${y.member.profile.id}`),
  );
  return opts.limit != null ? out.slice(0, opts.limit) : out;
}

/** Validates admin-provided weights (non-negative, at least one positive). */
export function parseWeights(input: unknown): Weights {
  const w = { ...DEFAULT_WEIGHTS, ...(typeof input === 'object' && input !== null ? (input as Partial<Weights>) : {}) };
  const keys: (keyof Omit<Weights, 'version'>)[] = ['interests', 'timeline', 'location', 'lifestyle', 'education', 'preferenceFit'];
  for (const k of keys) {
    if (typeof w[k] !== 'number' || !Number.isFinite(w[k]) || w[k] < 0 || w[k] > 100) throw new Error(`invalid weight: ${k}`);
  }
  if (keys.every((k) => w[k] === 0)) throw new Error('at least one weight must be positive');
  if (!Number.isInteger(w.version) || w.version < 1) throw new Error('invalid weights version');
  return w;
}
