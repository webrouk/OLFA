import { createPrivateKey, createSign, sign as cryptoSign, verify as cryptoVerify, X509Certificate } from 'node:crypto';

/**
 * Verifies an App Store JWS (signed transaction, renewal info or server
 * notification) the way Apple's App Store Server Library does:
 *   1. header.alg is ES256 and header.x5c holds [leaf, intermediate, root];
 *   2. the root is byte-identical to the trusted Apple Root CA - G3 we ship
 *      via configuration (never the one in the token);
 *   3. leaf ← intermediate ← root signatures and validity dates check out;
 *   4. the leaf carries Apple's receipt-signing OID and the intermediate the
 *      WWDR OID;
 *   5. the ES256 signature over "header.payload" verifies with the leaf key.
 */
export class JwsError extends Error {}

const b64url = (s: string) => Buffer.from(s, 'base64url');

// DER-encoded OIDs searched for in the certificates.
const OID_LEAF = Buffer.from('060a2a864886f76364060b01', 'hex'); // 1.2.840.113635.100.6.11.1
const OID_INTERMEDIATE = Buffer.from('060a2a864886f76364060201', 'hex'); // 1.2.840.113635.100.6.2.1

export interface JwsOptions {
  /** Trusted roots (DER or PEM). */
  trustedRoots: (Buffer | string)[];
  /** Date the chain must be valid at (default: now). */
  at?: Date;
  /** Tests only: skip the Apple OID checks for a locally generated chain. */
  skipOidCheck?: boolean;
}

export function decodeJwsUnverified<T>(jws: string): { header: Record<string, unknown>; payload: T } {
  const [h, p] = jws.split('.');
  if (!h || !p) throw new JwsError('malformed JWS');
  return { header: JSON.parse(b64url(h).toString('utf8')), payload: JSON.parse(b64url(p).toString('utf8')) as T };
}

export function verifyAppleJws<T>(jws: string, opts: JwsOptions): T {
  const parts = jws.split('.');
  if (parts.length !== 3) throw new JwsError('malformed JWS');
  const [h, p, s] = parts;
  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(b64url(h).toString('utf8'));
  } catch {
    throw new JwsError('bad header');
  }
  if (header.alg !== 'ES256') throw new JwsError('unexpected alg');
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) throw new JwsError('x5c chain must have 3 certificates');
  const [leaf, mid, root] = header.x5c.map((c) => new X509Certificate(Buffer.from(c, 'base64')));
  const trusted = opts.trustedRoots.map((r) => new X509Certificate(r));
  if (!trusted.some((t) => t.raw.equals(root.raw))) throw new JwsError('untrusted root');
  if (!leaf.verify(mid.publicKey) || !leaf.checkIssued(mid)) throw new JwsError('leaf not issued by intermediate');
  if (!mid.verify(root.publicKey) || !mid.checkIssued(root)) throw new JwsError('intermediate not issued by root');
  const at = (opts.at ?? new Date()).getTime();
  for (const c of [leaf, mid, root]) {
    if (at < Date.parse(c.validFrom) || at > Date.parse(c.validTo)) throw new JwsError('certificate not valid at signing time');
  }
  if (!opts.skipOidCheck) {
    if (!leaf.raw.includes(OID_LEAF)) throw new JwsError('leaf is not an App Store signing certificate');
    if (!mid.raw.includes(OID_INTERMEDIATE)) throw new JwsError('intermediate is not Apple WWDR');
  }
  const ok = cryptoVerify('sha256', Buffer.from(`${h}.${p}`), { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' }, b64url(s));
  if (!ok) throw new JwsError('bad signature');
  return JSON.parse(b64url(p).toString('utf8')) as T;
}

// ── outbound JWTs (App Store Server API, Google service account) ───

const enc = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');

/** ES256 JWT for the App Store Server API (key from App Store Connect, .p8 PEM). */
export function appStoreApiJwt(o: { issuerId: string; keyId: string; privateKeyPem: string; bundleId: string; now?: Date }): string {
  const iat = Math.floor((o.now ?? new Date()).getTime() / 1000);
  const head = enc({ alg: 'ES256', kid: o.keyId, typ: 'JWT' });
  const body = enc({ iss: o.issuerId, iat, exp: iat + 20 * 60, aud: 'appstoreconnect-v1', bid: o.bundleId });
  const sig = cryptoSign('sha256', Buffer.from(`${head}.${body}`), { key: createPrivateKey(o.privateKeyPem), dsaEncoding: 'ieee-p1363' });
  return `${head}.${body}.${sig.toString('base64url')}`;
}

/** RS256 assertion exchanged for an OAuth token (Google Play Developer API). */
export function googleServiceJwt(o: { clientEmail: string; privateKeyPem: string; tokenUri?: string; now?: Date }): string {
  const iat = Math.floor((o.now ?? new Date()).getTime() / 1000);
  const head = enc({ alg: 'RS256', typ: 'JWT' });
  const body = enc({
    iss: o.clientEmail,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: o.tokenUri ?? 'https://oauth2.googleapis.com/token',
    iat,
    exp: iat + 3600,
  });
  const signer = createSign('RSA-SHA256');
  signer.update(`${head}.${body}`);
  return `${head}.${body}.${signer.sign(o.privateKeyPem).toString('base64url')}`;
}
