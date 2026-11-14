import { Body, Controller, Get, HttpCode, Inject, Injectable, Logger, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { ConnectedSocket, MessageBody, OnGatewayConnection, SubscribeMessage, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Type } from 'class-transformer';
import { IsBoolean, IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Max, Min, validateOrReject } from 'class-validator';
import { EventEmitter } from 'node:events';
import type { Server, Socket } from 'socket.io';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode, fromPgError } from '../../common/errors';
import { AuthUser, CurrentUser, RateLimit } from '../../common/http';
import { PrismaService, RateLimiter, SettingsService } from '../../common/infra';
import { profileInclude, toPublicProfile } from '../profiles/profile.mapper';
import { NotificationsService } from '../notifications/notifications.module';
import { EntitlementsService, QuotaService } from '../quotas/quotas.module';

export class SendMessageDto {
  @ApiProperty({ description: 'Client-generated UUID (idempotency key)' }) @IsUUID() clientMessageId: string;
  @ApiProperty() @IsString() @Length(1, 2000) body: string;
}

class ListQuery {
  @ApiPropertyOptional({ enum: ['INBOX', 'ARCHIVE', 'UNMATCHED', 'CONSULTATION'] }) @IsOptional() @IsIn(['INBOX', 'ARCHIVE', 'UNMATCHED', 'CONSULTATION']) section?: string;
}

class RematchResponseDto {
  @ApiProperty() @IsBoolean() accept: boolean;
}

class PageQuery {
  @ApiPropertyOptional() @IsOptional() @IsDateString() before?: string;
  @ApiPropertyOptional({ default: 30 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 30;
}

/** In-process bus between REST/services and the WebSocket gateway. */
@Injectable()
export class ChatEvents extends EventEmitter {}

@Injectable()
export class MessagingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly quotas: QuotaService,
    private readonly entitlements: EntitlementsService,
    private readonly settings: SettingsService,
    private readonly notifications: NotificationsService,
    private readonly events: ChatEvents,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /**
   * Membership + conversation open + no block + not locked by the plan.
   * Match chats: the match must be ACTIVE (after an unmatch the chat is
   * closed until a re-match is accepted — also enforced by a DB trigger).
   * Consultation chats: open while CONFIRMED and for N days after completion.
   */
  async assertCanChat(userId: string, conversationId: string, opts: { forWrite?: boolean } = {}) {
    const c = await this.prisma.conversation.findUnique({
      where: { id: conversationId },
      select: {
        id: true,
        kind: true,
        match: { select: { status: true, userAId: true, userBId: true } },
        consultation: { select: { status: true, completedAt: true, clientId: true, counselorId: true } },
        members: { select: { userId: true } },
      },
    });
    if (!c || !c.members.some((m) => m.userId === userId)) throw new AppError(ErrorCode.NOT_FOUND);
    let peerId: string;
    if (c.kind === 'CONSULTATION') {
      const k = c.consultation!;
      const graceDays = await this.settings.get('consultations.chatOpenDaysAfterCompletion', 7);
      const open = k.status === 'CONFIRMED' || (k.status === 'COMPLETED' && !!k.completedAt && Date.now() - k.completedAt.getTime() < graceDays * 86_400_000);
      if (opts.forWrite && !open) throw new AppError(ErrorCode.CONVERSATION_CLOSED, 'Consultation chat is closed');
      peerId = k.clientId === userId ? k.counselorId : k.clientId;
    } else {
      const m = c.match!;
      if (m.status === 'BLOCKED') throw new AppError(ErrorCode.NOT_FOUND);
      if (opts.forWrite && m.status !== 'ACTIVE') throw new AppError(ErrorCode.CONVERSATION_CLOSED, 'Unmatched — request a re-match first');
      peerId = m.userAId === userId ? m.userBId : m.userAId;
      if (m.status === 'ACTIVE') {
        const row = await this.listRows(userId).then((r) => r.find((x) => x.conversation_id === conversationId));
        if (row?.locked) throw new AppError(ErrorCode.CONVERSATION_LOCKED, 'Upgrade to open more conversations', { feature: 'visibleConversations' });
      }
    }
    const blocked = await this.prisma.blockedUser.findFirst({ where: { OR: [{ blockerId: userId, blockedId: peerId }, { blockerId: peerId, blockedId: userId }] } });
    if (blocked) throw new AppError(ErrorCode.BLOCKED);
    return { peerId, kind: c.kind };
  }

  private async listRows(userId: string) {
    const ent = await this.entitlements.forUser(userId);
    return this.prisma.$queryRaw<{ conversation_id: string; section: 'INBOX' | 'ARCHIVE' | 'UNMATCHED' | 'CONSULTATION'; list_position: number | null; locked: boolean; expires_at: Date | null; warn: boolean }[]>`
      SELECT * FROM olfa_conversation_list(${userId}::uuid, ${ent.visibleConversations}::int)`;
  }

  /**
   * Sections: INBOX · ARCHIVE · UNMATCHED · CONSULTATION. Locked rows (over the
   * plan's limit) carry no peer identity and no message preview.
   */
  async list(userId: string, section?: string) {
    const rows = (await this.listRows(userId)).filter((r) => !section || r.section === section);
    const ids = rows.filter((r) => !r.locked).map((r) => r.conversation_id);
    const convs = await this.prisma.conversation.findMany({
      where: { id: { in: ids } },
      select: {
        id: true,
        kind: true,
        lastMessageAt: true,
        rematch: { select: { requestedBy: true, status: true } },
        match: { select: { userAId: true, endedAt: true, endedBy: true, userA: { include: profileInclude }, userB: { include: profileInclude } } },
        consultation: { select: { id: true, status: true, scheduledAt: true, clientId: true, counselor: { select: { userId: true, displayName: true, kind: true } } } },
        members: { where: { userId }, select: { lastReadAt: true } },
        messages: { where: { deletedAt: null }, orderBy: { createdAt: 'desc' }, take: 1, select: { body: true, senderId: true, createdAt: true } },
      },
    });
    const byId = new Map(convs.map((c) => [c.id, c]));
    return Promise.all(
      rows.map(async (r) => {
        const base = { id: r.conversation_id, section: r.section, locked: r.locked, expiresAt: r.expires_at, expiringSoon: r.warn };
        const c = byId.get(r.conversation_id);
        if (r.locked || !c) return base;
        const lastReadAt = c.members[0]?.lastReadAt;
        const unread = await this.prisma.message.count({ where: { conversationId: c.id, senderId: { not: userId }, deletedAt: null, ...(lastReadAt ? { createdAt: { gt: lastReadAt } } : {}) } });
        const rematch = c.rematch ? { status: c.rematch.status, byMe: c.rematch.requestedBy === userId } : null;
        if (c.kind === 'CONSULTATION') {
          const k = c.consultation!;
          return { ...base, kind: c.kind, unread, lastMessage: c.messages[0] ?? null, lastMessageAt: c.lastMessageAt, consultation: { id: k.id, status: k.status, scheduledAt: k.scheduledAt, counselor: k.clientId === userId ? k.counselor : null } };
        }
        const m = c.match!;
        const peer = m.userAId === userId ? m.userB : m.userA;
        return {
          ...base,
          kind: c.kind,
          unread,
          lastMessage: c.messages[0] ?? null,
          lastMessageAt: c.lastMessageAt,
          unmatchedAt: r.section === 'UNMATCHED' ? m.endedAt : null,
          unmatchedByMe: r.section === 'UNMATCHED' ? m.endedBy === userId : null,
          rematch,
          peer: peer.profile ? toPublicProfile(peer, this.env.CDN_BASE_URL) : null,
        };
      }),
    );
  }

  async setFolder(userId: string, conversationId: string, folder: 'INBOX' | 'ARCHIVE') {
    await this.assertCanChat(userId, conversationId);
    await this.prisma.conversationMember.update({
      where: { conversationId_userId: { conversationId, userId } },
      data: { folder, archivedAt: folder === 'ARCHIVE' ? new Date() : null, retentionAnchorAt: new Date(), expiryWarnedAt: null },
    });
  }

  async unmatch(userId: string, conversationId: string) {
    try {
      await this.prisma.$executeRaw`SELECT olfa_unmatch(${conversationId}::uuid, ${userId}::uuid)`;
    } catch (e) {
      throw fromPgError(e) ?? e;
    }
    const members = await this.prisma.conversationMember.findMany({ where: { conversationId }, select: { userId: true } });
    this.events.emit('conversation', { conversationId, userIds: members.map((m) => m.userId), section: 'UNMATCHED' });
  }

  /** One request per conversation, ever (primary key in rematch_requests). */
  async requestRematch(userId: string, conversationId: string) {
    let peerId: string;
    try {
      [{ peer: peerId }] = await this.prisma.$queryRaw<{ peer: string }[]>`SELECT olfa_request_rematch(${conversationId}::uuid, ${userId}::uuid) AS peer`;
    } catch (e) {
      const err = fromPgError(e);
      if (err?.code === ErrorCode.CONFLICT) throw new AppError(ErrorCode.REMATCH_USED, 'A re-match request was already used in this conversation');
      throw err ?? e;
    }
    await this.notifications.push(peerId, 'push.rematch_request', { conversationId });
    this.events.emit('conversation', { conversationId, userIds: [userId, peerId], section: 'UNMATCHED' });
  }

  async respondRematch(userId: string, conversationId: string, accept: boolean) {
    let status: string;
    try {
      [{ status }] = await this.prisma.$queryRaw<{ status: string }[]>`SELECT olfa_respond_rematch(${conversationId}::uuid, ${userId}::uuid, ${accept}) AS status`;
    } catch (e) {
      throw fromPgError(e) ?? e;
    }
    const members = await this.prisma.conversationMember.findMany({ where: { conversationId }, select: { userId: true } });
    this.events.emit('conversation', { conversationId, userIds: members.map((m) => m.userId), section: accept ? 'INBOX' : 'UNMATCHED' });
    return { status };
  }

  async page(userId: string, conversationId: string, q: PageQuery) {
    await this.assertCanChat(userId, conversationId).catch((e) => {
      if (e instanceof AppError && e.code === ErrorCode.BLOCKED) throw new AppError(ErrorCode.NOT_FOUND);
      throw e;
    });
    const items = await this.prisma.message.findMany({
      where: { conversationId, deletedAt: null, ...(q.before ? { createdAt: { lt: new Date(q.before) } } : {}) },
      orderBy: { createdAt: 'desc' },
      take: q.limit + 1,
      select: { id: true, clientMessageId: true, senderId: true, body: true, type: true, createdAt: true, receipts: { select: { userId: true, deliveredAt: true, readAt: true } } },
    });
    const hasMore = items.length > q.limit;
    return { items: items.slice(0, q.limit).reverse(), hasMore };
  }

  /**
   * Idempotent send. Quota policy (admin-configurable):
   *  - start_only (default): starting a conversation spent the daily credit; each
   *    message counts against a per-conversation anti-spam limit.
   *  - every_message: every message also consumes the daily message quota.
   */
  async send(userId: string, conversationId: string, dto: SendMessageDto) {
    const { peerId, kind } = await this.assertCanChat(userId, conversationId, { forWrite: true });
    const existing = await this.prisma.message.findUnique({
      where: { conversationId_senderId_clientMessageId: { conversationId, senderId: userId, clientMessageId: dto.clientMessageId } },
    });
    if (existing) return existing;

    const body = dto.body.trim();
    if (!body) throw new AppError(ErrorCode.VALIDATION, 'Empty message');
    const policy = await this.settings.get<string>('chat.messagesConsumeCredit', 'start_only');
    const contLimit = await this.settings.get('chat.continuationDailyLimit', 200);

    let msg;
    try {
      msg = await this.prisma.$transaction(async (tx) => {
        // counter key "msg:<conversationId>" fits varchar(40) exactly
        await this.quotas.consume(userId, `msg:${conversationId}`, contLimit, { type: 'message', id: conversationId }, tx);
        // Paid consultation chats never consume dating message credits.
        if (policy === 'every_message' && kind === 'MATCH') {
          const ent = await this.entitlements.forUser(userId);
          await this.quotas.consume(userId, 'messages', ent.dailyMessages, { type: 'message', id: conversationId }, tx);
        }
        const m = await tx.message.create({ data: { conversationId, senderId: userId, clientMessageId: dto.clientMessageId, body } });
        await tx.messageReceipt.create({ data: { messageId: m.id, userId: peerId } });
        await tx.conversation.update({ where: { id: conversationId }, data: { lastMessageAt: m.createdAt } });
        return m;
      });
    } catch (e) {
      const err = fromPgError(e);
      if (err?.code === ErrorCode.CONFLICT) {
        // concurrent retry with the same clientMessageId
        return this.prisma.message.findUniqueOrThrow({ where: { conversationId_senderId_clientMessageId: { conversationId, senderId: userId, clientMessageId: dto.clientMessageId } } });
      }
      throw err ?? e;
    }

    this.events.emit('message', { conversationId, userIds: [userId, peerId], message: msg });
    await this.notifications.push(peerId, 'push.new_message', { conversationId });
    return msg;
  }

  async markRead(userId: string, conversationId: string) {
    await this.assertCanChat(userId, conversationId);
    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.conversationMember.update({ where: { conversationId_userId: { conversationId, userId } }, data: { lastReadAt: now } }),
      this.prisma.messageReceipt.updateMany({ where: { userId, readAt: null, message: { conversationId } }, data: { readAt: now, deliveredAt: now } }),
    ]);
    const c = await this.prisma.conversation.findUniqueOrThrow({ where: { id: conversationId }, select: { members: { select: { userId: true } } } });
    // Respect the reader's read-receipt preference in Phase 4 (privacy settings).
    this.events.emit('read', { conversationId, userIds: c.members.map((m) => m.userId), readerId: userId, at: now });
  }
}

/**
 * Socket.IO gateway (namespace /chat). Auth: { auth: { token } } on connect.
 * Rooms: user:<id>. Horizontal scaling via the Redis adapter (main.ts).
 */
@WebSocketGateway({ namespace: '/chat', cors: { origin: true } })
export class ChatGateway implements OnGatewayConnection {
  @WebSocketServer() server: Server;
  private readonly log = new Logger('ChatGateway');

  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
    private readonly messaging: MessagingService,
    private readonly limiter: RateLimiter,
    events: ChatEvents,
    @Inject(ENV) private readonly env: Env,
  ) {
    events.on('message', (e: { userIds: string[]; message: unknown; conversationId: string }) =>
      e.userIds.forEach((u) => this.server?.to(`user:${u}`).emit('message:new', { conversationId: e.conversationId, message: e.message })),
    );
    events.on('read', (e: { userIds: string[]; conversationId: string; readerId: string; at: Date }) =>
      e.userIds.forEach((u) => this.server?.to(`user:${u}`).emit('message:read', { conversationId: e.conversationId, readerId: e.readerId, at: e.at })),
    );
    // unmatch / re-match / archive moves: clients re-fetch the affected section
    events.on('conversation', (e: { userIds: string[]; conversationId: string; section: string }) =>
      e.userIds.forEach((u) => this.server?.to(`user:${u}`).emit('conversation:moved', { conversationId: e.conversationId, section: e.section })),
    );
  }

  async handleConnection(socket: Socket) {
    try {
      const token = (socket.handshake.auth?.token as string) ?? '';
      const p = await this.jwt.verifyAsync<{ sub: string; sid: string; typ: string }>(token, { secret: this.env.JWT_ACCESS_SECRET });
      const s = await this.prisma.userSession.findUnique({ where: { id: p.sid }, select: { revokedAt: true, user: { select: { status: true } } } });
      if (p.typ !== 'access' || !s || s.revokedAt || !['ACTIVE', 'RESTRICTED'].includes(s.user.status)) throw new Error('unauthorized');
      socket.data.user = { id: p.sub, sessionId: p.sid, status: s.user.status } satisfies AuthUser;
      await socket.join(`user:${p.sub}`);
    } catch {
      socket.emit('error', { code: ErrorCode.UNAUTHORIZED });
      socket.disconnect(true);
    }
  }

  private user(socket: Socket): AuthUser {
    const u = socket.data.user as AuthUser | undefined;
    if (!u) throw new AppError(ErrorCode.UNAUTHORIZED);
    return u;
  }

  @SubscribeMessage('message:send')
  async send(@ConnectedSocket() socket: Socket, @MessageBody() payload: { conversationId: string } & SendMessageDto) {
    const u = this.user(socket);
    try {
      await this.limiter.hit(`ws:send:${u.id}`, 60, 60);
      const dto = Object.assign(new SendMessageDto(), { clientMessageId: payload?.clientMessageId, body: payload?.body });
      await validateOrReject(dto);
      const msg = await this.messaging.send(u.id, payload.conversationId, dto);
      return { ok: true, message: msg };
    } catch (e) {
      const code = e instanceof AppError ? e.code : Array.isArray(e) ? ErrorCode.VALIDATION : ErrorCode.INTERNAL;
      if (code === ErrorCode.INTERNAL) this.log.error(e);
      return { ok: false, error: { code } };
    }
  }

  @SubscribeMessage('typing')
  async typing(@ConnectedSocket() socket: Socket, @MessageBody() payload: { conversationId: string; on: boolean }) {
    const u = this.user(socket);
    try {
      await this.limiter.hit(`ws:typing:${u.id}`, 120, 60);
      const { peerId } = await this.messaging.assertCanChat(u.id, payload.conversationId);
      this.server.to(`user:${peerId}`).emit('typing', { conversationId: payload.conversationId, userId: u.id, on: !!payload.on });
    } catch {
      /* ignore: typing is best-effort */
    }
  }

  @SubscribeMessage('read')
  async read(@ConnectedSocket() socket: Socket, @MessageBody() payload: { conversationId: string }) {
    await this.messaging.markRead(this.user(socket).id, payload.conversationId).catch(() => undefined);
  }
}

@ApiTags('messaging')
@ApiBearerAuth()
@Controller('v1/conversations')
export class MessagingController {
  constructor(private readonly messaging: MessagingService) {}

  /** Sections: INBOX · ARCHIVE · UNMATCHED · CONSULTATION (omit for all). */
  @Get()
  list(@CurrentUser() u: AuthUser, @Query() q: ListQuery) {
    return this.messaging.list(u.id, q.section);
  }

  @Post(':id/archive') @HttpCode(204)
  async archive(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.messaging.setFolder(u.id, id, 'ARCHIVE');
  }

  @Post(':id/restore') @HttpCode(204)
  async restore(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.messaging.setFolder(u.id, id, 'INBOX');
  }

  /** Moves the chat to Unmatched for both people immediately. */
  @RateLimit(20, 3600) @Post(':id/unmatch') @HttpCode(204)
  async unmatch(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.messaging.unmatch(u.id, id);
  }

  @RateLimit(20, 3600) @Post(':id/rematch') @HttpCode(204)
  async rematch(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.messaging.requestRematch(u.id, id);
  }

  @Post(':id/rematch/respond')
  respond(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RematchResponseDto) {
    return this.messaging.respondRematch(u.id, id, dto.accept);
  }

  @Get(':id/messages')
  page(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Query() q: PageQuery) {
    return this.messaging.page(u.id, id, q);
  }

  @RateLimit(120, 60) @Post(':id/messages')
  send(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SendMessageDto) {
    return this.messaging.send(u.id, id, dto);
  }

  @Post(':id/read') @HttpCode(204)
  async read(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.messaging.markRead(u.id, id);
  }
}

@Module({
  imports: [JwtModule.register({})],
  controllers: [MessagingController],
  providers: [MessagingService, ChatGateway, ChatEvents],
})
export class MessagingModule {}
