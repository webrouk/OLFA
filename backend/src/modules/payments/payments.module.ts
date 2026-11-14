import { Controller, Get, Injectable, Module, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { AllowPending, AuthUser, CurrentUser } from '../../common/http';
import { PrismaService } from '../../common/infra';

class PaymentsQuery {
  @ApiPropertyOptional({ enum: ['SUBSCRIPTION', 'CONSULTATION'] }) @IsOptional() @IsIn(['SUBSCRIPTION', 'CONSULTATION']) kind?: 'SUBSCRIPTION' | 'CONSULTATION';
  @ApiPropertyOptional() @IsOptional() @IsUUID() cursor?: string;
}

const PAGE = 30;

/**
 * Payment history for the member: store subscriptions (App Store / Google
 * Play) and consultation payments (web). Amounts are integer minor units;
 * full card details never reach us.
 */
@Injectable()
export class PaymentsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(userId: string, q: PaymentsQuery) {
    const rows = await this.prisma.payment.findMany({
      where: {
        userId,
        ...(q.kind === 'SUBSCRIPTION' ? { subscriptionId: { not: null } } : {}),
        ...(q.kind === 'CONSULTATION' ? { consultationId: { not: null } } : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: PAGE + 1,
      ...(q.cursor ? { cursor: { id: q.cursor }, skip: 1 } : {}),
      select: {
        id: true,
        provider: true,
        providerPaymentId: true,
        amountMinor: true,
        currency: true,
        status: true,
        createdAt: true,
        refundedAt: true,
        subscription: { select: { status: true, expiresAt: true, plan: { select: { code: true, nameAr: true, nameEn: true } } } },
        consultation: { select: { id: true, service: true, durationMinutes: true, status: true, counselor: { select: { displayName: true } } } },
      },
    });
    const items = rows.slice(0, PAGE).map((p) => ({
      id: p.id,
      kind: p.consultation ? 'CONSULTATION' : 'SUBSCRIPTION',
      provider: p.provider,
      // receipt reference shown to the member for support requests (no secrets)
      reference: p.providerPaymentId.slice(-12),
      amountMinor: p.amountMinor,
      currency: p.currency,
      status: p.status,
      createdAt: p.createdAt,
      refundedAt: p.refundedAt,
      subscription: p.subscription ? { plan: p.subscription.plan, status: p.subscription.status, expiresAt: p.subscription.expiresAt } : null,
      consultation: p.consultation
        ? { id: p.consultation.id, service: p.consultation.service, durationMinutes: p.consultation.durationMinutes, status: p.consultation.status, counselor: p.consultation.counselor.displayName }
        : null,
    }));
    return { items, nextCursor: rows.length > PAGE ? rows[PAGE - 1].id : null };
  }
}

@ApiTags('payments')
@ApiBearerAuth()
@Controller('v1')
export class PaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @AllowPending() @Get('me/payments')
  list(@CurrentUser() u: AuthUser, @Query() q: PaymentsQuery) {
    return this.payments.list(u.id, q);
  }
}

@Module({ controllers: [PaymentsController], providers: [PaymentsService] })
export class PaymentsModule {}
