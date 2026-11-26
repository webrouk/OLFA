import { Inject, Injectable, Logger } from '@nestjs/common';
import { readFileSync } from 'node:fs';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { appStoreApiJwt, googleServiceJwt, JwsError, verifyAppleJws } from '../../domain/apple-jws';
import { AppleRenewalInfo, AppleTransaction, GoogleSubscriptionV2 } from '../../domain/store-subscriptions';

/** App Store Server Notifications V2 (decoded). */
export interface AppleNotification {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data?: { bundleId?: string; environment?: string; signedTransactionInfo?: string; signedRenewalInfo?: string };
}

/**
 * Talks to the stores. Every piece of purchase data the app or a webhook
 * sends us is verified here before it can change an entitlement:
 *  · Apple: JWS signatures chained to Apple Root CA - G3 (configured file),
 *    bundle id and environment checked; optional App Store Server API lookups.
 *  · Google: the purchase token is looked up with the Play Developer API
 *    (service account); the token alone proves nothing.
 */
@Injectable()
export class StoreGateway {
  private readonly log = new Logger('Store');
  private appleRoots: Buffer[] | null = null;
  private googleToken: { token: string; exp: number } | null = null;

  constructor(@Inject(ENV) private readonly env: Env) {}

  // ── Apple ──

  private roots(): Buffer[] {
    if (this.appleRoots) return this.appleRoots;
    if (!this.env.APPLE_ROOT_CA_PATH) throw new AppError(ErrorCode.INTERNAL, 'App Store verification is not configured');
    this.appleRoots = [readFileSync(this.env.APPLE_ROOT_CA_PATH)];
    return this.appleRoots;
  }

  private verify<T>(jws: string): T {
    try {
      return verifyAppleJws<T>(jws, { trustedRoots: this.roots() });
    } catch (e) {
      if (e instanceof JwsError) throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, e.message);
      throw e;
    }
  }

  private checkApp(bundleId: string | undefined, environment: string | undefined) {
    if (!this.env.APPLE_BUNDLE_ID || bundleId !== this.env.APPLE_BUNDLE_ID) throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, 'bundle id mismatch');
    if (environment !== 'Production' && this.env.APPLE_ALLOW_SANDBOX !== 'true') throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, 'sandbox purchases are not accepted here');
  }

  appleTransaction(jws: string): AppleTransaction {
    const tx = this.verify<AppleTransaction>(jws);
    this.checkApp(tx.bundleId, tx.environment);
    return tx;
  }

  appleRenewal(jws: string): AppleRenewalInfo {
    return this.verify<AppleRenewalInfo>(jws);
  }

  appleNotification(signedPayload: string): AppleNotification {
    const n = this.verify<AppleNotification>(signedPayload);
    if (n.notificationType !== 'TEST') this.checkApp(n.data?.bundleId, n.data?.environment);
    return n;
  }

  get appleApiConfigured() {
    return !!(this.env.APPLE_ISSUER_ID && this.env.APPLE_KEY_ID && this.env.APPLE_PRIVATE_KEY && this.env.APPLE_BUNDLE_ID);
  }

  /**
   * Latest signed transaction + renewal info for a subscription (App Store
   * Server API "Get All Subscription Statuses"). Used on restore so the
   * server never relies on a stale device copy.
   */
  async appleStatus(originalTransactionId: string, sandbox = false): Promise<{ transaction: AppleTransaction; renewal: AppleRenewalInfo | null } | null> {
    if (!this.appleApiConfigured) return null;
    const host = sandbox ? 'https://api.storekit-sandbox.itunes.apple.com' : 'https://api.storekit.itunes.apple.com';
    const jwt = appStoreApiJwt({ issuerId: this.env.APPLE_ISSUER_ID!, keyId: this.env.APPLE_KEY_ID!, privateKeyPem: this.env.APPLE_PRIVATE_KEY!.replace(/\\n/g, '\n'), bundleId: this.env.APPLE_BUNDLE_ID! });
    const res = await fetch(`${host}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`, { headers: { Authorization: `Bearer ${jwt}` } });
    if (res.status === 404) return null;
    if (!res.ok) throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, `App Store API ${res.status}`);
    const body = (await res.json()) as { data?: { lastTransactions?: { originalTransactionId: string; signedTransactionInfo: string; signedRenewalInfo?: string }[] }[] };
    const last = body.data?.flatMap((g) => g.lastTransactions ?? []).find((t) => t.originalTransactionId === originalTransactionId);
    if (!last) return null;
    return { transaction: this.appleTransaction(last.signedTransactionInfo), renewal: last.signedRenewalInfo ? this.appleRenewal(last.signedRenewalInfo) : null };
  }

  // ── Google ──

  private async googleAccessToken(): Promise<string> {
    if (this.googleToken && this.googleToken.exp > Date.now() + 60_000) return this.googleToken.token;
    if (!this.env.GOOGLE_SERVICE_ACCOUNT_JSON) throw new AppError(ErrorCode.INTERNAL, 'Google Play verification is not configured');
    const sa = JSON.parse(this.env.GOOGLE_SERVICE_ACCOUNT_JSON) as { client_email: string; private_key: string; token_uri?: string };
    const assertion = googleServiceJwt({ clientEmail: sa.client_email, privateKeyPem: sa.private_key, tokenUri: sa.token_uri });
    const res = await fetch(sa.token_uri ?? 'https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    });
    if (!res.ok) throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, `Google OAuth ${res.status}`);
    const j = (await res.json()) as { access_token: string; expires_in: number };
    this.googleToken = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
    return j.access_token;
  }

  private gp(path: string) {
    if (!this.env.GOOGLE_PACKAGE_NAME) throw new AppError(ErrorCode.INTERNAL, 'Google Play verification is not configured');
    return `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(this.env.GOOGLE_PACKAGE_NAME)}/${path}`;
  }

  async googleSubscription(purchaseToken: string): Promise<GoogleSubscriptionV2> {
    const res = await fetch(this.gp(`purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`), { headers: { Authorization: `Bearer ${await this.googleAccessToken()}` } });
    if (res.status === 404 || res.status === 410) throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, 'unknown purchase token');
    if (!res.ok) throw new AppError(ErrorCode.STORE_VERIFICATION_FAILED, `Play API ${res.status}`);
    return (await res.json()) as GoogleSubscriptionV2;
  }

  /** Must happen within 3 days of purchase or Google refunds it automatically. */
  async googleAcknowledge(productId: string, purchaseToken: string) {
    const res = await fetch(this.gp(`purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`), {
      method: 'POST',
      headers: { Authorization: `Bearer ${await this.googleAccessToken()}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    if (!res.ok && res.status !== 409) this.log.error(`acknowledge failed ${res.status} for ${productId}`);
  }
}
