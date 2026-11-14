import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  acceptsOneWay,
  compatibility,
  DEFAULT_WEIGHTS,
  jaccard,
  Member,
  mutuallyCompatible,
  parseWeights,
  rankCandidates,
} from '../../src/domain/matching';
import { dayWindow, tzOffsetMs } from '../../src/domain/quota-period';
import { ageOn, checkOtp, generateOtp, hashOtp, newRefreshToken, profileCompleteness, sha256, toE164 } from '../../src/domain/security';

const base = (id: string, gender: 'MALE' | 'FEMALE', over: Partial<Member['profile']> = {}, prefs: Partial<Member['prefs']> = {}): Member => ({
  profile: {
    id,
    gender,
    age: 30,
    countryCode: 'AE',
    city: 'Dubai',
    maritalStatus: 'NEVER_MARRIED',
    education: 'BACHELOR',
    occupation: 'Engineer',
    interests: ['reading', 'travel'],
    marriageTimeline: 'WITHIN_1_YEAR',
    wantsChildren: true,
    smoking: false,
    ...over,
  },
  prefs: {
    ageMin: 22,
    ageMax: 40,
    sameCountryOnly: false,
    countryCodes: [],
    cities: [],
    maritalStatuses: [],
    educationLevels: [],
    occupations: [],
    wantsChildren: null,
    ...prefs,
  },
});

describe('matching — hard filters', () => {
  const man = base('m', 'MALE');
  const woman = base('w', 'FEMALE', { age: 27 });

  test('opposite genders inside each other\'s ranges are compatible', () => {
    assert.equal(mutuallyCompatible(man, woman), true);
  });
  test('same gender is never shown', () => {
    assert.equal(acceptsOneWay(man, base('m2', 'MALE')), 'same_gender');
  });
  test('filters are MUTUAL: fitting my prefs is not enough', () => {
    const picky = base('w2', 'FEMALE', {}, { ageMin: 35, ageMax: 45 }); // man is 30
    assert.equal(acceptsOneWay(man, picky), null); // he accepts her
    assert.equal(acceptsOneWay(picky, man), 'age'); // she does not accept him
    assert.equal(mutuallyCompatible(man, picky), false);
  });
  test('country: explicit list and same-country-only', () => {
    assert.equal(acceptsOneWay(base('a', 'MALE', {}, { countryCodes: ['SA'] }), woman), 'country');
    assert.equal(acceptsOneWay(base('a', 'MALE', {}, { sameCountryOnly: true }), base('b', 'FEMALE', { countryCode: 'EG' })), 'country');
  });
  test('marital status, education and children preferences', () => {
    assert.equal(acceptsOneWay(base('a', 'MALE', {}, { maritalStatuses: ['NEVER_MARRIED'] }), base('b', 'FEMALE', { maritalStatus: 'DIVORCED' })), 'marital_status');
    assert.equal(acceptsOneWay(base('a', 'MALE', {}, { educationLevels: ['MASTER'] }), woman), 'education');
    assert.equal(acceptsOneWay(base('a', 'MALE', {}, { wantsChildren: true }), base('b', 'FEMALE', { wantsChildren: false })), 'children');
  });
});

describe('matching — score', () => {
  test('identical declared traits score 100', () => {
    const a = base('a', 'MALE');
    const b = base('b', 'FEMALE');
    assert.equal(compatibility(a, b).score, 100);
  });
  test('score is symmetric and within 0..100', () => {
    const a = base('a', 'MALE', { interests: ['reading'], education: 'DOCTORATE', city: 'Abu Dhabi' });
    const b = base('b', 'FEMALE', { interests: ['travel', 'reading', 'cooking'], marriageTimeline: 'WITHIN_2_YEARS' });
    const x = compatibility(a, b).score;
    assert.equal(x, compatibility(b, a).score);
    assert.ok(x >= 0 && x <= 100);
  });
  test('weights change the result and are admin-tunable', () => {
    const a = base('a', 'MALE', { interests: ['reading'] });
    const b = base('b', 'FEMALE', { interests: ['cooking'] });
    const onlyInterests = parseWeights({ version: 2, interests: 100, timeline: 0, location: 0, lifestyle: 0, education: 0, preferenceFit: 0 });
    assert.equal(compatibility(a, b, onlyInterests).score, 0);
    assert.equal(compatibility(a, b, onlyInterests).weightsVersion, 2);
    assert.ok(compatibility(a, b, DEFAULT_WEIGHTS).score > 0);
  });
  test('invalid weights are rejected', () => {
    assert.throws(() => parseWeights({ interests: -1 }));
    assert.throws(() => parseWeights({ interests: 0, timeline: 0, location: 0, lifestyle: 0, education: 0, preferenceFit: 0 }));
  });
  test('jaccard basics', () => {
    assert.equal(jaccard(['a', 'b'], ['b', 'c']), 1 / 3);
    assert.equal(jaccard([], []), 0);
  });
});

describe('matching — ranking', () => {
  const viewer = base('v', 'MALE');
  const pool = [
    base('w1', 'FEMALE', { interests: ['reading', 'travel'] }),
    base('w2', 'FEMALE', { interests: ['cooking'] }),
    base('w3', 'FEMALE', { age: 50 }), // outside viewer's range
    base('w1', 'FEMALE'), // duplicate
    base('m9', 'MALE'), // same gender
    base('w4', 'FEMALE', { interests: ['reading', 'travel'] }),
  ];

  test('excludes incompatible, excluded and duplicate candidates; sorts by score', () => {
    const r = rankCandidates(viewer, pool, { exclude: new Set(['w4']), dayKey: '2026-11-14' });
    assert.deepEqual(r.map((x) => x.member.profile.id), ['w1', 'w2']);
    assert.ok(r[0].result.score >= r[1].result.score);
  });
  test('minScore and limit', () => {
    const r = rankCandidates(viewer, pool, { minScore: 99, limit: 5 });
    assert.ok(r.every((x) => x.result.score >= 99));
  });
  test('tie-break is deterministic per day', () => {
    const ties = [base('t1', 'FEMALE'), base('t2', 'FEMALE'), base('t3', 'FEMALE'), base('t4', 'FEMALE')];
    const a = rankCandidates(viewer, ties, { dayKey: 'd1' }).map((x) => x.member.profile.id);
    const b = rankCandidates(viewer, ties, { dayKey: 'd1' }).map((x) => x.member.profile.id);
    assert.deepEqual(a, b);
  });
});

describe('quota windows (UTC storage, local reset)', () => {
  test('Dubai (UTC+4) day starts at 20:00 UTC the previous day', () => {
    const w = dayWindow(new Date('2026-11-14T03:00:00Z'), 'Asia/Dubai'); // 07:00 local
    assert.equal(w.start.toISOString(), '2026-11-13T20:00:00.000Z');
    assert.equal(w.end.toISOString(), '2026-11-14T20:00:00.000Z');
    assert.equal(w.dayKey, '2026-11-14');
  });
  test('just before local midnight belongs to the same day', () => {
    const w = dayWindow(new Date('2026-11-14T19:59:59Z'), 'Asia/Dubai');
    assert.equal(w.dayKey, '2026-11-14');
  });
  test('DST day in London is 23 hours long', () => {
    const w = dayWindow(new Date('2026-03-29T12:00:00Z'), 'Europe/London');
    assert.equal((w.end.getTime() - w.start.getTime()) / 3600000, 23);
  });
  test('invalid timezone falls back to UTC', () => {
    const w = dayWindow(new Date('2026-11-14T10:00:00Z'), 'Mars/Olympus');
    assert.equal(w.start.toISOString(), '2026-11-14T00:00:00.000Z');
  });
  test('offset helper', () => {
    assert.equal(tzOffsetMs(Date.UTC(2026, 0, 1), 'Asia/Riyadh'), 3 * 3600000);
  });
});

describe('security helpers', () => {
  test('OTP is 6 digits and only its HMAC is comparable', () => {
    const code = generateOtp();
    assert.match(code, /^\d{6}$/);
    const h = hashOtp('secret', '+971501234567', code);
    assert.equal(h.length, 64);
    assert.notEqual(h, hashOtp('secret', '+971501234568', code), 'bound to the phone number');
  });
  test('OTP state machine', () => {
    const now = new Date('2026-11-14T00:00:00Z');
    const good = hashOtp('s', '+1', '123456');
    const c = { codeHash: good, attempts: 0, maxAttempts: 5, expiresAt: new Date(now.getTime() + 300000), consumedAt: null };
    assert.equal(checkOtp(c, good, now), 'ok');
    assert.equal(checkOtp(c, hashOtp('s', '+1', '000000'), now), 'mismatch');
    assert.equal(checkOtp({ ...c, attempts: 5 }, good, now), 'locked');
    assert.equal(checkOtp(c, good, new Date(now.getTime() + 300000)), 'expired');
    assert.equal(checkOtp({ ...c, consumedAt: now }, good, now), 'consumed');
  });
  test('refresh tokens are random and stored hashed', () => {
    const a = newRefreshToken();
    const b = newRefreshToken();
    assert.notEqual(a.token, b.token);
    assert.equal(a.hash, sha256(a.token));
  });
  test('E.164 normalisation', () => {
    assert.equal(toE164('+971', '050 123 4567'), '+971501234567');
    assert.equal(toE164('+966', '0551234567'), '+966551234567');
    assert.equal(toE164('+971', '971501234567'), '+971501234567');
    assert.equal(toE164('+971', '12'), null);
  });
  test('age calculation around birthdays', () => {
    assert.equal(ageOn(new Date('2008-11-15'), new Date('2026-11-14')), 17);
    assert.equal(ageOn(new Date('2008-11-14'), new Date('2026-11-14')), 18);
  });
  test('profile completeness is bounded', () => {
    assert.equal(profileCompleteness({ bio: 'x'.repeat(100), interests: 9, approvedPhotos: 6, occupation: 'a', hasLifestyle: true }), 100);
    assert.equal(profileCompleteness({ bio: '', interests: 0, approvedPhotos: 0, occupation: '', hasLifestyle: false }), 40);
  });
});
