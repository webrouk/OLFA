import { test } from 'node:test';
import assert from 'node:assert/strict';
import { failedSelfieChecks } from '../../src/domain/selfie';

const good = { faces: 1, faceRatio: 0.4, yaw: 3, roll: -2, leftEyeOpen: 0.9, rightEyeOpen: 0.8 };
const img = { width: 1080, height: 1440, format: 'jpeg', brightness: 120, entropy: 7.2 };

test('a clear, straight, single-face selfie passes the automatic checks', () => {
  assert.deepEqual(failedSelfieChecks(good, img), []);
});

test('no face / several faces', () => {
  assert.deepEqual(failedSelfieChecks({ ...good, faces: 0 }, img), ['oneFace']);
  assert.deepEqual(failedSelfieChecks({ ...good, faces: 2 }, img), ['oneFace']);
});

test('face too small, eyes closed, head turned', () => {
  assert.deepEqual(failedSelfieChecks({ ...good, faceRatio: 0.1 }, img), ['visible']);
  assert.deepEqual(failedSelfieChecks({ ...good, leftEyeOpen: 0.1 }, img), ['visible']);
  assert.deepEqual(failedSelfieChecks({ ...good, yaw: 35 }, img), ['straight']);
  assert.deepEqual(failedSelfieChecks({ ...good, roll: -25 }, img), ['straight']);
});

test('image quality: too small, too dark, blank, not JPEG', () => {
  assert.deepEqual(failedSelfieChecks(good, { ...img, width: 400 }), ['quality']);
  assert.deepEqual(failedSelfieChecks(good, { ...img, brightness: 20 }), ['quality']);
  assert.deepEqual(failedSelfieChecks(good, { ...img, brightness: 240 }), ['quality']);
  assert.deepEqual(failedSelfieChecks(good, { ...img, entropy: 1.5 }), ['quality']);
  assert.deepEqual(failedSelfieChecks(good, { ...img, format: 'png' }), ['quality']);
});
