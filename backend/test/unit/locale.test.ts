import { test } from 'node:test';
import assert from 'node:assert/strict';
import { asLocale, pickLocale } from '../../src/domain/locale';

test('device language → ar / en / fr, anything else → en', () => {
  assert.equal(pickLocale('ar-EG'), 'ar');
  assert.equal(pickLocale('fr-CA,fr;q=0.9,en;q=0.8'), 'fr');
  assert.equal(pickLocale('en-GB'), 'en');
  assert.equal(pickLocale('es-ES,es;q=0.9'), 'en');
  assert.equal(pickLocale('de-DE,ar;q=0.5'), 'ar'); // first supported in the user's order
  assert.equal(pickLocale('tr,fr;q=0.3,ar;q=0.7'), 'ar'); // q-values respected
  assert.equal(pickLocale(undefined), 'en');
  assert.equal(pickLocale(''), 'en');
  assert.equal(pickLocale('*'), 'en');
});

test('stored values are validated', () => {
  assert.equal(asLocale('fr'), 'fr');
  assert.equal(asLocale('es'), 'en');
  assert.equal(asLocale(null), 'en');
});
