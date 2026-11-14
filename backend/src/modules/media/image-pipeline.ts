import { createHash } from 'node:crypto';
import sharp from 'sharp';

export const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp', 'image/heic'] as const;
export type AllowedMime = (typeof ALLOWED_MIME)[number];
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

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

/** Magic-byte sniffing — never trust the declared Content-Type. */
export function sniffImage(buf: Buffer): AllowedMime | null {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  const brand = buf.toString('ascii', 4, 12);
  if (/^ftyp(heic|heix|mif1|msf1)/.test(brand)) return 'image/heic';
  return null;
}
