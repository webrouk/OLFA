import { strict as assert } from 'node:assert';
import { randomBytes } from 'node:crypto';
import { test } from 'node:test';
import { assessIntegrity, detectContactInfo, ReviewAnswers, Signal, signalsFromReview, validateAnswers } from '../../src/domain/integrity';
import { isValidBic, isValidIban, maskPayout, minWithdrawalMinor, open, payoutFingerprint, seal, validatePayout, walletBalance } from '../../src/domain/payout';
import { splitFee } from '../../src/domain/payments';

const NOW = new Date('2026-11-14T12:00:00Z');
const day = 86_400_000;

const clean: ReviewAnswers = {
  rating: 5, quality: 5, commitment: 5, effectiveness: 4, outcome: 4,
  nextSession: 'BOOKED_IN_APP', nextChannel: 'OLFA', contactShared: 'NO', offPlatformPayment: 'NO', externalChannel: 'NO',
};

test('questionnaire: clean answers produce no signals', () => {
  assert.deepEqual(signalsFromReview(clean), []);
  assert.equal(validateAnswers(clean), null);
  assert.match(validateAnswers({ ...clean, outcome: 0 }) ?? '', /outcome/);
});

test('questionnaire: direct and indirect answers map to signals', () => {
  const s = signalsFromReview({ ...clean, offPlatformPayment: 'YES', nextSession: 'AGREED_OUTSIDE', nextChannel: 'DIRECT', externalChannel: 'UNSURE' });
  assert.deepEqual(s.sort(), ['REVIEW_DIRECT_BOOKING', 'REVIEW_NEXT_OUTSIDE', 'REVIEW_OFFPLATFORM_PAYMENT', 'REVIEW_UNSURE'].sort());
});

test('chat: contact details in Arabic and English are detected', () => {
  assert.deepEqual(detectContactInfo('كلمني واتساب ٠٥٠١٢٣٤٥٦٧'), ['phone', 'channel']);
  assert.deepEqual(detectContactInfo('email me: dr.huda@clinic.ae'), ['email', 'url']);
  assert.deepEqual(detectContactInfo('follow me on insta @dr_huda'), ['handle', 'channel']);
  assert.deepEqual(detectContactInfo('www.huda-clinic.com'), ['url']);
  assert.deepEqual(detectContactInfo('نلتقي غدًا الساعة 7 مساءً إن شاء الله'), []);
  assert.deepEqual(detectContactInfo('Session 2 of 4 — 45 minutes'), []);
});

const sig = (kind: Signal['kind'], clientId: string | null, consultationId: string | null, ago = 1): Signal => ({ kind, clientId, consultationId, createdAt: new Date(NOW.getTime() - ago * day) });

test('integrity: one client alone never triggers a review, however often they report', () => {
  const s = [sig('REVIEW_OFFPLATFORM_PAYMENT', 'c1', 'k1'), sig('REVIEW_OFFPLATFORM_PAYMENT', 'c1', 'k2'), sig('REVIEW_CONTACT_SHARED', 'c1', 'k2'), sig('REVIEW_NEXT_OUTSIDE', 'c1', 'k3')];
  const a = assessIntegrity(s, NOW);
  assert.equal(a.score, 17, 'each (client, kind) counts once');
  assert.equal(a.distinctClients, 1);
  assert.equal(a.level, 'watch');
});

test('integrity: several clients reporting opens a human review', () => {
  const s = [sig('REVIEW_OFFPLATFORM_PAYMENT', 'c1', 'k1'), sig('REVIEW_CONTACT_SHARED', 'c2', 'k2')];
  const a = assessIntegrity(s, NOW);
  assert.equal(a.level, 'review');
  assert.deepEqual(a.reasons, ['several_clients_reported']);
});

test('integrity: chat evidence corroborated by the same client opens a review', () => {
  const a = assessIntegrity([sig('CHAT_CONTACT_SHARED', null, 'k1'), sig('REVIEW_NEXT_OUTSIDE', 'c1', 'k1')], NOW);
  assert.equal(a.level, 'review');
  assert.deepEqual(a.reasons, ['chat_and_client_report_agree']);
});

test('integrity: old signals age out of the 90-day window', () => {
  const a = assessIntegrity([sig('REVIEW_OFFPLATFORM_PAYMENT', 'c1', 'k1', 120), sig('REVIEW_CONTACT_SHARED', 'c2', 'k2', 100)], NOW);
  assert.deepEqual([a.score, a.level], [0, 'none']);
});

test('commission: 15% to OLFA, the rest to the counselor, exact to the minor unit', () => {
  assert.deepEqual(splitFee(28000, 15), { platformMinor: 4200, counselorMinor: 23800 });
  assert.deepEqual(splitFee(12345, 15), { platformMinor: 1852, counselorMinor: 10493 });
  const { platformMinor, counselorMinor } = splitFee(999, 15);
  assert.equal(platformMinor + counselorMinor, 999);
});

test('payout: IBAN and BIC validation', () => {
  assert.equal(isValidIban('AE07 0331 2345 6789 0123 456'), true);
  assert.equal(isValidIban('SA03 8000 0000 6080 1016 7519'), true);
  assert.equal(isValidIban('GB82 WEST 1234 5698 7654 32'), true);
  assert.equal(isValidIban('AE07 0331 2345 6789 0123 457'), false, 'check digits');
  assert.equal(isValidIban('AE07 0331 2345 6789 0123 45'), false, 'length');
  assert.equal(isValidBic('NBADAEAA'), true);
  assert.equal(isValidBic('NBADAEAAXXX'), true);
  assert.equal(isValidBic('NBAD-AE'), false);
});

test('payout: validation, masking, fingerprint', () => {
  const d = { kind: 'BANK_IBAN' as const, holderName: 'Huda Al Mansoori', iban: 'AE07 0331 2345 6789 0123 456' };
  assert.equal(validatePayout(d), null);
  assert.equal(maskPayout(d), 'AE07 •••• 3456');
  assert.equal(validatePayout({ kind: 'PAYPAL', holderName: 'Huda', email: 'not-an-email' }), 'email');
  assert.equal(maskPayout({ kind: 'WISE', holderName: 'Huda', email: 'Huda@Example.com' }), 'hu•••@example.com');
  const f1 = payoutFingerprint('s'.repeat(32), d);
  const f2 = payoutFingerprint('s'.repeat(32), { ...d, iban: 'ae070331234567890123456' });
  assert.equal(f1, f2, 'formatting does not change the fingerprint');
});

test('payout: details are sealed (AES-256-GCM) and tamper-evident', () => {
  const key = randomBytes(32);
  const box = seal(key, JSON.stringify({ iban: 'AE070331234567890123456' }));
  assert.ok(!box.toString('latin1').includes('AE07'));
  assert.equal(JSON.parse(open(key, box)).iban, 'AE070331234567890123456');
  box[box.length - 1] ^= 1;
  assert.throws(() => open(key, box));
  assert.throws(() => open(randomBytes(32), seal(key, 'x')));
});

test('wallet: hold period, available balance and minimums', () => {
  const b = walletBalance([
    { amountMinor: 23800, availableAt: new Date(NOW.getTime() - day) },
    { amountMinor: 10200, availableAt: new Date(NOW.getTime() + 3 * day) },
    { amountMinor: -20000, availableAt: NOW },
  ], NOW);
  assert.deepEqual(b, { availableMinor: 3800, pendingMinor: 10200 });
  assert.equal(minWithdrawalMinor('AED'), 5000);
  assert.equal(minWithdrawalMinor('KWD'), 50000);
});

import { religionAccepted } from '../../src/domain/matching';
test('religion filter: religions, sects narrowing their own religion, undisclosed', () => {
  assert.equal(religionAccepted([], [], null, null), true, 'no filter');
  assert.equal(religionAccepted(['islam'], [], 'islam', 'shia'), true);
  assert.equal(religionAccepted(['islam'], [], 'undisclosed', null), false);
  assert.equal(religionAccepted(['islam'], [], null, null), false);
  assert.equal(religionAccepted(['islam', 'christianity'], ['islam.sunni'], 'islam', 'shia'), false);
  assert.equal(religionAccepted(['islam', 'christianity'], ['islam.sunni'], 'islam', 'sunni'), true);
  assert.equal(religionAccepted(['islam', 'christianity'], ['islam.sunni'], 'christianity', 'catholic'), true, 'sects narrow only their religion');
  assert.equal(religionAccepted(['islam'], ['islam.sunni'], 'islam', null), false, 'a sect filter needs a sect');
  assert.equal(religionAccepted([], ['christianity.maronite'], 'christianity', 'maronite'), true, 'sects alone imply the religion');
});
