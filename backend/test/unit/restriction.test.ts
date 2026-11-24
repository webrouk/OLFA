import { test } from 'node:test';
import assert from 'node:assert/strict';
import { restrictionDetails, restrictionOf } from '../../src/domain/restriction';

const now = new Date('2026-11-24T12:00:00Z');

test('banned is permanent', () => {
  const r = restrictionOf({ status: 'BANNED', restrictionReason: 'fraud' }, now);
  assert.equal(r.kind, 'banned');
  assert.deepEqual(restrictionDetails(r), { permanent: true, reason: 'fraud', since: null });
});

test('suspension until a date, and it ends by itself', () => {
  const until = new Date('2026-12-01T00:00:00Z');
  const r = restrictionOf({ status: 'SUSPENDED', suspendedUntil: until }, now);
  assert.equal(r.kind, 'suspended');
  assert.equal(restrictionDetails(r)?.until, until.toISOString());
  assert.equal(restrictionOf({ status: 'SUSPENDED', suspendedUntil: new Date('2026-11-24T11:59:00Z') }, now).kind, 'none');
});

test('open-ended suspension and active accounts', () => {
  assert.equal(restrictionOf({ status: 'SUSPENDED' }, now).kind, 'suspended');
  assert.equal(restrictionOf({ status: 'ACTIVE' }, now).kind, 'none');
});
