import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { dHash, hamming, processImage, sniffImage, VARIANTS } from '../../src/modules/media/image-pipeline';

/** Synthetic photo with structure (so dHash is meaningful) and EXIF metadata. */
async function makePhoto(w: number, h: number, seed = 0, format: 'jpeg' | 'png' | 'webp' = 'jpeg'): Promise<Buffer> {
  // Seeded blocky texture (like real photos: edges and regions), upscaled.
  let s = seed * 9301 + 49297;
  const rnd = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  const cw = 24, ch = 18;
  const cells = Buffer.alloc(cw * ch * 3);
  for (let i = 0; i < cells.length; i++) cells[i] = Math.floor(rnd() * 256);
  return sharp(cells, { raw: { width: cw, height: ch, channels: 3 } })
    .resize(w, h, { kernel: 'cubic' })
    .withMetadata({ exif: { IFD0: { Copyright: 'secret-owner', ImageDescription: 'GPS 25.2,55.3' } } })
    .toFormat(format)
    .toBuffer();
}

describe('image pipeline (real sharp)', () => {
  test('magic-byte sniffing ignores the declared type', async () => {
    assert.equal(sniffImage(await makePhoto(400, 400, 0, 'jpeg')), 'image/jpeg');
    assert.equal(sniffImage(await makePhoto(400, 400, 0, 'png')), 'image/png');
    assert.equal(sniffImage(await makePhoto(400, 400, 0, 'webp')), 'image/webp');
    assert.equal(sniffImage(Buffer.from('<?php echo "not an image"; ?>')), null);
    assert.equal(sniffImage(Buffer.from('%PDF-1.7 fake')), null);
  });

  test('variants are WebP, size-bounded, and carry NO metadata', async () => {
    const original = await makePhoto(2400, 1800);
    const before = await sharp(original).metadata();
    assert.ok(before.exif, 'fixture has EXIF');

    const out = await processImage(original);
    assert.equal(out.width, 2400);
    assert.equal(out.sha256.length, 64);
    for (const [name, max] of Object.entries(VARIANTS)) {
      const m = await sharp(out.variants[name as keyof typeof VARIANTS]).metadata();
      assert.equal(m.format, 'webp', `${name} format`);
      assert.ok(Math.max(m.width!, m.height!) <= max, `${name} within ${max}px`);
      assert.equal(m.exif, undefined, `${name} has no EXIF`);
      assert.equal(m.icc, undefined, `${name} has no ICC`);
    }
    assert.ok(out.variants.thumb.length < out.variants.full.length);
  });

  test('small images are rejected', async () => {
    await assert.rejects(processImage(await makePhoto(200, 200)), /too small/);
  });

  test('corrupt data is rejected', async () => {
    const good = await makePhoto(600, 600);
    await assert.rejects(processImage(Buffer.concat([good.subarray(0, 200), Buffer.alloc(500)])));
  });

  test('dHash: near-duplicates are close, different photos are far', async () => {
    const a = await makePhoto(1200, 900, 1);
    const aSmall = await sharp(a).resize(500).jpeg({ quality: 60 }).toBuffer(); // re-encoded copy
    const b = await makePhoto(1200, 900, 7);
    const ha = await dHash(a);
    assert.match(ha, /^[0-9a-f]{16}$/);
    assert.ok(hamming(ha, await dHash(aSmall)) <= 6, 're-encoded copy detected as duplicate');
    assert.ok(hamming(ha, await dHash(b)) > 6, 'different photo not flagged');
  });
});
