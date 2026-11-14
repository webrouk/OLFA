import { Inject, Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { verifyStripeSignature } from '../../domain/payments';

export interface PaymentIntent {
  providerPaymentId: string;
  /** Handed to the app's payment sheet; null for the test provider. */
  clientSecret: string | null;
}

export type PaymentEvent =
  | { type: 'succeeded'; providerPaymentId: string; amountMinor: number; currency: string }
  | { type: 'failed'; providerPaymentId: string }
  | { type: 'refunded'; providerPaymentId: string }
  | { type: 'ignored' };

/** Port for the web payment provider. Amounts are integer minor units. */
export interface PaymentGateway {
  readonly name: 'stripe' | 'test';
  createIntent(p: { amountMinor: number; currency: string; consultationId: string; userId: string }): Promise<PaymentIntent>;
  refund(providerPaymentId: string): Promise<void>;
  /** Verifies the signature; throws UNAUTHORIZED on a forged payload. */
  parseWebhook(rawBody: string, signature: string | undefined): PaymentEvent;
}

export const PAYMENT_GATEWAY = Symbol('PAYMENT_GATEWAY');

/** Stripe REST over fetch (no SDK). */
@Injectable()
export class StripeGateway implements PaymentGateway {
  readonly name = 'stripe' as const;
  private readonly log = new Logger('Stripe');
  constructor(@Inject(ENV) private readonly env: Env) {}

  private async call<T>(path: string, form: Record<string, string>, idempotencyKey: string): Promise<T> {
    const r = await fetch(`https://api.stripe.com/v1/${path}`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.env.STRIPE_SECRET_KEY}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Idempotency-Key': idempotencyKey,
      },
      body: new URLSearchParams(form).toString(),
    });
    const body = (await r.json()) as T & { error?: { message?: string } };
    if (!r.ok) {
      this.log.error(`Stripe ${path} failed: ${r.status} ${body.error?.message ?? ''}`);
      throw new AppError(ErrorCode.INTERNAL, 'Payment provider error');
    }
    return body;
  }

  async createIntent(p: { amountMinor: number; currency: string; consultationId: string; userId: string }): Promise<PaymentIntent> {
    const pi = await this.call<{ id: string; client_secret: string }>(
      'payment_intents',
      {
        amount: String(p.amountMinor),
        currency: p.currency.toLowerCase(),
        'automatic_payment_methods[enabled]': 'true',
        'metadata[consultation_id]': p.consultationId,
        'metadata[user_id]': p.userId,
      },
      `pi-${p.consultationId}`, // one intent per booking, even on retries
    );
    return { providerPaymentId: pi.id, clientSecret: pi.client_secret };
  }

  async refund(providerPaymentId: string) {
    await this.call('refunds', { payment_intent: providerPaymentId }, `refund-${providerPaymentId}`);
  }

  parseWebhook(rawBody: string, signature: string | undefined): PaymentEvent {
    if (!verifyStripeSignature(rawBody, signature, this.env.STRIPE_WEBHOOK_SECRET ?? '', Math.floor(Date.now() / 1000))) {
      throw new AppError(ErrorCode.UNAUTHORIZED, 'Invalid webhook signature');
    }
    const evt = JSON.parse(rawBody) as { type: string; data: { object: { id: string; amount_received?: number; currency?: string; payment_intent?: string } } };
    const o = evt.data.object;
    switch (evt.type) {
      case 'payment_intent.succeeded':
        return { type: 'succeeded', providerPaymentId: o.id, amountMinor: o.amount_received ?? 0, currency: (o.currency ?? '').toUpperCase() };
      case 'payment_intent.payment_failed':
        return { type: 'failed', providerPaymentId: o.id };
      case 'charge.refunded':
        return o.payment_intent ? { type: 'refunded', providerPaymentId: o.payment_intent } : { type: 'ignored' };
      default:
        return { type: 'ignored' };
    }
  }
}

/** Development/staging only (refused in production by env validation). */
@Injectable()
export class TestGateway implements PaymentGateway {
  readonly name = 'test' as const;
  async createIntent(): Promise<PaymentIntent> {
    return { providerPaymentId: `test_${randomUUID()}`, clientSecret: null };
  }
  async refund() {}
  parseWebhook(): PaymentEvent {
    throw new AppError(ErrorCode.NOT_FOUND);
  }
}
