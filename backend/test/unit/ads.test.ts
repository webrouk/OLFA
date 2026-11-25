import { test } from 'node:test';
import assert from 'node:assert/strict';
import { adDue, ADS_DEFAULTS, adsForMember, invalidAdsFields, isAdUnitId, parseAdsSettings } from '../../src/domain/ads';

const UNIT = 'ca-app-pub-1234567890123456/1234567890';
const on = { ...ADS_DEFAULTS, enabled: true, units: { android: UNIT, ios: '' } };

test('ad unit id format', () => {
  assert.ok(isAdUnitId(UNIT));
  assert.ok(!isAdUnitId('ca-app-pub-1234567890123456~1234567890')); // app id, not a unit id
  assert.ok(!isAdUnitId(''));
  assert.ok(!isAdUnitId('ca-app-pub-123/456'));
});

test('paid plans never get ads, whatever the settings', () => {
  for (const plan of ['PLUS', 'PREMIUM']) assert.deepEqual(adsForMember(plan, true, on), { enabled: false, reason: 'paid_plan' });
});

test('free plan: plan switch, kill switch and missing unit ids all turn ads off', () => {
  assert.equal(adsForMember('FREE', false, on).enabled, false);
  assert.deepEqual(adsForMember('FREE', true, { ...on, enabled: false }), { enabled: false, reason: 'switched_off' });
  assert.deepEqual(adsForMember('FREE', true, { ...on, units: { android: '', ios: '' } }), { enabled: false, reason: 'not_configured' });
  const r = adsForMember('FREE', true, on);
  assert.equal(r.enabled, true);
  if (r.enabled) {
    assert.equal(r.placement, 'discovery');
    assert.equal(r.units.android, UNIT);
  }
});

test('stored settings are read leniently; bad values fall back to defaults', () => {
  assert.deepEqual(parseAdsSettings(null), ADS_DEFAULTS);
  const s = parseAdsSettings({ enabled: 'yes', firstAfter: 0, interval: 2.5, maxPerSession: 99, units: { android: 'nope', ios: UNIT }, maxAdContentRating: 'X' });
  assert.equal(s.enabled, false);
  assert.equal(s.firstAfter, ADS_DEFAULTS.firstAfter);
  assert.equal(s.interval, ADS_DEFAULTS.interval);
  assert.equal(s.maxPerSession, ADS_DEFAULTS.maxPerSession);
  assert.equal(s.maxAdContentRating, 'PG');
  assert.deepEqual(s.units, { android: '', ios: UNIT });
});

test('admin validation names the wrong fields', () => {
  assert.deepEqual(invalidAdsFields(on), []);
  assert.deepEqual(invalidAdsFields({ ...on, interval: 1, units: { android: 'x', ios: '' } }).sort(), ['interval', 'units.android']);
  assert.deepEqual(invalidAdsFields({ ...on, units: { android: '', ios: '' } }), ['units']);
  assert.deepEqual(invalidAdsFields({ ...ADS_DEFAULTS }), []); // off and empty is fine
});

test('schedule: first after N profiles, then every interval, capped per session', () => {
  const s = { firstAfter: 4, interval: 6, maxPerSession: 2 };
  assert.equal(adDue(3, 0, s), false);
  assert.equal(adDue(4, 0, s), true);
  assert.equal(adDue(9, 1, s), false);
  assert.equal(adDue(10, 1, s), true);
  assert.equal(adDue(100, 2, s), false);
  assert.equal(adDue(100, 0, { ...s, maxPerSession: 0 }), false);
});
