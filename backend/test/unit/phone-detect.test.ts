import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { containsPhoneNumber, findPhoneNumbers, normalizeDigits } from '../../src/domain/phone-detect';

test('detects international and local formats', () => {
  for (const t of ['call me +971 50 123 4567', 'رقمي 0501234567', '00966-55-123-4567', '(050) 123-4567', 'my number is 05.01.23.45.67', 'واتس +20 100 123 4567']) {
    assert.equal(containsPhoneNumber(t), true, t);
  }
});

test('Arabic-Indic and Persian digits', () => {
  assert.equal(normalizeDigits('٠٥٠١٢٣٤٥٦٧'), '0501234567');
  assert.equal(containsPhoneNumber('رقمي ٠٥٠ ١٢٣ ٤٥٦٧'), true);
  assert.equal(containsPhoneNumber('شماره ۰۹۱۲۳۴۵۶۷۸۹'), true);
});

test('ignores dates, times, prices, short numbers and repeated digits', () => {
  for (const t of ['see you 2026-11-14', 'on 14/11/2026', 'at 19:30', 'it cost 1500 AED', 'code 1234', 'I am 30 years old', '00000000', 'room 205']) {
    assert.equal(containsPhoneNumber(t), false, t);
  }
});

test('returns the normalised digits', () => {
  assert.deepEqual(findPhoneNumbers('a +971 50 123 4567 b 0501112222'), ['971501234567', '0501112222']);
});
