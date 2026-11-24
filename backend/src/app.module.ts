import { BullModule } from '@nestjs/bullmq';
import { Controller, Get, Inject, MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { ApiTags } from '@nestjs/swagger';
import Redis from 'ioredis';
import { ENV, Env } from './config/env';
import { AllExceptionsFilter, AuthGuard, Public, RequestContextMiddleware } from './common/http';
import { InfraModule, PrismaService, REDIS } from './common/infra';
import { AdminModule } from './modules/admin/admin.module';
import { AuthModule } from './modules/auth/auth.module';
import { MatchingModule } from './modules/matching/matching.module';
import { MediaModule } from './modules/media/media.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { ConsultationsModule } from './modules/consultations/consultations.module';
import { IntegrityModule } from './modules/integrity/integrity.module';
import { SubscriptionsModule } from './modules/subscriptions/subscriptions.module';
import { WalletModule } from './modules/wallet/wallet.module';
import { MessagingModule } from './modules/messaging/messaging.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { ProfilesModule } from './modules/profiles/profiles.module';
import { QuotasModule } from './modules/quotas/quotas.module';
import { SafetyModule } from './modules/safety/safety.module';
import { VerificationModule } from './modules/verification/verification.module';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private readonly prisma: PrismaService, @Inject(REDIS) private readonly redis: Redis) {}

  @Public() @Get('live')
  live() {
    return { status: 'ok' };
  }

  @Public() @Get('ready')
  async ready() {
    await this.prisma.$queryRaw`SELECT 1`;
    await this.redis.ping();
    return { status: 'ok' };
  }
}

export const bullConnection = {
  inject: [ENV],
  useFactory: (env: Env) => {
    const u = new URL(env.REDIS_URL);
    return { connection: { host: u.hostname, port: Number(u.port || 6379), password: u.password || undefined, tls: u.protocol === 'rediss:' ? {} : undefined } };
  },
};

@Module({
  imports: [
    InfraModule,
    BullModule.forRootAsync(bullConnection),
    JwtModule.register({}),
    QuotasModule,
    NotificationsModule,
    IntegrityModule,
    AuthModule,
    ProfilesModule,
    MediaModule,
    VerificationModule,
    MatchingModule,
    MessagingModule,
    ConsultationsModule,
    PaymentsModule,
    WalletModule,
    SubscriptionsModule,
    SafetyModule,
    AdminModule,
  ],
  controllers: [HealthController],
  providers: [
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestContextMiddleware).forRoutes('{*splat}');
  }
}
