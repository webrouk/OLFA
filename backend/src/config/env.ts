import { z } from 'zod';

/** All configuration comes from the environment and is validated at boot. */
const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().int().default(3000),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  CORS_ORIGINS: z.string().default(''), // comma-separated, e.g. https://admin.olfa.app

  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_ACCESS_TTL_SECONDS: z.coerce.number().int().default(900),
  REFRESH_TTL_DAYS: z.coerce.number().int().default(60),
  ADMIN_JWT_SECRET: z.string().min(32),
  OTP_HMAC_SECRET: z.string().min(32),
  IP_HASH_PEPPER: z.string().min(16),

  SMS_PROVIDER: z.enum(['twilio', 'log']).default('twilio'),
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),
  TWILIO_FROM: z.string().optional(),

  S3_ENDPOINT: z.string().url().optional(), // set for MinIO / R2
  S3_REGION: z.string().default('me-central-1'),
  S3_ACCESS_KEY_ID: z.string(),
  S3_SECRET_ACCESS_KEY: z.string(),
  S3_PRIVATE_BUCKET: z.string(), // originals, never public
  S3_PUBLIC_BUCKET: z.string(), // approved variants only, behind the CDN
  CDN_BASE_URL: z.string().url(),

  MODERATION_PROVIDER: z.enum(['rekognition', 'manual']).default('manual'),
  FCM_CREDENTIALS_JSON: z.string().optional(), // service account JSON
});

export type Env = z.infer<typeof schema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('\n  ');
    throw new Error(`Invalid environment:\n  ${issues}`);
  }
  const env = parsed.data;
  if (env.NODE_ENV === 'production' && env.SMS_PROVIDER === 'log') {
    throw new Error('SMS_PROVIDER=log is not allowed in production');
  }
  if (env.SMS_PROVIDER === 'twilio' && (!env.TWILIO_ACCOUNT_SID || !env.TWILIO_AUTH_TOKEN || !env.TWILIO_FROM)) {
    throw new Error('Twilio credentials are required when SMS_PROVIDER=twilio');
  }
  return env;
}

export const ENV = Symbol('ENV');
