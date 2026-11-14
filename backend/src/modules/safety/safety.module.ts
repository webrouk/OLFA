import { Body, Controller, Delete, Get, HttpCode, Injectable, Module, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { ReportReason, ReportTarget } from '@prisma/client';
import { IsBoolean, IsEnum, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { AppError, ErrorCode } from '../../common/errors';
import { AllowPending, AuthUser, CurrentUser, RateLimit } from '../../common/http';
import { AuditService, PrismaService } from '../../common/infra';

class BlockDto {
  @ApiProperty() @IsUUID() userId: string;
}

class ReportDto {
  @ApiProperty() @IsUUID() userId: string;
  @ApiProperty({ enum: ReportReason }) @IsEnum(ReportReason) reason: ReportReason;
  @ApiPropertyOptional({ enum: ReportTarget }) @IsOptional() @IsEnum(ReportTarget) targetType?: ReportTarget;
  @ApiPropertyOptional() @IsOptional() @IsUUID() targetId?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) details?: string;
  @ApiPropertyOptional({ default: true }) @IsOptional() @IsBoolean() block?: boolean;
}

const PRIORITY: Partial<Record<ReportReason, number>> = { UNDERAGE: 100, HARASSMENT: 80, SPAM_SCAM: 60, INAPPROPRIATE_PHOTO: 50, FAKE_PROFILE: 40 };

@Injectable()
export class SafetyService {
  constructor(private readonly prisma: PrismaService, private readonly audit: AuditService) {}

  /** Blocking hides both users from each other everywhere and closes their match. */
  async block(userId: string, targetId: string) {
    if (userId === targetId) throw new AppError(ErrorCode.VALIDATION);
    const [a, b] = [userId, targetId].sort();
    await this.prisma.$transaction([
      this.prisma.blockedUser.upsert({ where: { blockerId_blockedId: { blockerId: userId, blockedId: targetId } }, create: { blockerId: userId, blockedId: targetId }, update: {} }),
      this.prisma.match.updateMany({ where: { userAId: a, userBId: b, status: 'ACTIVE' }, data: { status: 'BLOCKED', endedAt: new Date(), endedBy: userId } }),
    ]);
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'user.block', entityType: 'user', entityId: targetId });
  }

  async unblock(userId: string, targetId: string) {
    await this.prisma.blockedUser.deleteMany({ where: { blockerId: userId, blockedId: targetId } });
  }

  list(userId: string) {
    return this.prisma.blockedUser.findMany({
      where: { blockerId: userId },
      select: { createdAt: true, blocked: { select: { id: true, profile: { select: { displayName: true } } } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  /** Reports land in the moderation queue (admin dashboard), prioritised by reason. */
  async report(userId: string, dto: ReportDto) {
    if (userId === dto.userId) throw new AppError(ErrorCode.VALIDATION);
    const target = await this.prisma.user.findUnique({ where: { id: dto.userId }, select: { id: true } });
    if (!target) throw new AppError(ErrorCode.NOT_FOUND);
    const recent = await this.prisma.report.findFirst({ where: { reporterId: userId, reportedUserId: dto.userId, createdAt: { gt: new Date(Date.now() - 86_400_000) } } });
    const report = recent ?? (await this.prisma.report.create({
      data: { reporterId: userId, reportedUserId: dto.userId, reason: dto.reason, targetType: dto.targetType ?? 'USER', targetId: dto.targetId, details: dto.details, priority: PRIORITY[dto.reason] ?? 10 },
    }));
    if (dto.block ?? true) await this.block(userId, dto.userId);
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'report.create', entityType: 'user', entityId: dto.userId, after: { reason: dto.reason, reportId: report.id } });
    return { reportId: report.id, blocked: dto.block ?? true };
  }
}

@ApiTags('safety')
@ApiBearerAuth()
@Controller('v1')
export class SafetyController {
  constructor(private readonly safety: SafetyService) {}

  @AllowPending() @Get('blocks')
  list(@CurrentUser() u: AuthUser) {
    return this.safety.list(u.id);
  }

  @AllowPending() @RateLimit(60, 3600) @Post('blocks') @HttpCode(204)
  async block(@CurrentUser() u: AuthUser, @Body() dto: BlockDto) {
    await this.safety.block(u.id, dto.userId);
  }

  @AllowPending() @Delete('blocks/:userId') @HttpCode(204)
  async unblock(@CurrentUser() u: AuthUser, @Param('userId', ParseUUIDPipe) id: string) {
    await this.safety.unblock(u.id, id);
  }

  @AllowPending() @RateLimit(20, 3600) @Post('reports')
  report(@CurrentUser() u: AuthUser, @Body() dto: ReportDto) {
    return this.safety.report(u.id, dto);
  }
}

@Module({ controllers: [SafetyController], providers: [SafetyService] })
export class SafetyModule {}
