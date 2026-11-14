import { createHash } from 'node:crypto';
import sharp from 'sharp';

export const VARIANTS = { thumb: 200, card: 800, full: 1600 } as const;
export type VariantName = keyof typeof VARIANTS;

export interface Processed {
  width: number;
  height: number;
  sha256: string;
  phash: string; // 64-bit difference hash, hex
  variants: Record<VariantName, Buffer>;
}

/**
 * Auto-orients, strips ALL metadata (EXIF/GPS), and produces WebP variants.
 * The original never leaves private storage.
 */
export async function processImage(original: Buffer): Promise<Processed> {
  const base = sharp(original, { failOn: 'error', limitInputPixels: 50_000_000 }).rotate();
  const meta = await base.metadata();
  if (!meta.width || !meta.height || meta.width < 300 || meta.height < 300) throw new Error('image too small');

  const variants = {} as Record<VariantName, Buffer>;
  for (const [name, size] of Object.entries(VARIANTS) as [VariantName, number][]) {
    variants[name] = await base
      .clone()
      .resize({ width: size, height: size, fit: 'inside', withoutEnlargement: true })
      .webp({ quality: name === 'thumb' ? 70 : 80 })
      .toBuffer(); // sharp drops metadata unless .withMetadata() is called
  }
  return {
    width: meta.width,
    height: meta.height,
    sha256: createHash('sha256').update(original).digest('hex'),
    phash: await dHash(original),
    variants,
  };
}

/** dHash: 9×8 grayscale, compare adjacent pixels → 64 bits. Near-duplicates have small Hamming distance. */
export async function dHash(img: Buffer): Promise<string> {
  const px = await sharp(img).rotate().grayscale().resize(9, 8, { fit: 'fill' }).raw().toBuffer();
  let bits = 0n;
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) {
      bits = (bits << 1n) | (px[y * 9 + x] > px[y * 9 + x + 1] ? 1n : 0n);
    }
  }
  return bits.toString(16).padStart(16, '0');
}

export function hamming(a: string, b: string): number {
  let x = BigInt(`0x${a}`) ^ BigInt(`0x${b}`);
  let n = 0;
  while (x) {
    n += Number(x & 1n);
    x >>= 1n;
  }
  return n;
}
