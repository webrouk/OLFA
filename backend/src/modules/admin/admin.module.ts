import { Body, Controller, Get, HttpCode, Inject, Injectable, Module, Param, ParseEnumPipe, Post, Put } from '@nestjs/common';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { PlanCode, Prisma } from '@prisma/client';
import * as argon2 from 'argon2';
import { IsDateString, IsEmail, IsIn, IsInt, IsObject, IsOptional, IsString, Length, Max, Min } from 'class-validator';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode } from '../../common/errors';
import { AuthAdmin, CurrentAdmin, OlfaRequest, Public, RateLimit, Req, RequirePermissions } from '../../common/http';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { parseWeights } from '../../domain/matching';
import { EntitlementsService } from '../quotas/quotas.module';

class AdminLoginDto {
  @ApiProperty() @IsEmail() email: string;
  @ApiProperty() @IsString() @Length(12, 200) password: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(6, 6) totp?: string;
}

/** Admin panel: close an account permanently, or for a period (until a date). */
class RestrictDto {
  @ApiProperty({ enum: ['ban', 'suspend'] }) @IsIn(['ban', 'suspend']) action!: 'ban' | 'suspend';
  /** Required for 'suspend' with a period; omitted = until lifted by an admin. */
  @ApiPropertyOptional() @IsOptional() @IsDateString() until?: string;
  /** Shown to the user on the closed-account screen. */
  @ApiProperty() @IsString() @Length(3, 300) reason!: string;
}
class UnrestrictDto {
  @ApiProperty() @IsString() @Length(3, 300) reason!: string;
}

class WeightsDto {
  @ApiProperty() @IsInt() @Min(0) @Max(100) interests: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) timeline: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) location: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) lifestyle: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) education: number;
  @ApiProperty() @IsInt() @Min(0) @Max(100) preferenceFit: number;
}

class EntitlementsDto {
  @ApiProperty({ example: { daily_likes: 10, daily_messages: 1, advanced_filters: false } }) @IsObject() values: Record<string, number | boolean>;
}

const FEATURE_KEYS: Record<string, 'number' | 'boolean'> = {
  daily_likes: 'number',
  daily_messages: 'number',
  daily_undos: 'number',
  advanced_filters: 'boolean',
  see_who_liked_you: 'boolean',
  incognito: 'boolean',
  priority_visibility: 'boolean',
};

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly settings: SettingsService,
    private readonly entitlements: EntitlementsService,
    private readonly audit: AuditService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async login(dto: AdminLoginDto, ipHash: string) {
    const admin = await this.prisma.adminUser.findUnique({ where: { email: dto.email.toLowerCase() } });
    // Constant-ish work whether or not the account exists.
    const ok = admin?.isActive ? await argon2.verify(admin.passwordHash, dto.password) : (await argon2.hash(dto.password), false);
    if (!admin || !ok) throw new AppError(ErrorCode.UNAUTHORIZED);
    // TOTP enforcement lands with the admin dashboard (Phase 4); the column already exists.
    await this.prisma.adminUser.update({ where: { id: admin.id }, data: { lastLoginAt: new Date() } });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'admin.login', entityType: 'admin', entityId: admin.id, ipHash });
    return { accessToken: await this.jwt.signAsync({ sub: admin.id, typ: 'admin' }, { secret: this.env.ADMIN_JWT_SECRET, expiresIn: '8h' }) };
  }

  async getWeights() {
    return this.settings.get('matching.weights', {});
  }

  async setWeights(dto: WeightsDto, admin: AuthAdmin) {
    const before = (await this.settings.get<{ version?: number }>('matching.weights', {})) ?? {};
    const next = parseWeights({ ...dto, version: (before.version ?? 0) + 1 });
    await this.settings.set('matching.weights', next as unknown as Prisma.InputJsonValue, admin.id);
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'settings.matching_weights', entityType: 'system_setting', entityId: 'matching.weights', before, after: next });
    return next;
  }

  async plans() {
    return this.prisma.subscriptionPlan.findMany({ orderBy: { sortOrder: 'asc' }, include: { entitlements: { select: { featureKey: true, value: true } } } });
  }

  /** Quota / feature edits apply to all users of the plan within ~30 s, no app update needed. */
  async setEntitlements(code: PlanCode, dto: EntitlementsDto, admin: AuthAdmin) {
    for (const [k, v] of Object.entries(dto.values)) {
      const t = FEATURE_KEYS[k];
      if (!t || typeof v !== t || (t === 'number' && (!Number.isInteger(v) || (v as number) < 0 || (v as number) > 10000))) {
        throw new AppError(ErrorCode.VALIDATION, `Invalid value for ${k}`);
      }
    }
    const plan = await this.prisma.subscriptionPlan.findUniqueOrThrow({ where: { code }, include: { entitlements: true } });
    const before = Object.fromEntries(plan.entitlements.map((e) => [e.featureKey, e.value]));
    await this.prisma.$transaction(
      Object.entries(dto.values).map(([featureKey, value]) =>
        this.prisma.featureEntitlement.upsert({ where: { planId_featureKey: { planId: plan.id, featureKey } }, create: { planId: plan.id, featureKey, value }, update: { value } }),
      ),
    );
    this.entitlements.invalidate();
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'plan.entitlements', entityType: 'subscription_plan', entityId: code, before, after: dto.values });
    return this.plans();
  }

  /** Ban (permanent) or suspend (temporary) — sessions are revoked, the app shows the closed-account screen. */
  async restrict(userId: string, dto: RestrictDto, admin: AuthAdmin) {
    const until = dto.until ? new Date(dto.until) : null;
    if (dto.action === 'suspend' && until && until.getTime() <= Date.now()) throw new AppError(ErrorCode.VALIDATION, 'until must be in the future');
    const before = await this.prisma.user.findUnique({ where: { id: userId }, select: { status: true, suspendedUntil: true } });
    if (!before) throw new AppError(ErrorCode.NOT_FOUND);
    const now = new Date();
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: dto.action === 'ban'
          ? { status: 'BANNED', suspendedUntil: null, restrictionReason: dto.reason, restrictedAt: now }
          : { status: 'SUSPENDED', suspendedUntil: until, restrictionReason: dto.reason, restrictedAt: now },
      });
      await tx.userSession.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: now, revokedReason: `admin_${dto.action}` } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: `user.${dto.action}`, entityType: 'user', entityId: userId, reason: dto.reason, before, after: { until: until?.toISOString() ?? null } }, tx);
    });
    return { userId, status: dto.action === 'ban' ? 'BANNED' : 'SUSPENDED', until: until?.toISOString() ?? null };
  }

  async unrestrict(userId: string, dto: UnrestrictDto, admin: AuthAdmin) {
    const before = await this.prisma.user.findUnique({ where: { id: userId }, select: { status: true } });
    if (!before) throw new AppError(ErrorCode.NOT_FOUND);
    if (before.status !== 'BANNED' && before.status !== 'SUSPENDED') throw new AppError(ErrorCode.INVALID_STATE);
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: userId }, data: { status: 'ACTIVE', suspendedUntil: null, restrictionReason: null, restrictedAt: null } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'user.unrestrict', entityType: 'user', entityId: userId, reason: dto.reason, before }, tx);
    });
    return { userId, status: 'ACTIVE' };
  }

  async setSetting(key: string, value: Prisma.InputJsonValue, admin: AuthAdmin) {
    const known = await this.prisma.systemSetting.findUnique({ where: { key } });
    if (!known) throw new AppError(ErrorCode.NOT_FOUND, 'Unknown setting');
    if (typeof value !== typeof known.value) throw new AppError(ErrorCode.VALIDATION, 'Type must match the current value');
    await this.settings.set(key, value, admin.id);
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'settings.update', entityType: 'system_setting', entityId: key, before: known.value, after: value });
  }

  listSettings() {
    return this.prisma.systemSetting.findMany({ orderBy: { key: 'asc' } });
  }
}

@ApiTags('admin')
@Controller('v1/admin')
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Public() @RateLimit(10, 900) @Post('auth/login') @HttpCode(200)
  login(@Body() dto: AdminLoginDto, @Req() req: OlfaRequest) {
    return this.admin.login(dto, req.ipHash);
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Get('settings')
  settings() {
    return this.admin.listSettings();
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Put('settings/:key') @HttpCode(204)
  async setting(@Param('key') key: string, @Body() body: { value: Prisma.InputJsonValue }, @CurrentAdmin() a: AuthAdmin) {
    await this.admin.setSetting(key, body.value, a);
  }

  @ApiBearerAuth() @RequirePermissions('users.manage') @Post('users/:id/restrict') @HttpCode(200)
  restrict(@Param('id') id: string, @Body() dto: RestrictDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.restrict(id, dto, a);
  }

  @ApiBearerAuth() @RequirePermissions('users.manage') @Post('users/:id/unrestrict') @HttpCode(200)
  unrestrict(@Param('id') id: string, @Body() dto: UnrestrictDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.unrestrict(id, dto, a);
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Get('matching/weights')
  weights() {
    return this.admin.getWeights();
  }

  @ApiBearerAuth() @RequirePermissions('settings.manage') @Put('matching/weights')
  setWeights(@Body() dto: WeightsDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.setWeights(dto, a);
  }

  @ApiBearerAuth() @RequirePermissions('plans.manage') @Get('plans')
  plans() {
    return this.admin.plans();
  }

  @ApiBearerAuth() @RequirePermissions('plans.manage') @Put('plans/:code/entitlements')
  setEntitlements(@Param('code', new ParseEnumPipe(PlanCode)) code: PlanCode, @Body() dto: EntitlementsDto, @CurrentAdmin() a: AuthAdmin) {
    return this.admin.setEntitlements(code, dto, a);
  }
}

@Module({ imports: [JwtModule.register({})], controllers: [AdminController], providers: [AdminService] })
export class AdminModule {}
