import { strict as assert } from 'node:assert';
import { execFileSync } from 'node:child_process';
import { generateKeyPairSync, sign as cryptoSign, verify as cryptoVerify, createVerify } from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { appStoreApiJwt, googleServiceJwt, JwsError, verifyAppleJws } from '../../src/domain/apple-jws';
import { currencyExponent } from '../../src/domain/payments';
import {
  AppleRenewalInfo,
  AppleTransaction,
  appleSnapshot,
  classifyChange,
  deriveStatus,
  googleSnapshot,
  GoogleSubscriptionV2,
  manageUrl,
  resolveOwner,
} from '../../src/domain/store-subscriptions';

const NOW = new Date('2026-11-14T12:00:00Z');
const day = 86_400_000;
const USER = '3f1c2a9e-6b7d-4c1e-9a2b-1d2e3f4a5b6c';

const tx = (o: Partial<AppleTransaction> = {}): AppleTransaction => ({
  transactionId: '2000000101',
  originalTransactionId: '2000000100',
  productId: 'olfa.plus.monthly',
  bundleId: 'app.olfa',
  purchaseDate: NOW.getTime() - 3 * day,
  expiresDate: NOW.getTime() + 27 * day,
  environment: 'Production',
  appAccountToken: USER,
  price: 39990,
  currency: 'AED',
  ...o,
});
const ren = (o: Partial<AppleRenewalInfo> = {}): AppleRenewalInfo => ({ originalTransactionId: '2000000100', productId: 'olfa.plus.monthly', autoRenewProductId: 'olfa.plus.monthly', autoRenewStatus: 1, ...o });

// ── Apple ─────────────────────────────────────────────────────────

test('apple: new purchase is active, price converted to minor units', () => {
  const s = appleSnapshot(tx(), ren(), NOW, currencyExponent);
  assert.equal(s.state, 'ACTIVE');
  assert.equal(s.priceMinor, 3999);
  assert.equal(s.accountToken, USER);
  const d = deriveStatus(s, NOW);
  assert.deepEqual([d.status, d.entitled, d.autoRenew], ['ACTIVE', true, true]);
});

test('apple: cancelled = auto-renew off, access until the period ends', () => {
  const d = deriveStatus(appleSnapshot(tx(), ren({ autoRenewStatus: 0 }), NOW), NOW);
  assert.deepEqual([d.status, d.entitled], ['CANCELLED', true]);
  const after = new Date(NOW.getTime() + 28 * day);
  assert.equal(deriveStatus(appleSnapshot(tx(), ren({ autoRenewStatus: 0 }), after), after).status, 'EXPIRED');
});

test('apple: downgrade is scheduled for the next renewal; upgrade is immediate', () => {
  const premium = tx({ productId: 'olfa.premium.monthly' });
  const s = appleSnapshot(premium, ren({ productId: 'olfa.premium.monthly', autoRenewProductId: 'olfa.plus.monthly' }), NOW);
  assert.equal(s.pendingProductId, 'olfa.plus.monthly');
  assert.equal(s.productId, 'olfa.premium.monthly');
  assert.equal(classifyChange({ plan: 'PREMIUM', expiresAt: s.expiresAt, pendingPlan: null }, { plan: 'PREMIUM', expiresAt: s.expiresAt, pendingPlan: 'PLUS' }), 'downgrade_scheduled');
  assert.equal(classifyChange({ plan: 'PLUS', expiresAt: s.expiresAt, pendingPlan: null }, { plan: 'PREMIUM', expiresAt: s.expiresAt, pendingPlan: null }), 'upgrade');
});

test('apple: billing failure → grace keeps access, then billing retry removes it', () => {
  const lapsed = tx({ expiresDate: NOW.getTime() - day });
  const g = appleSnapshot(lapsed, ren({ isInBillingRetryPeriod: true, gracePeriodExpiresDate: NOW.getTime() + 5 * day }), NOW);
  assert.equal(g.state, 'GRACE');
  assert.equal(g.expiresAt.getTime(), NOW.getTime() + 5 * day, 'access runs to the end of grace');
  assert.deepEqual([deriveStatus(g, NOW).status, deriveStatus(g, NOW).entitled], ['GRACE_PERIOD', true]);
  const r = appleSnapshot(lapsed, ren({ isInBillingRetryPeriod: true }), NOW);
  assert.deepEqual([deriveStatus(r, NOW).status, deriveStatus(r, NOW).entitled], ['BILLING_RETRY', false]);
  const e = appleSnapshot(lapsed, ren({ isInBillingRetryPeriod: false, autoRenewStatus: 0, expirationIntent: 2 }), NOW);
  assert.equal(deriveStatus(e, NOW).status, 'EXPIRED');
});

test('apple: refund and family-sharing revocation remove access immediately', () => {
  const refunded = appleSnapshot(tx({ revocationDate: NOW.getTime() - 1000, revocationReason: 0 }), ren(), NOW);
  assert.deepEqual([deriveStatus(refunded, NOW).status, deriveStatus(refunded, NOW).entitled], ['REFUNDED', false]);
  const revoked = appleSnapshot(tx({ revocationDate: NOW.getTime() - 1000, inAppOwnershipType: 'FAMILY_SHARED' }), ren(), NOW);
  assert.equal(deriveStatus(revoked, NOW).status, 'REVOKED');
});

test('apple: renewal moves the expiry forward', () => {
  const prev = { plan: 'PLUS' as const, expiresAt: new Date(NOW.getTime() + day), pendingPlan: null };
  const s = appleSnapshot(tx({ expiresDate: NOW.getTime() + 31 * day, transactionId: '2000000150' }), ren(), NOW);
  assert.equal(classifyChange(prev, { plan: 'PLUS', expiresAt: s.expiresAt, pendingPlan: null }), 'renewal');
});

test('apple: a non-subscription transaction is rejected', () => {
  assert.throws(() => appleSnapshot(tx({ expiresDate: undefined }), null, NOW));
});

// ── Google ────────────────────────────────────────────────────────

const g = (o: Partial<GoogleSubscriptionV2> = {}, item: Partial<GoogleSubscriptionV2['lineItems'][0]> = {}): GoogleSubscriptionV2 => ({
  subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
  latestOrderId: 'GPA.3333-4444-5555-66666',
  acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
  externalAccountIdentifiers: { obfuscatedExternalAccountId: USER },
  lineItems: [{ productId: 'olfa_plus', expiryTime: new Date(NOW.getTime() + 20 * day).toISOString(), autoRenewingPlan: { autoRenewEnabled: true }, ...item }],
  ...o,
});

test('google: active purchase that still needs acknowledging', () => {
  const s = googleSnapshot('tok-1', g({ acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING' }), NOW);
  assert.equal(s.needsAcknowledge, true);
  assert.deepEqual([deriveStatus(s, NOW).status, deriveStatus(s, NOW).entitled], ['ACTIVE', true]);
});

test('google: canceled keeps access until expiry, then expires', () => {
  const s = googleSnapshot('tok-1', g({ subscriptionState: 'SUBSCRIPTION_STATE_CANCELED' }), NOW);
  assert.deepEqual([deriveStatus(s, NOW).status, deriveStatus(s, NOW).entitled], ['CANCELLED', true]);
});

test('google: grace keeps access; on hold and paused do not', () => {
  assert.equal(deriveStatus(googleSnapshot('t', g({ subscriptionState: 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD' }), NOW), NOW).entitled, true);
  const hold = googleSnapshot('t', g({ subscriptionState: 'SUBSCRIPTION_STATE_ON_HOLD' }), NOW);
  assert.deepEqual([deriveStatus(hold, NOW).status, deriveStatus(hold, NOW).entitled], ['ON_HOLD', false]);
  const paused = googleSnapshot('t', g({ subscriptionState: 'SUBSCRIPTION_STATE_PAUSED' }), NOW);
  assert.deepEqual([deriveStatus(paused, NOW).status, deriveStatus(paused, NOW).entitled], ['PAUSED', false]);
});

test('google: pending (slow payment) grants nothing and is not acknowledged yet', () => {
  const s = googleSnapshot('t', g({ subscriptionState: 'SUBSCRIPTION_STATE_PENDING', acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING' }), NOW);
  assert.equal(deriveStatus(s, NOW).entitled, false);
  assert.equal(s.needsAcknowledge, false);
});

test('google: plan change links the old token; deferred downgrade is pending', () => {
  const up = googleSnapshot('tok-2', g({ linkedPurchaseToken: 'tok-1' }, { productId: 'olfa_premium' }), NOW);
  assert.equal(up.replacesOriginalId, 'tok-1');
  assert.equal(up.productId, 'olfa_premium');
  const down = googleSnapshot('tok-2', g({}, { productId: 'olfa_premium', deferredItemReplacement: { productId: 'olfa_plus' } }), NOW);
  assert.equal(down.pendingProductId, 'olfa_plus');
});

test('google: expired subscription', () => {
  const s = googleSnapshot('t', g({ subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' }, { expiryTime: new Date(NOW.getTime() - day).toISOString() }), NOW);
  assert.equal(deriveStatus(s, NOW).status, 'EXPIRED');
});

// ── ownership / restore ───────────────────────────────────────────

test('ownership: purchase belongs to the account that bought it; restore can move it', () => {
  const other = '00000000-0000-4000-8000-000000000001';
  assert.deepEqual(resolveOwner({ accountToken: USER, currentOwner: null, requester: USER, isRestore: false }), { owner: USER, transferred: false });
  assert.deepEqual(resolveOwner({ accountToken: USER, currentOwner: USER, requester: other, isRestore: false }), { error: 'belongs_to_another_account' });
  assert.deepEqual(resolveOwner({ accountToken: USER, currentOwner: USER, requester: other, isRestore: true }), { owner: other, transferred: true });
  assert.deepEqual(resolveOwner({ accountToken: null, currentOwner: null, requester: other, isRestore: true }), { owner: other, transferred: false });
});

test('manage subscription links', () => {
  assert.equal(manageUrl('APPLE'), 'https://apps.apple.com/account/subscriptions');
  assert.equal(manageUrl('GOOGLE', { packageName: 'app.olfa', productId: 'olfa_plus' }), 'https://play.google.com/store/account/subscriptions?sku=olfa_plus&package=app.olfa');
});

// ── JWS verification with a locally generated chain ───────────────

function makeChain() {
  const d = mkdtempSync(join(tmpdir(), 'olfa-jws-'));
  const sh = (...a: string[]) => execFileSync('openssl', a, { cwd: d, stdio: 'pipe' });
  const ext = (name: string, body: string) => writeFileSync(join(d, name), body);
  ext('ca.ext', 'basicConstraints=critical,CA:true\nkeyUsage=critical,keyCertSign,cRLSign\n');
  ext('leaf.ext', 'basicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\n');
  for (const k of ['root', 'mid', 'leaf']) sh('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${k}.key`);
  sh('req', '-x509', '-new', '-key', 'root.key', '-subj', '/CN=Test Root', '-days', '30', '-out', 'root.pem', '-addext', 'basicConstraints=critical,CA:true', '-addext', 'keyUsage=critical,keyCertSign,cRLSign');
  sh('req', '-new', '-key', 'mid.key', '-subj', '/CN=Test Mid', '-out', 'mid.csr');
  sh('x509', '-req', '-in', 'mid.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '20', '-out', 'mid.pem', '-extfile', 'ca.ext');
  sh('req', '-new', '-key', 'leaf.key', '-subj', '/CN=Test Leaf', '-out', 'leaf.csr');
  sh('x509', '-req', '-in', 'leaf.csr', '-CA', 'mid.pem', '-CAkey', 'mid.key', '-CAcreateserial', '-days', '10', '-out', 'leaf.pem', '-extfile', 'leaf.ext');
  const der = (f: string) => execFileSync('openssl', ['x509', '-in', f, '-outform', 'DER'], { cwd: d }).toString('base64');
  return { x5c: [der('leaf.pem'), der('mid.pem'), der('root.pem')], leafKey: readFileSync(join(d, 'leaf.key'), 'utf8'), rootPem: readFileSync(join(d, 'root.pem'), 'utf8') };
}

function hasOpenssl() {
  try {
    execFileSync('openssl', ['version'], { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

test('apple JWS: valid chain verifies; tampering, foreign roots and bad algs fail', { skip: !hasOpenssl() && 'openssl not installed' }, () => {
  const c = makeChain();
  const enc = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const h = enc({ alg: 'ES256', x5c: c.x5c });
  const p = enc(tx());
  const sig = cryptoSign('sha256', Buffer.from(`${h}.${p}`), { key: c.leafKey, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  const jws = `${h}.${p}.${sig}`;
  const got = verifyAppleJws<AppleTransaction>(jws, { trustedRoots: [c.rootPem], skipOidCheck: true });
  assert.equal(got.originalTransactionId, '2000000100');

  // OID check is on by default — a non-Apple chain is refused
  assert.throws(() => verifyAppleJws(jws, { trustedRoots: [c.rootPem] }), JwsError);
  // payload tampering
  const forged = `${h}.${enc(tx({ productId: 'olfa.premium.monthly' }))}.${sig}`;
  assert.throws(() => verifyAppleJws(forged, { trustedRoots: [c.rootPem], skipOidCheck: true }), /bad signature/);
  // a different trusted root
  const other = makeChain();
  assert.throws(() => verifyAppleJws(jws, { trustedRoots: [other.rootPem], skipOidCheck: true }), /untrusted root/);
  // alg confusion
  const none = `${enc({ alg: 'none', x5c: c.x5c })}.${p}.`;
  assert.throws(() => verifyAppleJws(none, { trustedRoots: [c.rootPem], skipOidCheck: true }), /alg/);
  // outside the certificate validity window
  assert.throws(() => verifyAppleJws(jws, { trustedRoots: [c.rootPem], skipOidCheck: true, at: new Date(Date.now() + 365 * day) }), /not valid/);
});

test('outbound JWTs are signed with the configured keys', () => {
  const ec = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwt = appStoreApiJwt({ issuerId: 'iss', keyId: 'KID123', bundleId: 'app.olfa', privateKeyPem: ec.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(), now: NOW });
  const [h, p, s] = jwt.split('.');
  assert.equal(JSON.parse(Buffer.from(h, 'base64url').toString()).kid, 'KID123');
  assert.equal(JSON.parse(Buffer.from(p, 'base64url').toString()).aud, 'appstoreconnect-v1');
  assert.ok(cryptoVerify('sha256', Buffer.from(`${h}.${p}`), { key: ec.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url')));

  const rsa = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const g2 = googleServiceJwt({ clientEmail: 'svc@olfa.iam.gserviceaccount.com', privateKeyPem: rsa.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(), now: NOW });
  const [gh, gp, gs] = g2.split('.');
  const v = createVerify('RSA-SHA256');
  v.update(`${gh}.${gp}`);
  assert.ok(v.verify(rsa.publicKey, Buffer.from(gs, 'base64url')));
  assert.match(JSON.parse(Buffer.from(gp, 'base64url').toString()).scope, /androidpublisher/);
});
