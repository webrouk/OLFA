import { Body, Controller, Delete, Get, HttpCode, Inject, Injectable, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { PayoutMethodKind, WithdrawalStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsBoolean, IsEnum, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Max, MaxLength, Min } from 'class-validator';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode, fromPgError } from '../../common/errors';
import { AuthAdmin, AuthUser, CurrentAdmin, CurrentUser, ProfessionalsOnly, RateLimit, RequirePermissions } from '../../common/http';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { currencyExponent, SUPPORTED_CURRENCIES } from '../../domain/payments';
import { maskPayout, open, PayoutDetails, payoutFingerprint, seal, validatePayout } from '../../domain/payout';
import ref from '../../reference/reference.json';
import { BansService } from '../integrity/integrity.module';
import { NotificationsService } from '../notifications/notifications.module';

class PayoutMethodDto {
  @ApiProperty({ enum: PayoutMethodKind }) @IsEnum(PayoutMethodKind) kind: PayoutMethodKind;
  @ApiProperty() @IsString() @Length(3, 120) holderName: string;
  @ApiProperty() @IsIn(ref.countries) countryCode: string;
  @ApiProperty({ enum: SUPPORTED_CURRENCIES }) @IsIn(SUPPORTED_CURRENCIES) currency: string;
  @ApiPropertyOptional({ description: 'BANK_IBAN' }) @IsOptional() @IsString() @MaxLength(42) iban?: string;
  @ApiPropertyOptional({ description: 'BANK_SWIFT' }) @IsOptional() @IsString() @MaxLength(40) accountNumber?: string;
  @ApiPropertyOptional({ description: 'BANK_SWIFT' }) @IsOptional() @IsString() @MaxLength(11) bic?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(120) bankName?: string;
  @ApiPropertyOptional({ description: 'WISE / PAYPAL / PAYONEER' }) @IsOptional() @IsString() @MaxLength(254) email?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() makeDefault?: boolean;
}

class WithdrawDto {
  @ApiProperty() @IsUUID() payoutMethodId: string;
  @ApiProperty({ enum: SUPPORTED_CURRENCIES }) @IsIn(SUPPORTED_CURRENCIES) currency: string;
  @ApiProperty({ description: 'Integer minor units' }) @Type(() => Number) @IsInt() @Min(1) @Max(100_000_000) amountMinor: number;
}

class EntriesQuery {
  @ApiPropertyOptional() @IsOptional() @IsString() cursor?: string;
  @ApiPropertyOptional({ enum: SUPPORTED_CURRENCIES }) @IsOptional() @IsIn(SUPPORTED_CURRENCIES) currency?: string;
}

class AdminWithdrawalsQuery {
  @ApiPropertyOptional({ enum: WithdrawalStatus }) @IsOptional() @IsEnum(WithdrawalStatus) status?: WithdrawalStatus;
}
class PaidDto {
  @ApiProperty({ description: 'Bank / provider transfer reference' }) @IsString() @Length(3, 120) providerRef: string;
}
class ReasonDto {
  @ApiProperty() @IsString() @Length(5, 300) reason: string;
}
class AdjustDto {
  @ApiProperty({ enum: SUPPORTED_CURRENCIES }) @IsIn(SUPPORTED_CURRENCIES) currency: string;
  @ApiProperty() @Type(() => Number) @IsInt() @Min(-100_000_000) @Max(100_000_000) amountMinor: number;
  @ApiProperty() @IsString() @Length(5, 200) memo: string;
}

const PAGE = 30;

/**
 * Counselor wallet. Every consultation the client pays is split when paid:
 * 15% platform commission (development, marketing, advertising and promoting
 * the professional) and the counselor's net share. The net share is credited
 * when the session is completed and becomes withdrawable after the hold period.
 * Payouts go to a bank account (IBAN / SWIFT) or Wise / PayPal / Payoneer and
 * are executed by the finance team; the ledger lives in the database
 * (append-only, balance enforced by triggers).
 */
@Injectable()
export class WalletService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
    private readonly bans: BansService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  private key(): Buffer {
    if (!this.env.PAYOUT_ENC_KEY) throw new AppError(ErrorCode.INTERNAL, 'Payouts are not configured');
    return Buffer.from(this.env.PAYOUT_ENC_KEY, 'base64');
  }
  private fpSecret() {
    return this.env.IDENTITY_HMAC_SECRET ?? `payout:${this.env.OTP_HMAC_SECRET}`;
  }

  private async counselor(userId: string) {
    const c = await this.prisma.counselorProfile.findUnique({ where: { userId }, select: { status: true } });
    if (!c) throw new AppError(ErrorCode.NOT_FOUND, 'Not a counselor');
    return c;
  }

  async summary(userId: string) {
    await this.counselor(userId);
    const now = new Date();
    const [inWallet, inEscrow] = await Promise.all([
      this.prisma.walletEntry.groupBy({ by: ['currency'], where: { counselorId: userId } }),
      this.prisma.consultation.groupBy({ by: ['currency'], where: { counselorId: userId, escrowStatus: { in: ['HELD', 'DISPUTED'] } } }),
    ]);
    const currencies = [...new Set([...inWallet, ...inEscrow].map((c) => c.currency))].map((currency) => ({ currency }));
    const balances = await Promise.all(
      currencies.map(async ({ currency }) => {
        const [b] = await this.prisma.$queryRaw<{ available_minor: bigint; pending_minor: bigint }[]>`SELECT * FROM olfa_wallet_balance(${userId}::uuid, ${currency}::char(3), ${now})`;
        // Escrow: paid by the client, released only after the client confirms the session and rates it.
        const escrow = await this.prisma.consultation.groupBy({
          by: ['escrowStatus'],
          where: { counselorId: userId, currency, escrowStatus: { in: ['HELD', 'DISPUTED'] } },
          _sum: { counselorNetMinor: true },
          _count: { _all: true },
        });
        const held = escrow.find((e) => e.escrowStatus === 'HELD');
        const disputed = escrow.find((e) => e.escrowStatus === 'DISPUTED');
        const agg = await this.prisma.consultation.aggregate({
          where: { counselorId: userId, currency, status: 'COMPLETED' },
          _sum: { priceMinor: true, platformFeeMinor: true, counselorNetMinor: true },
          _count: true,
        });
        const withdrawn = await this.prisma.withdrawal.aggregate({ where: { counselorId: userId, currency, status: 'PAID' }, _sum: { amountMinor: true } });
        return {
          currency,
          availableMinor: Number(b.available_minor),
          pendingMinor: Number(b.pending_minor),
          heldMinor: held?._sum.counselorNetMinor ?? 0,
          heldSessions: held?._count._all ?? 0,
          disputedMinor: disputed?._sum.counselorNetMinor ?? 0,
          disputedSessions: disputed?._count._all ?? 0,
          completedSessions: agg._count,
          grossMinor: agg._sum.priceMinor ?? 0,
          platformFeeMinor: agg._sum.platformFeeMinor ?? 0,
          netEarnedMinor: agg._sum.counselorNetMinor ?? 0,
          withdrawnMinor: withdrawn._sum.amountMinor ?? 0,
        };
      }),
    );
    const minMajor = await this.settings.get('wallet.minWithdrawalMajor', 50);
    const openWithdrawals = await this.prisma.withdrawal.findMany({ where: { counselorId: userId, status: { in: ['REQUESTED', 'PROCESSING'] } }, select: { id: true, amountMinor: true, currency: true, status: true, requestedAt: true } });
    const caseOpen = !!(await this.prisma.counselorIntegrityCase.findFirst({ where: { counselorId: userId, status: { in: ['OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW'] } }, select: { id: true } }));
    return {
      commissionPercent: await this.settings.get('consultations.platformFeePercent', 15),
      commissionPurpose: ['platform_development', 'marketing', 'advertising', 'promoting_you'],
      holdDays: await this.settings.get('wallet.holdDays', 0),
      escrowAutoReleaseDays: await this.settings.get('escrow.autoReleaseDays', 0),
      minimums: Object.fromEntries(balances.map((b) => [b.currency, minMajor * 10 ** currencyExponent(b.currency)])),
      balances,
      openWithdrawals,
      payoutsOnHold: caseOpen,
    };
  }

  async entries(userId: string, q: EntriesQuery) {
    const rows = await this.prisma.walletEntry.findMany({
      where: { counselorId: userId, currency: q.currency },
      orderBy: { id: 'desc' },
      take: PAGE + 1,
      ...(q.cursor ? { cursor: { id: BigInt(q.cursor) }, skip: 1 } : {}),
      select: {
        id: true, kind: true, amountMinor: true, currency: true, availableAt: true, createdAt: true, memo: true, withdrawalId: true,
        consultation: { select: { id: true, service: true, durationMinutes: true, priceMinor: true, platformFeePercent: true, platformFeeMinor: true, counselorNetMinor: true, completedAt: true } },
      },
    });
    const more = rows.length > PAGE;
    const items = rows.slice(0, PAGE).map((r) => ({ ...r, id: r.id.toString(), pending: r.amountMinor > 0 && r.availableAt > new Date() }));
    return { items, nextCursor: more ? items[PAGE - 1].id : null };
  }

  // ── payout methods ──

  async methods(userId: string) {
    return this.prisma.payoutMethod.findMany({
      where: { counselorId: userId, deletedAt: null },
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'desc' }],
      select: { id: true, kind: true, holderName: true, countryCode: true, currency: true, detailsMask: true, isDefault: true, createdAt: true },
    });
  }

  async addMethod(userId: string, dto: PayoutMethodDto) {
    const c = await this.counselor(userId);
    if (c.status !== 'APPROVED') throw new AppError(ErrorCode.FORBIDDEN, 'Available once your profile is approved');
    const d: PayoutDetails = { kind: dto.kind, holderName: dto.holderName.trim(), iban: dto.iban, accountNumber: dto.accountNumber, bic: dto.bic, bankName: dto.bankName, email: dto.email };
    const bad = validatePayout(d);
    if (bad) throw new AppError(ErrorCode.VALIDATION, `Invalid ${bad}`, { field: bad });
    const fingerprint = payoutFingerprint(this.fpSecret(), d);
    // An account that received payouts for a banned counselor cannot be added again.
    await this.bans.assertNotBanned('PAYOUT', fingerprint, true);
    const count = await this.prisma.payoutMethod.count({ where: { counselorId: userId, deletedAt: null } });
    if (count >= 5) throw new AppError(ErrorCode.VALIDATION, 'Up to 5 payout methods');
    const makeDefault = dto.makeDefault || count === 0;
    const row = await this.prisma
      .$transaction(async (tx) => {
        if (makeDefault) await tx.payoutMethod.updateMany({ where: { counselorId: userId, isDefault: true }, data: { isDefault: false } });
        return tx.payoutMethod.create({
          data: {
            counselorId: userId, kind: dto.kind, holderName: d.holderName, countryCode: dto.countryCode, currency: dto.currency,
            detailsEnc: seal(this.key(), JSON.stringify(d)), detailsMask: maskPayout(d), fingerprint, isDefault: makeDefault,
          },
          select: { id: true, kind: true, holderName: true, countryCode: true, currency: true, detailsMask: true, isDefault: true, createdAt: true },
        });
      })
      .catch((e: unknown) => {
        const err = fromPgError(e);
        if (err?.code === ErrorCode.CONFLICT) throw new AppError(ErrorCode.CONFLICT, 'This account is already saved');
        throw err ?? e;
      });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'wallet.payout_method_add', entityType: 'payout_method', entityId: row.id, after: { kind: row.kind, mask: row.detailsMask } });
    return row;
  }

  async removeMethod(userId: string, id: string) {
    const open = await this.prisma.withdrawal.count({ where: { payoutMethodId: id, status: { in: ['REQUESTED', 'PROCESSING'] } } });
    if (open) throw new AppError(ErrorCode.INVALID_STATE, 'A withdrawal to this account is in progress');
    const r = await this.prisma.payoutMethod.updateMany({ where: { id, counselorId: userId, deletedAt: null }, data: { deletedAt: new Date(), isDefault: false } });
    if (!r.count) throw new AppError(ErrorCode.NOT_FOUND);
  }

  // ── withdrawals ──

  async withdraw(userId: string, dto: WithdrawDto) {
    const c = await this.counselor(userId);
    if (c.status !== 'APPROVED') throw new AppError(ErrorCode.FORBIDDEN, 'Withdrawals are paused for this account');
    const minMajor = await this.settings.get('wallet.minWithdrawalMajor', 50);
    const min = minMajor * 10 ** currencyExponent(dto.currency);
    if (dto.amountMinor < min) throw new AppError(ErrorCode.VALIDATION, 'Below the minimum withdrawal', { field: 'amountMinor', minimumMinor: min });
    // DB: method ownership, one open request per currency, balance ≥ amount (advisory lock).
    const w = await this.prisma.withdrawal
      .create({ data: { counselorId: userId, payoutMethodId: dto.payoutMethodId, amountMinor: dto.amountMinor, currency: dto.currency } })
      .catch((e: unknown) => {
        const err = fromPgError(e);
        if (err?.code === ErrorCode.CONFLICT) throw new AppError(ErrorCode.CONFLICT, 'You already have a withdrawal in progress for this currency');
        throw err ?? e;
      });
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'wallet.withdraw', entityType: 'withdrawal', entityId: w.id, after: { amountMinor: w.amountMinor, currency: w.currency } });
    return w;
  }

  withdrawals(userId: string) {
    return this.prisma.withdrawal.findMany({
      where: { counselorId: userId },
      orderBy: { requestedAt: 'desc' },
      take: 50,
      select: { id: true, amountMinor: true, currency: true, status: true, requestedAt: true, processedAt: true, providerRef: true, failureReason: true, payoutMethod: { select: { kind: true, detailsMask: true } } },
    });
  }

  async cancel(userId: string, id: string) {
    const r = await this.prisma.withdrawal.updateMany({ where: { id, counselorId: userId, status: 'REQUESTED' }, data: { status: 'CANCELLED' } });
    if (!r.count) throw new AppError(ErrorCode.INVALID_STATE, 'Only a request that is not being processed can be cancelled');
    return { id, status: 'CANCELLED' };
  }

  // ── admin (finance) ──

  adminList(status?: WithdrawalStatus) {
    return this.prisma.withdrawal.findMany({
      where: { status: status ?? { in: ['REQUESTED', 'PROCESSING'] } },
      orderBy: { requestedAt: 'asc' },
      take: 200,
      include: {
        payoutMethod: { select: { kind: true, detailsMask: true, countryCode: true, currency: true, holderName: true } },
        counselor: { select: { displayName: true, status: true, integrityCases: { where: { status: { in: ['OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW'] } }, select: { id: true } } } },
      },
    });
  }

  /** Full destination details for executing the transfer — audited every time. */
  async adminReveal(admin: AuthAdmin, id: string) {
    const w = await this.prisma.withdrawal.findUnique({ where: { id }, include: { payoutMethod: true } });
    if (!w) throw new AppError(ErrorCode.NOT_FOUND);
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'wallet.reveal_payout_details', entityType: 'withdrawal', entityId: id });
    const { detailsEnc, fingerprint, ...pm } = w.payoutMethod;
    void fingerprint;
    return { ...w, payoutMethod: { ...pm, details: JSON.parse(open(this.key(), Buffer.from(detailsEnc))) as PayoutDetails } };
  }

  async adminTransition(admin: AuthAdmin, id: string, to: 'PROCESSING' | 'PAID' | 'REJECTED' | 'FAILED', extra: { providerRef?: string; reason?: string } = {}) {
    const w = await this.prisma.withdrawal.findUnique({ where: { id }, select: { counselorId: true, status: true } });
    if (!w) throw new AppError(ErrorCode.NOT_FOUND);
    if (to === 'PROCESSING') {
      const caseOpen = await this.prisma.counselorIntegrityCase.findFirst({ where: { counselorId: w.counselorId, status: { in: ['OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW'] } }, select: { id: true } });
      if (caseOpen) throw new AppError(ErrorCode.INVALID_STATE, 'Payout on hold while an integrity review is open');
    }
    await this.prisma.withdrawal
      .update({ where: { id }, data: { status: to, processedBy: admin.id, providerRef: extra.providerRef, failureReason: extra.reason } })
      .catch((e: unknown) => {
        throw fromPgError(e) ?? e;
      });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: `wallet.withdrawal_${to.toLowerCase()}`, entityType: 'withdrawal', entityId: id, before: { status: w.status }, reason: extra.reason });
    if (to === 'PAID') await this.notifications.notify(w.counselorId, 'WITHDRAWAL_UPDATE', 'push.withdrawal_paid', { withdrawalId: id });
    if (to === 'REJECTED' || to === 'FAILED') await this.notifications.notify(w.counselorId, 'WITHDRAWAL_UPDATE', 'push.withdrawal_rejected', { withdrawalId: id });
    return this.prisma.withdrawal.findUnique({ where: { id } });
  }

  async adjust(admin: AuthAdmin, counselorId: string, dto: AdjustDto) {
    if (dto.amountMinor === 0) throw new AppError(ErrorCode.VALIDATION, 'Amount cannot be zero');
    const e = await this.prisma.walletEntry.create({ data: { counselorId, currency: dto.currency, kind: 'ADJUSTMENT', amountMinor: dto.amountMinor, memo: dto.memo, createdBy: admin.id } });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'wallet.adjust', entityType: 'counselor', entityId: counselorId, after: { amountMinor: dto.amountMinor, currency: dto.currency }, reason: dto.memo });
    return { ...e, id: e.id.toString() };
  }
}

@ApiTags('wallet')
@ApiBearerAuth()
@ProfessionalsOnly()
@Controller('v1/wallet')
export class WalletController {
  constructor(private readonly wallet: WalletService) {}

  @Get()
  summary(@CurrentUser() u: AuthUser) {
    return this.wallet.summary(u.id);
  }
  @Get('entries')
  entries(@CurrentUser() u: AuthUser, @Query() q: EntriesQuery) {
    return this.wallet.entries(u.id, q);
  }
  @Get('payout-methods')
  methods(@CurrentUser() u: AuthUser) {
    return this.wallet.methods(u.id);
  }
  @RateLimit(10, 86400) @Post('payout-methods')
  add(@CurrentUser() u: AuthUser, @Body() dto: PayoutMethodDto) {
    return this.wallet.addMethod(u.id, dto);
  }
  @Delete('payout-methods/:id') @HttpCode(204)
  async remove(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.wallet.removeMethod(u.id, id);
  }
  @RateLimit(10, 86400) @Post('withdrawals')
  withdraw(@CurrentUser() u: AuthUser, @Body() dto: WithdrawDto) {
    return this.wallet.withdraw(u.id, dto);
  }
  @Get('withdrawals')
  withdrawals(@CurrentUser() u: AuthUser) {
    return this.wallet.withdrawals(u.id);
  }
  @Post('withdrawals/:id/cancel') @HttpCode(200)
  cancel(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.wallet.cancel(u.id, id);
  }
}

@ApiTags('admin')
@ApiBearerAuth()
@Controller('v1/admin')
export class WalletAdminController {
  constructor(private readonly wallet: WalletService) {}

  @RequirePermissions('payouts.manage') @Get('withdrawals')
  list(@Query() q: AdminWithdrawalsQuery) {
    return this.wallet.adminList(q.status);
  }
  @RequirePermissions('payouts.manage') @Get('withdrawals/:id')
  reveal(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string) {
    return this.wallet.adminReveal(a, id);
  }
  @RequirePermissions('payouts.manage') @Post('withdrawals/:id/processing') @HttpCode(200)
  processing(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string) {
    return this.wallet.adminTransition(a, id, 'PROCESSING');
  }
  @RequirePermissions('payouts.manage') @Post('withdrawals/:id/paid') @HttpCode(200)
  paid(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: PaidDto) {
    return this.wallet.adminTransition(a, id, 'PAID', { providerRef: dto.providerRef });
  }
  @RequirePermissions('payouts.manage') @Post('withdrawals/:id/reject') @HttpCode(200)
  reject(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReasonDto) {
    return this.wallet.adminTransition(a, id, 'REJECTED', { reason: dto.reason });
  }
  @RequirePermissions('payouts.manage') @Post('withdrawals/:id/failed') @HttpCode(200)
  failed(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReasonDto) {
    return this.wallet.adminTransition(a, id, 'FAILED', { reason: dto.reason });
  }
  @RequirePermissions('payouts.manage') @Post('wallets/:counselorId/adjust') @HttpCode(200)
  adjust(@CurrentAdmin() a: AuthAdmin, @Param('counselorId', ParseUUIDPipe) id: string, @Body() dto: AdjustDto) {
    return this.wallet.adjust(a, id, dto);
  }
}

@Module({ controllers: [WalletController, WalletAdminController], providers: [WalletService] })
export class WalletModule {}
