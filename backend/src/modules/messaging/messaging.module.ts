import { Prisma } from '@prisma/client';
import { Body, Controller, Get, HttpCode, Inject, Injectable, Logger, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { ConnectedSocket, MessageBody, OnGatewayConnection, SubscribeMessage, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayUnique, IsArray, IsBoolean, IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Max, MaxLength, Min, validateOrReject } from 'class-validator';
import { BullModule, InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { randomUUID } from 'node:crypto';
import { containsPhoneNumber } from '../../domain/phone-detect';
import { foldedLikePattern } from '../../domain/text-fold';
import { IntegrityService } from '../integrity/integrity.module';
import { MEDIA_QUEUE, MediaModule } from '../media/media.module';
import { StorageService } from '../media/storage.service';
import { EventEmitter } from 'node:events';
import type { Server, Socket } from 'socket.io';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode, fromPgError } from '../../common/errors';
import { AuthUser, CurrentUser, RateLimit } from '../../common/http';
import { PrismaService, RateLimiter, SettingsService } from '../../common/infra';
import { profileInclude, toPublicProfile } from '../profiles/profile.mapper';
import { NotificationsService } from '../notifications/notifications.module';
import { EntitlementsService, QuotaService } from '../quotas/quotas.module';
import { privacyOf, readReceiptsVisible } from '../../domain/privacy';

export class SendMessageDto {
  @ApiProperty({ description: 'Client-generated UUID (idempotency key)' }) @IsUUID() clientMessageId: string;
  /** Text, or the caption of photos (may be empty when attachments are sent). */
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(2000) body?: string;
  @ApiPropertyOptional({ description: 'Up to 3 photos, or one voice note, from POST :id/attachments', type: [String] })
  @IsOptional() @IsArray() @ArrayMaxSize(3) @ArrayUnique() @IsUUID('all', { each: true }) attachmentIds?: string[];
}

/** Ask for an upload slot: photos ≤ 3 per message (compressed on the device), voice ≤ 60 s. */
export class AttachmentDto {
  @ApiProperty({ enum: ['IMAGE', 'VOICE'] }) @IsIn(['IMAGE', 'VOICE']) kind: 'IMAGE' | 'VOICE';
  @ApiProperty({ enum: ['image/jpeg', 'image/webp', 'image/heic', 'audio/mp4', 'audio/aac', 'audio/mpeg'] })
  @IsIn(['image/jpeg', 'image/webp', 'image/heic', 'audio/mp4', 'audio/aac', 'audio/mpeg']) mime: string;
  @ApiProperty() @Type(() => Number) @IsInt() @Min(1) @Max(8_388_608) bytes: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(8000) width?: number;
  @ApiPropertyOptional() @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(8000) height?: number;
  @ApiPropertyOptional({ description: 'Voice only, ≤ 60000' }) @IsOptional() @Type(() => Number) @IsInt() @Min(300) @Max(60_000) durationMs?: number;
  @ApiPropertyOptional({ description: '48 peaks 0–100 for the voice bubble' }) @IsOptional() @IsArray() @ArrayMaxSize(64) @IsInt({ each: true }) @Min(0, { each: true }) @Max(100, { each: true }) waveform?: number[];
}

class SearchQuery {
  @ApiProperty({ minLength: 2 }) @IsString() @Length(2, 60) q: string;
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
const attachmentSelect = {
  id: true,
  kind: true,
  mime: true,
  width: true,
  height: true,
  durationMs: true,
  waveform: true,
  position: true,
  storageKey: true,
} as const;

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
    private readonly storage: StorageService,
    @InjectQueue(MEDIA_QUEUE) private readonly mediaQueue: Queue,
    @Inject(ENV) private readonly env: Env,
    private readonly integrity: IntegrityService,
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
        consultation: { select: { id: true, status: true, completedAt: true, clientId: true, counselorId: true } },
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
    // set only when the sender is the counselor of a consultation chat (integrity checks)
    const consultationId = c.kind === 'CONSULTATION' && c.consultation!.counselorId === userId ? c.consultation!.id : null;
    return { peerId, kind: c.kind, consultationId };
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
    const viewer = privacyOf(await this.prisma.userPrivacySettings.findUnique({ where: { userId } }));
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
        messages: { where: { deletedAt: null }, orderBy: { createdAt: 'desc' }, take: 1, select: { body: true, type: true, senderId: true, createdAt: true } },
      },
    });
    const byId = new Map(convs.map((c) => [c.id, c]));
    // Unread per conversation in one query (was one COUNT per row).
    const unreadRows = await this.prisma.$queryRaw<{ conversation_id: string; n: number }[]>`
      SELECT m.conversation_id, count(*)::int AS n
      FROM messages m
      JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = ${userId}::uuid
      WHERE m.conversation_id = ANY(${ids}::uuid[]) AND m.deleted_at IS NULL AND m.sender_id <> ${userId}::uuid
        AND (cm.last_read_at IS NULL OR m.created_at > cm.last_read_at)
      GROUP BY m.conversation_id`;
    const unreadOf = new Map(unreadRows.map((r) => [r.conversation_id, r.n]));
    const last = (c: (typeof convs)[number]) => (c.messages[0] ? { ...c.messages[0], mine: c.messages[0].senderId === userId } : null);
    return Promise.all(
      rows.map(async (r) => {
        const base = { id: r.conversation_id, section: r.section, locked: r.locked, expiresAt: r.expires_at, expiringSoon: r.warn };
        const c = byId.get(r.conversation_id);
        if (r.locked || !c) return base;
        const unread = unreadOf.get(c.id) ?? 0;
        const rematch = c.rematch ? { status: c.rematch.status, byMe: c.rematch.requestedBy === userId } : null;
        if (c.kind === 'CONSULTATION') {
          const k = c.consultation!;
          return { ...base, kind: c.kind, unread, lastMessage: last(c), lastMessageAt: c.lastMessageAt, consultation: { id: k.id, status: k.status, scheduledAt: k.scheduledAt, counselor: k.clientId === userId ? k.counselor : null } };
        }
        const m = c.match!;
        const peer = m.userAId === userId ? m.userB : m.userA;
        const matched = r.section !== 'UNMATCHED';
        return {
          ...base,
          kind: c.kind,
          unread,
          lastMessage: last(c),
          lastMessageAt: c.lastMessageAt,
          unmatchedAt: r.section === 'UNMATCHED' ? m.endedAt : null,
          unmatchedByMe: r.section === 'UNMATCHED' ? m.endedBy === userId : null,
          rematch,
          peer: peer.profile ? toPublicProfile(peer, this.env.CDN_BASE_URL, { viewer, matched }) : null,
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
    const { peerId } = await this.assertCanChat(userId, conversationId).catch((e) => {
      if (e instanceof AppError && e.code === ErrorCode.BLOCKED) throw new AppError(ErrorCode.NOT_FOUND);
      throw e;
    });
    const items = await this.prisma.message.findMany({
      where: { conversationId, deletedAt: null, ...(q.before ? { createdAt: { lt: new Date(q.before) } } : {}) },
      orderBy: { createdAt: 'desc' },
      take: q.limit + 1,
      select: {
        id: true, clientMessageId: true, senderId: true, body: true, type: true, createdAt: true, containsPhone: true,
        receipts: { select: { userId: true, deliveredAt: true, readAt: true } },
        attachments: { orderBy: { position: 'asc' }, select: attachmentSelect },
      },
    });
    const hasMore = items.length > q.limit;
    // Read receipts are reciprocal: hide "read" on my messages unless both of us keep them on.
    const prefs = await this.prisma.userPrivacySettings.findMany({ where: { userId: { in: [userId, peerId] } } });
    const mine = privacyOf(prefs.find((p) => p.userId === userId));
    const theirs = privacyOf(prefs.find((p) => p.userId === peerId));
    const showRead = readReceiptsVisible(mine, theirs);
    const out = await Promise.all(
      items
        .slice(0, q.limit)
        .reverse()
        .map(async (m) => ({
          ...m,
          attachments: await this.signAttachments(m.attachments),
          receipts: showRead ? m.receipts : m.receipts.map((r) => ({ ...r, readAt: null })),
        })),
    );
    return { items: out, hasMore, readReceipts: showRead };
  }

  /**
   * Idempotent send. Quota policy (admin-configurable):
   *  - start_only (default): starting a conversation spent the daily credit; each
   *    message counts against a per-conversation anti-spam limit.
   *  - every_message: every message also consumes the daily message quota.
   */
  async send(userId: string, conversationId: string, dto: SendMessageDto) {
    const { peerId, kind, consultationId } = await this.assertCanChat(userId, conversationId, { forWrite: true });
    const existing = await this.prisma.message.findUnique({
      where: { conversationId_senderId_clientMessageId: { conversationId, senderId: userId, clientMessageId: dto.clientMessageId } },
    });
    if (existing) return existing;

    const body = (dto.body ?? '').trim();
    const attachmentIds = dto.attachmentIds ?? [];
    if (!body && attachmentIds.length === 0) throw new AppError(ErrorCode.VALIDATION, 'Empty message');
    const atts = attachmentIds.length
      ? await this.prisma.messageAttachment.findMany({ where: { id: { in: attachmentIds }, uploaderId: userId, conversationId, messageId: null } })
      : [];
    if (atts.length !== attachmentIds.length) throw new AppError(ErrorCode.VALIDATION, 'Unknown or already used attachment');
    const kinds = new Set(atts.map((a) => a.kind));
    if (kinds.size > 1) throw new AppError(ErrorCode.VALIDATION, 'Photos and a voice note go in separate messages');
    const type = atts.length === 0 ? 'TEXT' : atts[0].kind === 'VOICE' ? 'VOICE' : 'IMAGE';
    if (type === 'VOICE' && atts.length > 1) throw new AppError(ErrorCode.VALIDATION, 'One voice note per message');
    // The upload must really be there (and within the signed size) before it is attached.
    for (const a of atts) await this.storage.head(a.storageKey).catch(() => { throw new AppError(ErrorCode.VALIDATION, 'Upload not finished'); });
    const containsPhone = containsPhoneNumber(body);
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
        if (type === 'VOICE') await this.consumeVoice(tx, userId, conversationId, kind);
        const m = await tx.message.create({ data: { conversationId, senderId: userId, clientMessageId: dto.clientMessageId, body, type, containsPhone } });
        for (const [i, a] of atts.entries()) {
          await tx.messageAttachment.update({ where: { id: a.id }, data: { messageId: m.id, position: i } });
        }
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

    // Photos are re-encoded in the worker: metadata (incl. GPS) stripped, ≤ 2048 px.
    for (const a of atts.filter((x) => x.kind === 'IMAGE')) await this.mediaQueue.add('chat-image', { attachmentId: a.id }, { attempts: 3, backoff: { type: 'exponential', delay: 2000 } });
    const full = await this.prisma.message.findUniqueOrThrow({
      where: { id: msg.id },
      select: { id: true, clientMessageId: true, senderId: true, body: true, type: true, createdAt: true, containsPhone: true, attachments: { orderBy: { position: 'asc' }, select: attachmentSelect } },
    });
    const out = { ...full, attachments: await this.signAttachments(full.attachments) };
    // Counselor sharing off-platform contact details in a consultation chat → integrity signal.
    if (kind === 'CONSULTATION' && consultationId && body) {
      await this.integrity.fromCounselorMessage(userId, consultationId, body).catch(() => undefined);
    }
    this.events.emit('message', { conversationId, userIds: [userId, peerId], message: out });
    await this.notifications.push(peerId, type === 'VOICE' ? 'push.new_voice' : type === 'IMAGE' ? 'push.new_photo' : 'push.new_message', { conversationId });
    return out;
  }

  /** Voice notes per conversation: Free 10 · Plus 30 · Premium unlimited (consultation chats unlimited). */
  private async consumeVoice(tx: Prisma.TransactionClient, userId: string, conversationId: string, kind: string) {
    if (kind === 'CONSULTATION') return;
    const ent = await this.entitlements.forUser(userId);
    if (ent.voiceNotesPerConversation < 0) return;
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${'voice:' + conversationId + ':' + userId}, 0))`;
    const used = await tx.message.count({ where: { conversationId, senderId: userId, type: 'VOICE' } });
    if (used >= ent.voiceNotesPerConversation) {
      throw new AppError(ErrorCode.QUOTA_EXCEEDED, 'Voice note limit for this conversation', { quota: 'voice', limit: ent.voiceNotesPerConversation });
    }
  }

  /** Voice notes left in this conversation (null = unlimited). */
  async voiceLeft(userId: string, conversationId: string) {
    const { kind } = await this.assertCanChat(userId, conversationId);
    const ent = await this.entitlements.forUser(userId);
    if (kind === 'CONSULTATION' || ent.voiceNotesPerConversation < 0) return { limit: -1, used: null, remaining: null };
    const used = await this.prisma.message.count({ where: { conversationId, senderId: userId, type: 'VOICE' } });
    return { limit: ent.voiceNotesPerConversation, used, remaining: Math.max(0, ent.voiceNotesPerConversation - used) };
  }

  /** Upload slot in the private bucket (presigned POST; size and type are part of the signature). */
  async createAttachment(userId: string, conversationId: string, dto: AttachmentDto) {
    const { kind } = await this.assertCanChat(userId, conversationId, { forWrite: true });
    const isVoice = dto.kind === 'VOICE';
    if (isVoice !== dto.mime.startsWith('audio/')) throw new AppError(ErrorCode.VALIDATION, 'mime does not match kind');
    if (isVoice && !dto.durationMs) throw new AppError(ErrorCode.VALIDATION, 'durationMs is required for voice notes');
    if (isVoice) {
      const left = await this.voiceLeft(userId, conversationId);
      if (left.remaining === 0) throw new AppError(ErrorCode.QUOTA_EXCEEDED, 'Voice note limit for this conversation', { quota: 'voice', limit: left.limit });
    }
    void kind;
    const pending = await this.prisma.messageAttachment.count({ where: { uploaderId: userId, messageId: null, createdAt: { gt: new Date(Date.now() - 3_600_000) } } });
    if (pending >= 30) throw new AppError(ErrorCode.RATE_LIMITED, 'Too many pending uploads');
    const key = `chat/${conversationId}/${randomUUID()}`;
    const a = await this.prisma.messageAttachment.create({
      data: {
        uploaderId: userId,
        conversationId,
        kind: dto.kind,
        storageKey: key,
        mime: dto.mime,
        bytes: dto.bytes,
        width: dto.width ?? null,
        height: dto.height ?? null,
        durationMs: isVoice ? dto.durationMs : null,
        waveform: isVoice ? (dto.waveform ?? []).slice(0, 64) : [],
      },
    });
    return { id: a.id, upload: await this.storage.presignUpload(key, dto.mime, Math.min(dto.bytes + 1024, 8_388_608)) };
  }

  private async signAttachments<T extends { storageKey: string }>(list: T[]) {
    return Promise.all(list.map(async ({ storageKey, ...rest }) => ({ ...rest, url: await this.storage.signedPrivateUrl(storageKey, 3600) })));
  }

  /**
   * One field, two kinds of results: conversations whose name matches and
   * messages whose text matches (trigram indexes). Only the user's own,
   * unlocked conversations are searched.
   */
  async search(userId: string, q: string) {
    const like = foldedLikePattern(q); // Arabic spelling variants match (أ/ا, ة/ه, ى/ي…)
    const rows = await this.listRows(userId);
    const allowed = rows.filter((r) => !r.locked).map((r) => r.conversation_id);
    if (allowed.length === 0) return { conversations: [], messages: [] };
    const [byName, byText] = await Promise.all([
      this.prisma.$queryRaw<{ conversation_id: string }[]>`
        SELECT DISTINCT cm.conversation_id
        FROM conversation_members cm
        JOIN conversations c ON c.id = cm.conversation_id
        LEFT JOIN user_profiles p ON p.user_id = cm.user_id
        LEFT JOIN consultations k ON k.id = c.consultation_id
        LEFT JOIN counselor_profiles cp ON cp.user_id = k.counselor_id
        WHERE cm.conversation_id = ANY(${allowed}::uuid[]) AND cm.user_id <> ${userId}::uuid
          AND (olfa_fold(p.display_name) LIKE ${like} OR olfa_fold(cp.display_name) LIKE ${like})
        LIMIT 20`,
      this.prisma.$queryRaw<{ id: string; conversation_id: string; body: string; created_at: Date; sender_id: string }[]>`
        SELECT m.id, m.conversation_id, m.body, m.created_at, m.sender_id
        FROM messages m
        WHERE m.conversation_id = ANY(${allowed}::uuid[]) AND m.deleted_at IS NULL AND m.type IN ('TEXT', 'IMAGE') AND m.body <> ''
          AND olfa_fold(m.body) LIKE ${like}
        ORDER BY m.created_at DESC
        LIMIT 30`,
    ]);
    return {
      conversations: byName.map((r) => r.conversation_id),
      messages: byText.map((m) => ({ id: m.id, conversationId: m.conversation_id, body: m.body, createdAt: m.created_at, fromMe: m.sender_id === userId })),
    };
  }

  async markRead(userId: string, conversationId: string) {
    await this.assertCanChat(userId, conversationId);
    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.conversationMember.update({ where: { conversationId_userId: { conversationId, userId } }, data: { lastReadAt: now } }),
      this.prisma.messageReceipt.updateMany({ where: { userId, readAt: null, message: { conversationId } }, data: { readAt: now, deliveredAt: now } }),
    ]);
    const c = await this.prisma.conversation.findUniqueOrThrow({ where: { id: conversationId }, select: { members: { select: { userId: true } } } });
    const ids = c.members.map((m) => m.userId);
    const prefs = await this.prisma.userPrivacySettings.findMany({ where: { userId: { in: ids } } });
    const reader = privacyOf(prefs.find((p) => p.userId === userId));
    const others = ids.filter((id) => id !== userId);
    // The other person learns "read" only when both keep read receipts on; the reader's own devices always sync.
    const notify = others.filter((id) => readReceiptsVisible(privacyOf(prefs.find((p) => p.userId === id)), reader));
    this.events.emit('read', { conversationId, userIds: [userId, ...notify], readerId: userId, at: now });
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
      const s = await this.prisma.userSession.findUnique({ where: { id: p.sid }, select: { revokedAt: true, user: { select: { status: true, accountType: true } } } });
      if (p.typ !== 'access' || !s || s.revokedAt || !['ACTIVE', 'RESTRICTED'].includes(s.user.status)) throw new Error('unauthorized');
      socket.data.user = { id: p.sub, sessionId: p.sid, status: s.user.status, accountType: s.user.accountType } satisfies AuthUser;
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
      const dto = Object.assign(new SendMessageDto(), { clientMessageId: payload?.clientMessageId, body: payload?.body, attachmentIds: payload?.attachmentIds });
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
      // Only where a message could actually be sent (not unmatched / closed chats).
      const { peerId } = await this.messaging.assertCanChat(u.id, payload.conversationId, { forWrite: true });
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

  /** Instant search across names and message text (debounced by the app). */
  @RateLimit(120, 60) @Get('search')
  search(@CurrentUser() u: AuthUser, @Query() q: SearchQuery) {
    return this.messaging.search(u.id, q.q);
  }

  @RateLimit(60, 60) @Post(':id/attachments')
  attach(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: AttachmentDto) {
    return this.messaging.createAttachment(u.id, id, dto);
  }

  @Get(':id/voice-quota')
  voice(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.messaging.voiceLeft(u.id, id);
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
  imports: [JwtModule.register({}), MediaModule, BullModule.registerQueue({ name: MEDIA_QUEUE })],
  controllers: [MessagingController],
  providers: [MessagingService, ChatGateway, ChatEvents],
})
export class MessagingModule {}
