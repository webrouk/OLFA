import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { discoveryScope, haversineKm, proximityTier, publicDistanceKm, roundCoord, sortNearest } from '../../src/domain/proximity';
import { defaultNationality, isCountry, isNationality, isOccupation, referenceCounts } from '../../src/domain/reference';
import { currencyExponent, splitFee, verifyStripeSignature } from '../../src/domain/payments';

describe('proximity', () => {
  test('coordinates are rounded to ~1 km before storage', () => {
    assert.equal(roundCoord(25.20482), 25.2);
    assert.equal(roundCoord(55.27078), 55.27);
  });
  test('haversine: Dubai → Abu Dhabi ≈ 123 km', () => {
    assert.ok(Math.abs(haversineKm(25.2, 55.27, 24.45, 54.38) - 122.6) < 1);
  });
  test('public distance is coarse and hidden when the candidate hides location', () => {
    assert.equal(publicDistanceKm(0.2, true), 1);
    assert.equal(publicDistanceKm(12.4, true), 12);
    assert.equal(publicDistanceKm(12.4, false), null);
    assert.equal(publicDistanceKm(800, true), null);
  });
  test('tiers: nearest first (any side of a border), then own country, then abroad', () => {
    assert.deepEqual([proximityTier(3, true), proximityTier(30, true), proximityTier(150, true), proximityTier(400, true), proximityTier(null, true), proximityTier(5, false), proximityTier(150, false)], [0, 1, 2, 3, 3, 0, 4]);
  });
  test('nearest first, then the rest of the own country; compatibility orders each tier', () => {
    const rows = [
      { item: 'far-best', score: 99, distanceKm: 300, countryCode: 'AE' },
      { item: 'abroad', score: 100, distanceKm: 20, countryCode: 'SA' },
      { item: 'near-ok', score: 60, distanceKm: 4, countryCode: 'AE' },
      { item: 'near-best', score: 90, distanceKm: 8, countryCode: 'AE' },
      { item: 'unknown', score: 95, distanceKm: null, countryCode: 'AE' },
    ];
    assert.deepEqual(sortNearest(rows, 'AE').map((r) => r.item), ['near-best', 'near-ok', 'abroad', 'far-best', 'unknown']);
  });
});

describe('country scope (free vs paid)', () => {
  const base = { homeCountry: 'AE', prefSameCountryOnly: false, prefCountries: [] as string[] };
  test('free plan is limited to the country it is in', () => {
    assert.deepEqual(discoveryScope({ ...base, canSearchOutside: false }), { ok: true, countries: ['AE'] });
    assert.deepEqual(discoveryScope({ ...base, canSearchOutside: false, requestedCountry: 'AE' }), { ok: true, countries: ['AE'] });
  });
  test('free plan asking for another country is refused, not widened', () => {
    assert.deepEqual(discoveryScope({ ...base, canSearchOutside: false, requestedCountry: 'SA' }), { ok: false, reason: 'outside_country_requires_plan' });
  });
  test('free plan: saved "any country" preferences cannot leak other countries', () => {
    assert.deepEqual(discoveryScope({ ...base, prefCountries: ['SA', 'EG'], canSearchOutside: false }), { ok: true, countries: ['AE'] });
  });
  test('paid plan may search anywhere, within its saved preferences', () => {
    assert.deepEqual(discoveryScope({ ...base, canSearchOutside: true }), { ok: true, countries: null });
    assert.deepEqual(discoveryScope({ ...base, canSearchOutside: true, requestedCountry: 'sa' }), { ok: true, countries: ['SA'] });
    assert.deepEqual(discoveryScope({ ...base, prefCountries: ['EG'], canSearchOutside: true, requestedCountry: 'SA' }), { ok: true, countries: [] });
  });
});

describe('reference data', () => {
  test('complete lists', () => {
    const c = referenceCounts();
    assert.ok(c.countries >= 240 && c.nationalities >= 195 && c.occupations >= 150, JSON.stringify(c));
  });
  test('validation', () => {
    assert.ok(isCountry('AE') && !isCountry('XX'));
    assert.ok(isNationality('EG') && !isNationality('PR'), 'territories are not nationalities');
    assert.ok(isOccupation('software_engineer') && !isOccupation('astronaut_wizard'));
  });
  test('country → default nationality (territory maps to sovereign)', () => {
    assert.equal(defaultNationality('SA'), 'SA');
    assert.equal(defaultNationality('PR'), 'US');
    assert.equal(defaultNationality('GF'), 'FR');
  });
});

describe('payments', () => {
  test('platform fee split always sums to the price', () => {
    for (const [p, f] of [[30000, 15], [999, 15], [1, 15], [12345, 0], [12345, 100]] as const) {
      const s = splitFee(p, f);
      assert.equal(s.platformMinor + s.counselorMinor, p);
    }
    assert.deepEqual(splitFee(30000, 15), { platformMinor: 4500, counselorMinor: 25500 });
    assert.throws(() => splitFee(10.5, 15));
  });
  test('currency exponents follow ISO-4217 (KWD has 3 decimals)', () => {
    assert.equal(currencyExponent('AED'), 2);
    assert.equal(currencyExponent('KWD'), 3);
    assert.throws(() => currencyExponent('XYZ'));
  });
  test('Stripe webhook signature: valid, tampered, replayed', () => {
    const secret = 'whsec_test', body = '{"id":"evt_1"}', t = 1_800_000_000;
    const sig = createHmac('sha256', secret).update(`${t}.${body}`).digest('hex');
    const header = `t=${t},v1=${sig}`;
    assert.equal(verifyStripeSignature(body, header, secret, t + 10), true);
    assert.equal(verifyStripeSignature(body + ' ', header, secret, t + 10), false);
    assert.equal(verifyStripeSignature(body, header, 'other', t + 10), false);
    assert.equal(verifyStripeSignature(body, header, secret, t + 3600), false);
    assert.equal(verifyStripeSignature(body, undefined, secret, t), false);
  });
});
