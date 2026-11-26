import { test } from 'node:test';
import assert from 'node:assert/strict';
import { foldForSearch, foldedLikePattern } from '../../src/domain/text-fold';

test('Arabic spelling variants fold to one form', () => {
  assert.equal(foldForSearch('أحمد'), foldForSearch('احمد'));
  assert.equal(foldForSearch('إيمان'), 'ايمان');
  assert.equal(foldForSearch('آمنة'), 'امنه');
  assert.equal(foldForSearch('رسالة'), foldForSearch('رساله'));
  assert.equal(foldForSearch('مصطفى'), foldForSearch('مصطفي'));
  assert.equal(foldForSearch('مسؤول'), 'مسوول');
  assert.equal(foldForSearch('بيئة'), 'بييه');
});

test('harakat, tatweel, digits and case', () => {
  assert.equal(foldForSearch('مُحَمَّد'), 'محمد');
  assert.equal(foldForSearch('جمـــيل'), 'جميل');
  assert.equal(foldForSearch('٠٥٠ ۱۲۳'), '050 123');
  assert.equal(foldForSearch('Sara'), 'sara');
});

test('LIKE pattern escapes wildcards', () => {
  assert.equal(foldedLikePattern(' 50%_off '), '%50\\%\\_off%');
  assert.equal(foldedLikePattern('أحمد'), '%احمد%');
});
