import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeSlots, isBookable, tzOffsetMinutes, zonedToUtc } from '../../src/domain/schedule';

const base = {
  timezone: 'Asia/Dubai',
  windows: [{ weekday: 1, startMinute: 9 * 60, endMinute: 12 * 60 }], // Mondays 09:00–12:00 Dubai
  timeOff: [],
  busy: [],
  durationMinutes: 60,
  bufferMinutes: 0,
  minNoticeHours: 1,
  maxDaysAhead: 7,
  // Sunday 2026-11-29 12:00 Dubai
  now: new Date('2026-11-29T08:00:00Z'),
};

test('time zones: Dubai is UTC+4, Paris switches with DST', () => {
  assert.equal(tzOffsetMinutes('Asia/Dubai', new Date('2026-07-01T00:00:00Z')), 240);
  assert.equal(tzOffsetMinutes('Europe/Paris', new Date('2026-07-01T00:00:00Z')), 120);
  assert.equal(tzOffsetMinutes('Europe/Paris', new Date('2026-12-01T00:00:00Z')), 60);
  assert.equal(zonedToUtc(2026, 3, 29, 10 * 60, 'Europe/Paris').toISOString(), '2026-03-29T08:00:00.000Z'); // day of the change
});

test('weekly window → hourly starts on the next Monday, in the counselor time zone', () => {
  const s = computeSlots(base).map((d) => d.toISOString());
  assert.deepEqual(s, ['2026-11-30T05:00:00.000Z', '2026-11-30T05:30:00.000Z', '2026-11-30T06:00:00.000Z', '2026-11-30T06:30:00.000Z', '2026-11-30T07:00:00.000Z']);
});

test('bookings (with buffer), time off and minimum notice remove times', () => {
  const busy = [{ start: new Date('2026-11-30T06:00:00Z'), end: new Date('2026-11-30T07:00:00Z') }];
  const s = computeSlots({ ...base, busy, bufferMinutes: 15 }).map((d) => d.toISOString());
  assert.deepEqual(s, []); // 09:00–10:00 would end within the buffer; nothing else fits
  const s2 = computeSlots({ ...base, busy }).map((d) => d.toISOString());
  assert.deepEqual(s2, ['2026-11-30T05:00:00.000Z', '2026-11-30T07:00:00.000Z']);
  const off = [{ start: new Date('2026-11-30T00:00:00Z'), end: new Date('2026-12-01T00:00:00Z') }];
  assert.deepEqual(computeSlots({ ...base, timeOff: off }), []);
  assert.deepEqual(computeSlots({ ...base, minNoticeHours: 24 * 8 }), []);
});

test('only offered times can be booked', () => {
  assert.equal(isBookable(base, new Date('2026-11-30T05:00:00Z')), true);
  assert.equal(isBookable(base, new Date('2026-11-30T05:10:00Z')), false);
  assert.equal(isBookable(base, new Date('2026-12-01T05:00:00Z')), false); // Tuesday
});
