import { Inject, Injectable, Logger } from '@nestjs/common';
import { ENV, Env } from '../../config/env';

export interface SmsProvider {
  send(toE164: string, body: string): Promise<void>;
}
export const SMS_PROVIDER = Symbol('SMS_PROVIDER');

/** Twilio Programmable Messaging over its REST API (no SDK dependency). */
@Injectable()
export class TwilioSmsProvider implements SmsProvider {
  constructor(@Inject(ENV) private readonly env: Env) {}

  async send(to: string, body: string): Promise<void> {
    const sid = this.env.TWILIO_ACCOUNT_SID!;
    const auth = Buffer.from(`${sid}:${this.env.TWILIO_AUTH_TOKEN}`).toString('base64');
    const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
      method: 'POST',
      headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ To: to, From: this.env.TWILIO_FROM!, Body: body }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) throw new Error(`SMS provider error ${res.status}`);
  }
}

/** Development only (refused in production by env validation). Never logs in prod. */
@Injectable()
export class LogSmsProvider implements SmsProvider {
  private readonly log = new Logger('SMS');
  async send(to: string, body: string): Promise<void> {
    this.log.warn(`[dev] SMS to ${to.slice(0, 5)}…: ${body}`);
  }
}
