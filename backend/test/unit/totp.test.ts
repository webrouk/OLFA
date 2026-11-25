import { test } from 'node:test';
import assert from 'node:assert/strict';
import { base32Decode, base32Encode, totpAt, verifyTotp } from '../../src/domain/totp';

// RFC 6238 appendix B, SHA-1 secret "12345678901234567890"
const SECRET = base32Encode(Buffer.from('12345678901234567890'));

test('RFC 6238 test vectors (6-digit tail of the 8-digit values)', () => {
  assert.equal(totpAt(SECRET, 59, 30, 8), '94287082');
  assert.equal(totpAt(SECRET, 1111111109, 30, 8), '07081804');
  assert.equal(totpAt(SECRET, 1234567890, 30, 8), '89005924');
  assert.equal(totpAt(SECRET, 2000000000, 30, 8), '69279037');
});

test('base32 round trip', () => {
  const b = Buffer.from('hello totp secret!!');
  assert.deepEqual(base32Decode(base32Encode(b)), b);
});

test('accepts the current code and ±1 step, refuses others', () => {
  const now = 1_800_000_000;
  assert.ok(verifyTotp(SECRET, totpAt(SECRET, now), now) !== null);
  assert.ok(verifyTotp(SECRET, totpAt(SECRET, now - 30), now) !== null);
  assert.equal(verifyTotp(SECRET, totpAt(SECRET, now - 120), now), null);
  assert.equal(verifyTotp(SECRET, '12ab56', now), null);
});
