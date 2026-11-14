import { Global, Inject, Injectable, Logger, Module, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';
import Redis from 'ioredis';
import { ENV, Env, loadEnv } from '../config/env';
import { AppError, ErrorCode } from './errors';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    await this.$connect();
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
}

export const REDIS = Symbol('REDIS');

/**
 * Fixed-window counter in Redis, atomic via Lua. Used for OTP abuse limits and
 * per-route API rate limits. Returns the remaining budget or throws.
 */
const RATE_LUA = `
local n = redis.call('INCR', KEYS[1])
if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
local ttl = redis.call('TTL', KEYS[1])
return {n, ttl}
`;

@Injectable()
export class RateLimiter {
  constructor(@Inject(REDIS) private readonly redis: Redis) {}

  async hit(key: string, limit: number, windowSeconds: number): Promise<{ remaining: number; retryAfter: number }> {
    const [count, ttl] = (await this.redis.eval(RATE_LUA, 1, `rl:${key}`, String(windowSeconds))) as [number, number];
    if (count > limit) {
      throw new AppError(ErrorCode.RATE_LIMITED, 'Too many requests', { retryAfter: Math.max(ttl, 1) });
    }
    return { remaining: limit - count, retryAfter: ttl };
  }
}

/** system_settings with a short in-memory cache (admin edits apply within 30 s). */
@Injectable()
export class SettingsService {
  private cache = new Map<string, { value: unknown; at: number }>();
  private readonly ttlMs = 30_000;
  constructor(private readonly prisma: PrismaService) {}

  async get<T>(key: string, fallback: T): Promise<T> {
    const hit = this.cache.get(key);
    if (hit && Date.now() - hit.at < this.ttlMs) return hit.value as T;
    const row = await this.prisma.systemSetting.findUnique({ where: { key } });
    const value = (row?.value as T | undefined) ?? fallback;
    this.cache.set(key, { value, at: Date.now() });
    return value;
  }

  async set(key: string, value: Prisma.InputJsonValue, adminId: string) {
    await this.prisma.systemSetting.upsert({
      where: { key },
      create: { key, value, updatedBy: adminId },
      update: { value, updatedBy: adminId },
    });
    this.cache.delete(key);
  }
}

export interface AuditEntry {
  actorType: 'ADMIN' | 'USER' | 'SYSTEM';
  actorId?: string | null;
  action: string;
  entityType: string;
  entityId: string;
  before?: unknown;
  after?: unknown;
  reason?: string;
  ipHash?: string;
  requestId?: string;
}

@Injectable()
export class AuditService {
  private readonly log = new Logger('Audit');
  constructor(private readonly prisma: PrismaService) {}

  async record(e: AuditEntry, tx?: Prisma.TransactionClient) {
    const db = tx ?? this.prisma;
    await db.auditLog.create({
      data: {
        actorType: e.actorType,
        actorId: e.actorId ?? null,
        action: e.action,
        entityType: e.entityType,
        entityId: e.entityId,
        before: (e.before ?? undefined) as Prisma.InputJsonValue | undefined,
        after: (e.after ?? undefined) as Prisma.InputJsonValue | undefined,
        reason: e.reason,
        ipHash: e.ipHash,
        requestId: e.requestId,
      },
    });
    this.log.log(`${e.actorType}:${e.actorId ?? '-'} ${e.action} ${e.entityType}:${e.entityId}`);
  }
}

@Global()
@Module({
  providers: [
    { provide: ENV, useFactory: () => loadEnv() },
    PrismaService,
    {
      provide: REDIS,
      inject: [ENV],
      useFactory: (env: Env) => new Redis(env.REDIS_URL, { maxRetriesPerRequest: 3, enableAutoPipelining: true }),
    },
    RateLimiter,
    SettingsService,
    AuditService,
  ],
  exports: [ENV, PrismaService, REDIS, RateLimiter, SettingsService, AuditService],
})
export class InfraModule {}
