import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pickQuestionSets, scoreCompat, topicAgreement, type CompatQuestionDef } from '../../src/domain/compat';

const opts = (n: number) => Array.from({ length: n }, (_, v) => ({ key: `o${v}`, value: v }));
const Q: CompatQuestionDef[] = [
  { id: 'budget', topic: 'fin_budget', domain: 'FINANCE', weight: 4, scoring: 'SCALE', options: opts(5) },
  { id: 'work_m', topic: 'fut_work', domain: 'FUTURE', weight: 5, scoring: 'SCALE', options: opts(4) },
  { id: 'work_f', topic: 'fut_work', domain: 'FUTURE', weight: 5, scoring: 'SCALE', options: opts(4) },
  { id: 'dec', topic: 'fam_decisions', domain: 'FAMILY_ROLES', weight: 4, scoring: 'MATCH', options: opts(2) },
];

test('topic agreement: scale distance and exact match', () => {
  assert.equal(topicAgreement('SCALE', 0, 4, 0, 4), 0);
  assert.equal(topicAgreement('SCALE', 2, 2, 0, 4), 1);
  assert.equal(topicAgreement('SCALE', 1, 2, 0, 4), 0.75);
  assert.equal(topicAgreement('MATCH', 1, 2, 0, 4), 0);
});

test('identical answers → 100; men and women versions compared by topic', () => {
  const r = scoreCompat(Q, { budget: 'o1', work_m: 'o2', dec: 'o1' }, { budget: 'o1', work_f: 'o2', dec: 'o1' });
  assert.equal(r.score, 100);
  assert.equal(r.agreed, 3);
  assert.deepEqual(r.domains.map((d) => d.domain), ['FINANCE', 'FUTURE', 'FAMILY_ROLES']);
  assert.deepEqual(r.talkAbout, []);
});

test('weighted mean and talking points', () => {
  // budget 0 vs 4 → 0 (w4); work 3 vs 3 → 1 (w5); decisions differ → 0 (w4) ⇒ 5/13 = 38 %
  const r = scoreCompat(Q, { budget: 'o0', work_m: 'o3', dec: 'o0' }, { budget: 'o4', work_f: 'o3', dec: 'o1' });
  assert.equal(r.score, 38);
  assert.deepEqual(r.talkAbout.sort(), ['fam_decisions', 'fin_budget']);
  assert.equal(r.domains.find((d) => d.domain === 'FUTURE')!.score, 100);
});

test('topics only one side answered are skipped; unknown option keys ignored', () => {
  const r = scoreCompat(Q, { budget: 'o2', dec: 'zz' }, { budget: 'o2', work_f: 'o0' });
  assert.equal(r.score, 100);
  assert.equal(r.domains.length, 1);
});

test('question sets per gender keep the bank order', () => {
  const s = pickQuestionSets([
    { id: 'b', audience: 'ALL', sortOrder: 20 },
    { id: 'm', audience: 'MALE', sortOrder: 10 },
    { id: 'f', audience: 'FEMALE', sortOrder: 11 },
    { id: 'a', audience: 'ALL', sortOrder: 0 },
  ]);
  assert.deepEqual(s.male, ['a', 'm', 'b']);
  assert.deepEqual(s.female, ['a', 'f', 'b']);
});
