import { Body, Controller, Delete, Get, HttpCode, Inject, Injectable, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { EducationLevel, MaritalStatus } from '@prisma/client';
import { Transform, Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsEnum, IsInt, IsISO31661Alpha2, IsOptional, IsString, IsUUID, Length, Matches, Max, MaxLength, Min, IsIn } from 'class-validator';
import { monthWindow } from '../../domain/quota-period';
import { privacyOf } from '../../domain/privacy';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode, fromPgError } from '../../common/errors';
import { AllowPending, AuthUser, CurrentUser, RateLimit } from '../../common/http';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { profileInclude, toPublicProfile } from '../profiles/profile.mapper';
import { NotificationsService } from '../notifications/notifications.module';
import { EntitlementsService, QuotaService } from '../quotas/quotas.module';
import { MatchingService } from './matching.service';

import ref from '../../reference/reference.json';

const csv = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.split(',').filter(Boolean) : value);

class DiscoveryQuery {
  @ApiPropertyOptional({ default: 10, maximum: 20 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(20) limit = 10;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(18) @Max(99) ageMin?: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(18) @Max(99) ageMax?: number;
  @ApiPropertyOptional() @IsOptional() @IsISO31661Alpha2() countryCode?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) city?: string;
  @ApiPropertyOptional({ description: 'comma-separated; free plans: one basic interest' }) @IsOptional() @Transform(csv) @IsArray() @ArrayMaxSize(8) @IsString({ each: true }) interests?: string[];
  @ApiPropertyOptional({ enum: MaritalStatus, isArray: true, description: 'paid' }) @IsOptional() @Transform(csv) @IsArray() @IsEnum(MaritalStatus, { each: true }) maritalStatuses?: MaritalStatus[];
  @ApiPropertyOptional({ enum: EducationLevel, isArray: true, description: 'paid' }) @IsOptional() @Transform(csv) @IsArray() @IsEnum(EducationLevel, { each: true }) educations?: EducationLevel[];
  @ApiPropertyOptional({ description: 'paid · occupation key' }) @IsOptional() @IsIn(ref.occupations) occupation?: string;
  @ApiPropertyOptional({ minimum: 120, maximum: 230 }) @IsOptional() @Type(() => Number) @IsInt() @Min(120) @Max(230) heightMin?: number;
  @ApiPropertyOptional({ minimum: 120, maximum: 230 }) @IsOptional() @Type(() => Number) @IsInt() @Min(120) @Max(230) heightMax?: number;
  @ApiPropertyOptional({ minimum: 35, maximum: 250 }) @IsOptional() @Type(() => Number) @IsInt() @Min(35) @Max(250) weightMin?: number;
  @ApiPropertyOptional({ minimum: 35, maximum: 250 }) @IsOptional() @Type(() => Number) @IsInt() @Min(35) @Max(250) weightMax?: number;
  @ApiPropertyOptional({ description: 'paid · nationality ISO code' }) @IsOptional() @IsIn(ref.nationalities) nationality?: string;
  @ApiPropertyOptional({ enum: ['nearest', 'best'], description: 'nearest (default): closest first, then own country' }) @IsOptional() @IsIn(['nearest', 'best']) sort?: 'nearest' | 'best';
  @ApiPropertyOptional({ description: 'paid' }) @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(100) minCompatibility?: number;
}

class TargetDto {
  @ApiProperty() @IsUUID() userId: string;
}

const NO_CONTACT = /^(?![\s\S]*(\+?\d[\d\s]{7,}|@|https?:\/\/|www\.))[\s\S]*$/i;

class LikeDto extends TargetDto {
  /** A compliment travels with the like and is shown to the other person first (monthly quota). */
  @ApiPropertyOptional({ maxLength: 300 }) @IsOptional() @IsString() @Length(2, 300) @Matches(NO_CONTACT, { message: 'contact details are not allowed' }) compliment?: string;
}

class ReceivedQuery {
  @ApiPropertyOptional() @IsOptional() @IsUUID() cursor?: string;
}

@Injectable()
export class LikesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly matching: MatchingService,
    private readonly quotas: QuotaService,
    private readonly entitlements: EntitlementsService,
    private readonly notifications: NotificationsService,
    private readonly settings: SettingsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /**
   * 1 account (SQL) · 2 quota (SQL, atomic) · 3 preferences (engine) ·
   * 4 duplicates (SQL) · 5 save · 6 mutual check · 7 match in the same
   * transaction (pair-locked) · 8 notify both.
   */
  async like(fromId: string, toId: string, compliment?: string) {
    if (fromId === toId) throw new AppError(ErrorCode.VALIDATION);
    const pair = await this.matching.pairCheck(fromId, toId);
    if (!pair.compatible) throw new AppError(ErrorCode.NOT_ELIGIBLE, 'Outside mutual preferences');
    const ent = await this.entitlements.forUser(fromId);
    const w = await this.quotas.window(fromId);

    const text = compliment?.trim() || null;
    let row: { like_id: string; match_id: string | null; likes_remaining: number };
    let complimentsRemaining: number | null = null;
    try {
      row = await this.prisma.$transaction(async (tx) => {
        // The compliment credit and the like succeed or fail together.
        if (text) {
          const tz = (await tx.user.findUniqueOrThrow({ where: { id: fromId }, select: { timezone: true } })).timezone;
          const mw = monthWindow(new Date(), tz);
          complimentsRemaining = await this.quotas.consume(fromId, 'compliments', ent.monthlyCompliments, { type: 'compliment', id: toId }, tx, mw);
        }
        const [r] = await tx.$queryRaw<(typeof row)[]>`
          SELECT like_id, match_id, likes_remaining FROM olfa_like(${fromId}::uuid, ${toId}::uuid, ${w.start}, ${w.end}, ${ent.dailyLikes})`;
        if (text) await tx.like.update({ where: { id: r.like_id }, data: { compliment: text } });
        return r;
      });
    } catch (e) {
      throw fromPgError(e) ?? e;
    }

    if (row.match_id) {
      await this.prisma.match.update({ where: { id: row.match_id }, data: { score: pair.score } });
      await Promise.all([
        this.notifications.notify(fromId, 'NEW_MATCH', 'push.new_match', { matchId: row.match_id }),
        this.notifications.notify(toId, 'NEW_MATCH', 'push.new_match', { matchId: row.match_id }),
      ]);
    } else {
      // The liked person learns *that* someone liked them; identity is gated by plan —
      // except for compliments, which always arrive with the sender.
      if (text) await this.notifications.notify(toId, 'NEW_COMPLIMENT', 'push.new_compliment', { fromUserId: fromId });
      else await this.notifications.notify(toId, 'NEW_LIKE', 'push.new_like');
    }
    return { matched: !!row.match_id, matchId: row.match_id, likesRemaining: row.likes_remaining, complimentsRemaining };
  }

  async pass(fromId: string, toId: string) {
    const days = await this.settings.get('matching.passResurfaceDays', 30);
    const expiresAt = days > 0 ? new Date(Date.now() + days * 86_400_000) : null;
    await this.prisma.$transaction([
      this.prisma.pass.upsert({ where: { fromUserId_toUserId: { fromUserId: fromId, toUserId: toId } }, create: { fromUserId: fromId, toUserId: toId, expiresAt }, update: { expiresAt, createdAt: new Date() } }),
      this.prisma.discoveryHistory.create({ data: { viewerId: fromId, candidateId: toId, action: 'PASSED' } }),
    ]);
  }

  /** Undo the last decision on a profile (plan-limited). Matches cannot be undone this way. */
  async undo(fromId: string, toId: string) {
    const ent = await this.entitlements.forUser(fromId);
    const [a, b] = [fromId, toId].sort();
    const match = await this.prisma.match.findUnique({ where: { userAId_userBId: { userAId: a, userBId: b } } });
    if (match) throw new AppError(ErrorCode.CONFLICT, 'Already matched — use unmatch instead');
    const [like, pass] = await Promise.all([
      this.prisma.like.findUnique({ where: { fromUserId_toUserId: { fromUserId: fromId, toUserId: toId } } }),
      this.prisma.pass.findUnique({ where: { fromUserId_toUserId: { fromUserId: fromId, toUserId: toId } } }),
    ]);
    if (!like && !pass) throw new AppError(ErrorCode.NOT_FOUND);
    await this.prisma.$transaction(async (tx) => {
      await this.quotas.consume(fromId, 'undos', ent.dailyUndos, { type: 'undo', id: toId }, tx);
      if (like) await tx.like.delete({ where: { id: like.id } }); // like quota is not refunded (anti-abuse)
      if (pass) await tx.pass.delete({ where: { id: pass.id } });
    });
  }

  /**
   * Count for everyone; identities only with see_who_liked_you. Compliments
   * are always shown with their sender, first. Cursor-paginated (30 per page).
   */
  async received(userId: string, cursor?: string) {
    const PAGE = 30;
    const ent = await this.entitlements.forUser(userId);
    const viewer = privacyOf(await this.prisma.userPrivacySettings.findUnique({ where: { userId } }));
    const where = {
      toUserId: userId,
      from: { status: 'ACTIVE' as const, deletedAt: null, frozenAt: null, blocksMade: { none: { blockedId: userId } }, blocksReceived: { none: { blockerId: userId } } },
      NOT: { from: { likesReceived: { some: { fromUserId: userId } } } }, // already liked back → it's a match
    };
    const select = { id: true, createdAt: true, compliment: true, from: { include: profileInclude } } as const;
    const [count, compliments] = await Promise.all([
      this.prisma.like.count({ where }),
      cursor ? Promise.resolve([]) : this.prisma.like.findMany({ where: { ...where, compliment: { not: null } }, orderBy: { createdAt: 'desc' }, take: 50, select }),
    ]);
    const view = (l: (typeof compliments)[number]) => ({ likeId: l.id, at: l.createdAt, compliment: l.compliment, profile: toPublicProfile(l.from, this.env.CDN_BASE_URL, { viewer }) });
    const complimentRows = compliments.filter((l) => l.from.profile).map(view);
    if (!ent.seeWhoLikedYou) return { count, compliments: complimentRows, profiles: [], items: [], locked: true, nextCursor: null };
    const likes = await this.prisma.like.findMany({
      where: { ...where, compliment: null },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: PAGE + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      select,
    });
    const page = likes.slice(0, PAGE).filter((l) => l.from.profile).map(view);
    return {
      count,
      compliments: complimentRows,
      items: page,
      profiles: page.map((x) => x.profile), // v1 clients
      locked: false,
      nextCursor: likes.length > PAGE ? likes[PAGE - 1].id : null,
    };
  }
}

@Injectable()
export class MatchesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly quotas: QuotaService,
    private readonly entitlements: EntitlementsService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async list(userId: string) {
    const viewer = privacyOf(await this.prisma.userPrivacySettings.findUnique({ where: { userId } }));
    const matches = await this.prisma.match.findMany({
      where: { status: 'ACTIVE', OR: [{ userAId: userId }, { userBId: userId }] },
      orderBy: { createdAt: 'desc' },
      include: { userA: { include: profileInclude }, userB: { include: profileInclude }, conversation: { select: { id: true, lastMessageAt: true } } },
    });
    return matches
      .map((m) => {
        const peer = m.userAId === userId ? m.userB : m.userA;
        if (peer.status !== 'ACTIVE' || peer.deletedAt || !peer.profile) return null;
        return {
          id: m.id,
          createdAt: m.createdAt,
          score: m.score,
          conversationId: m.conversation?.id ?? null,
          lastMessageAt: m.conversation?.lastMessageAt ?? null,
          paused: !!peer.frozenAt, // the other person took a break
          peer: toPublicProfile(peer, this.env.CDN_BASE_URL, { compatibility: m.score ?? undefined, viewer, matched: true }),
        };
      })
      .filter(Boolean);
  }

  /** Starting a conversation spends one daily credit (atomic, in the same transaction). */
  async startConversation(userId: string, matchId: string) {
    const m = await this.prisma.match.findFirst({ where: { id: matchId, status: 'ACTIVE', OR: [{ userAId: userId }, { userBId: userId }] }, include: { conversation: true } });
    if (!m) throw new AppError(ErrorCode.NOT_FOUND);
    if (m.conversation) return { conversationId: m.conversation.id, created: false };
    const ent = await this.entitlements.forUser(userId);
    try {
      const conv = await this.prisma.$transaction(async (tx) => {
        await this.quotas.consume(userId, 'messages', ent.dailyMessages, { type: 'conversation_start', id: matchId }, tx);
        return tx.conversation.create({
          data: { matchId, startedBy: userId, members: { create: [{ userId: m.userAId }, { userId: m.userBId }] } },
        });
      });
      return { conversationId: conv.id, created: true };
    } catch (e) {
      // Both users pressed "start" at once: the unique match_id makes one win.
      const err = fromPgError(e);
      if (err?.code === ErrorCode.CONFLICT) {
        const existing = await this.prisma.conversation.findUniqueOrThrow({ where: { matchId } });
        return { conversationId: existing.id, created: false };
      }
      throw err ?? e;
    }
  }

  async unmatch(userId: string, matchId: string) {
    // With a conversation: same lifecycle as the chat menu (moves it to Unmatched for both).
    const conv = await this.prisma.conversation.findFirst({ where: { matchId, match: { OR: [{ userAId: userId }, { userBId: userId }] } }, select: { id: true } });
    if (conv) {
      try {
        await this.prisma.$executeRaw`SELECT olfa_unmatch(${conv.id}::uuid, ${userId}::uuid)`;
      } catch (e) {
        throw fromPgError(e) ?? e;
      }
      await this.audit.record({ actorType: 'USER', actorId: userId, action: 'match.unmatch', entityType: 'match', entityId: matchId });
      return;
    }
    const r = await this.prisma.match.updateMany({
      where: { id: matchId, status: 'ACTIVE', OR: [{ userAId: userId }, { userBId: userId }] },
      data: { status: 'UNMATCHED', endedAt: new Date(), endedBy: userId },
    });
    if (r.count === 0) throw new AppError(ErrorCode.NOT_FOUND);
    await this.audit.record({ actorType: 'USER', actorId: userId, action: 'match.unmatch', entityType: 'match', entityId: matchId });
  }
}

@ApiTags('discovery')
@ApiBearerAuth()
@Controller('v1')
export class MatchingController {
  constructor(private readonly matching: MatchingService, private readonly likes: LikesService, private readonly matches: MatchesService) {}

  /** New accounts can browse (read-only) while their profile is reviewed; liking and opening profiles wait for approval. */
  @AllowPending() @RateLimit(120, 3600) @Get('discovery')
  discover(@CurrentUser() u: AuthUser, @Query() q: DiscoveryQuery) {
    return this.matching.discover(u.id, q);
  }

  @RateLimit(300, 3600) @Post('likes') @HttpCode(200)
  like(@CurrentUser() u: AuthUser, @Body() dto: LikeDto) {
    return this.likes.like(u.id, dto.userId, dto.compliment);
  }

  @RateLimit(600, 3600) @Post('passes') @HttpCode(204)
  async pass(@CurrentUser() u: AuthUser, @Body() dto: TargetDto) {
    await this.likes.pass(u.id, dto.userId);
  }

  @Post('undo') @HttpCode(204)
  async undo(@CurrentUser() u: AuthUser, @Body() dto: TargetDto) {
    await this.likes.undo(u.id, dto.userId);
  }

  @Get('likes/received')
  received(@CurrentUser() u: AuthUser, @Query() q: ReceivedQuery) {
    return this.likes.received(u.id, q.cursor);
  }

  @Get('matches')
  list(@CurrentUser() u: AuthUser) {
    return this.matches.list(u.id);
  }

  @Post('matches/:id/conversation') @HttpCode(200)
  start(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.matches.startConversation(u.id, id);
  }

  @Delete('matches/:id') @HttpCode(204)
  async unmatch(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.matches.unmatch(u.id, id);
  }
}

@Module({ controllers: [MatchingController], providers: [MatchingService, LikesService, MatchesService], exports: [MatchingService] })
export class MatchingModule {}
