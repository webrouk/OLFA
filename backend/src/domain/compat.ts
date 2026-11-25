/**
 * In-chat compatibility questions: scoring.
 *
 * Each person answers the questions for their gender. Answers are compared per
 * TOPIC (a men's and a women's version of a question share a topic and use the
 * same value scale). Every topic has a weight; the score is the weighted mean
 * of per-topic agreement, 0–100. The result only exists once BOTH people have
 * answered everything (also enforced by the database).
 */

export type CompatDomain = 'FINANCE' | 'FUTURE' | 'FAMILY_ROLES' | 'LIFESTYLE' | 'MARRIAGE';
export const COMPAT_DOMAINS: readonly CompatDomain[] = ['FINANCE', 'FUTURE', 'FAMILY_ROLES', 'LIFESTYLE', 'MARRIAGE'];

export interface CompatOption {
  key: string;
  value: number; // whole number 0..10
}

export interface CompatQuestionDef {
  id: string;
  topic: string;
  domain: CompatDomain;
  weight: number; // 1..10
  scoring: 'SCALE' | 'MATCH';
  options: CompatOption[];
}

export interface CompatDomainScore {
  domain: CompatDomain;
  score: number; // 0..100
  topics: number;
}

export interface CompatOutcome {
  score: number; // 0..100
  domains: CompatDomainScore[];
  /** Topics where both answered the same way (count). */
  agreed: number;
  /** Topics worth talking about: agreement below 50 %, strongest gaps first (topic keys). */
  talkAbout: string[];
}

/** Agreement on one topic, 0..1. SCALE: closeness on the shared value range; MATCH: same value. */
export function topicAgreement(scoring: 'SCALE' | 'MATCH', a: number, b: number, min: number, max: number): number {
  if (scoring === 'MATCH' || max <= min) return a === b ? 1 : 0;
  return 1 - Math.abs(a - b) / (max - min);
}

/**
 * Scores two people's answers. `mine`/`theirs` map questionId → optionKey for
 * each person's own question set. Topics answered by only one side are skipped.
 */
export function scoreCompat(
  questions: CompatQuestionDef[],
  answersA: Record<string, string>,
  answersB: Record<string, string>,
): CompatOutcome {
  const byId = new Map(questions.map((q) => [q.id, q]));
  type Side = { q: CompatQuestionDef; value: number };
  const sideOf = (answers: Record<string, string>) => {
    const out = new Map<string, Side>();
    for (const [qid, key] of Object.entries(answers)) {
      const q = byId.get(qid);
      const o = q?.options.find((x) => x.key === key);
      if (q && o) out.set(q.topic, { q, value: o.value });
    }
    return out;
  };
  const a = sideOf(answersA);
  const b = sideOf(answersB);
  const perDomain = new Map<CompatDomain, { w: number; s: number; n: number }>();
  const gaps: { topic: string; agreement: number; weight: number }[] = [];
  let totalW = 0;
  let totalS = 0;
  let agreed = 0;
  for (const [topic, sa] of a) {
    const sb = b.get(topic);
    if (!sb) continue;
    const values = [...sa.q.options, ...sb.q.options].map((o) => o.value);
    const min = Math.min(...values);
    const max = Math.max(...values);
    // a pair's weight is the mean of both versions' weights
    const weight = (sa.q.weight + sb.q.weight) / 2;
    const scoring = sa.q.scoring === 'MATCH' || sb.q.scoring === 'MATCH' ? 'MATCH' : 'SCALE';
    const agreement = topicAgreement(scoring, sa.value, sb.value, min, max);
    if (sa.value === sb.value) agreed++;
    if (agreement < 0.5) gaps.push({ topic, agreement, weight });
    totalW += weight;
    totalS += weight * agreement;
    const d = perDomain.get(sa.q.domain) ?? { w: 0, s: 0, n: 0 };
    d.w += weight;
    d.s += weight * agreement;
    d.n += 1;
    perDomain.set(sa.q.domain, d);
  }
  const pct = (s: number, w: number) => (w > 0 ? Math.round((100 * s) / w) : 0);
  return {
    score: pct(totalS, totalW),
    domains: COMPAT_DOMAINS.filter((d) => perDomain.has(d)).map((d) => {
      const x = perDomain.get(d)!;
      return { domain: d, score: pct(x.s, x.w), topics: x.n };
    }),
    agreed,
    talkAbout: gaps.sort((x, y) => x.agreement - y.agreement || y.weight - x.weight).slice(0, 3).map((g) => g.topic),
  };
}

/** Which question set a person answers: theirs by gender, plus the shared ones (picked at start). */
export function pickQuestionSets(active: { id: string; audience: 'ALL' | 'MALE' | 'FEMALE'; sortOrder: number }[]) {
  const sorted = [...active].sort((x, y) => x.sortOrder - y.sortOrder);
  return {
    male: sorted.filter((q) => q.audience !== 'FEMALE').map((q) => q.id),
    female: sorted.filter((q) => q.audience !== 'MALE').map((q) => q.id),
  };
}
