import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { DEFAULT_PRIVACY, isOnlineVisible, photosBlurred, privacyOf, readReceiptsVisible, visibleInDiscovery } from '../../src/domain/privacy';
import { monthWindow } from '../../src/domain/quota-period';

const on = DEFAULT_PRIVACY;
const off = (k: keyof typeof on) => ({ ...on, [k]: !on[k] });

test('online status is reciprocal and expires after 5 minutes', () => {
  const now = Date.parse('2026-11-14T10:00:00Z');
  const recent = new Date(now - 60_000);
  assert.equal(isOnlineVisible(on, on, recent, now), true);
  assert.equal(isOnlineVisible(off('showOnline'), on, recent, now), false, 'viewer hid theirs');
  assert.equal(isOnlineVisible(on, off('showOnline'), recent, now), false, 'target hid theirs');
  assert.equal(isOnlineVisible(on, on, new Date(now - 6 * 60_000), now), false);
  assert.equal(isOnlineVisible(on, on, null, now), false);
});

test('read receipts need both people', () => {
  assert.equal(readReceiptsVisible(on, on), true);
  assert.equal(readReceiptsVisible(off('readReceipts'), on), false);
  assert.equal(readReceiptsVisible(on, off('readReceipts')), false);
});

test('blurred photos until matched, never for yourself', () => {
  const b = off('blurPhotos');
  assert.equal(photosBlurred(b, false), true);
  assert.equal(photosBlurred(b, true), false);
  assert.equal(photosBlurred(b, false, true), false);
  assert.equal(photosBlurred(on, false), false);
});

test('discovery visibility: hidden, incognito with and without the plan', () => {
  assert.equal(visibleInDiscovery(off('discoverable'), false, true), false);
  const inc = off('incognito');
  assert.equal(visibleInDiscovery(inc, true, false), false);
  assert.equal(visibleInDiscovery(inc, true, true), true);
  assert.equal(visibleInDiscovery(inc, false, false), true, 'plan lapsed → incognito ignored');
});

test('privacyOf fills defaults and ignores junk', () => {
  assert.deepEqual(privacyOf(null), on);
  assert.equal(privacyOf({ showOnline: false }).showOnline, false);
  assert.equal(privacyOf({ showOnline: 'no' as unknown as boolean }).showOnline, true);
});

test('monthly window follows local month boundaries (Dubai, UTC+4)', () => {
  const w = monthWindow(new Date('2026-11-30T21:00:00Z'), 'Asia/Dubai'); // Dec 1, 01:00 local
  assert.equal(w.dayKey, '2026-12');
  assert.equal(w.start.toISOString(), '2026-11-30T20:00:00.000Z');
  assert.equal(w.end.toISOString(), '2026-12-31T20:00:00.000Z');
  const y = monthWindow(new Date('2026-12-15T00:00:00Z'), 'UTC');
  assert.equal(y.end.toISOString(), '2027-01-01T00:00:00.000Z');
});
