import { Body, Controller, Delete, Get, Headers, HttpCode, Inject, Injectable, Module, Param, ParseUUIDPipe, Post, Put, Query } from '@nestjs/common';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Prisma, TicketCategory, TicketStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayUnique, IsArray, IsBoolean, IsEnum, IsIn, IsInt, IsObject, IsOptional, IsString, IsUUID, Length, Max, MaxLength, Min } from 'class-validator';
import { randomUUID } from 'node:crypto';
import { ENV, Env } from '../../config/env';
import { AppError, ErrorCode, fromPgError } from '../../common/errors';
import { AllowPending, AuthAdmin, AuthUser, CurrentAdmin, CurrentUser, Public, RateLimit, RequirePermissions } from '../../common/http';
import { AuditService, PrismaService } from '../../common/infra';
import { asLocale } from '../../domain/locale';
import { MediaModule } from '../media/media.module';
import { StorageService } from '../media/storage.service';
import { ChatEvents, MessagingModule } from '../messaging/messaging.module';
import { NotificationsService } from '../notifications/notifications.module';

export const TICKET_MIMES = ['image/jpeg', 'image/png', 'image/heic', 'image/webp', 'application/pdf'] as const;
const MAX_BYTES = 10 * 1024 * 1024;

class UploadDto {
  @ApiProperty() @IsString() @Length(1, 120) fileName: string;
  @ApiProperty({ enum: TICKET_MIMES }) @IsIn(TICKET_MIMES) mime: string;
  @ApiProperty() @Type(() => Number) @IsInt() @Min(1) @Max(MAX_BYTES) bytes: number;
}

class TicketMessageDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(4000) body?: string;
  @ApiPropertyOptional({ description: 'Up to 3 images or PDFs from POST /support/attachments', type: [String] })
  @IsOptional() @IsArray() @ArrayMaxSize(3) @ArrayUnique() @IsUUID('all', { each: true }) attachmentIds?: string[];
}

class CreateTicketDto extends TicketMessageDto {
  @ApiProperty({ enum: TicketCategory }) @IsEnum(TicketCategory) category: TicketCategory;
  @ApiProperty() @IsString() @Length(3, 150) subject: string;
}

class AppealDto {
  @ApiProperty() @IsString() @Length(10, 2000) body: string;
}

class AdminStatusDto {
  @ApiProperty({ enum: TicketStatus }) @IsEnum(TicketStatus) status: TicketStatus;
}

class AdminQueueQuery {
  @ApiPropertyOptional({ enum: TicketStatus }) @IsOptional() @IsEnum(TicketStatus) status?: TicketStatus;
}

class FaqDto {
  @ApiProperty({ enum: TicketCategory }) @IsEnum(TicketCategory) category: TicketCategory;
  @ApiProperty({ example: { ar: '…', en: '…', fr: '…' } }) @IsObject() question: Record<'ar' | 'en' | 'fr', string>;
  @ApiProperty({ example: { ar: '…', en: '…', fr: '…' } }) @IsObject() answer: Record<'ar' | 'en' | 'fr', string>;
  @ApiProperty() @IsInt() @Min(0) @Max(999) sortOrder: number;
  @ApiProperty() @IsBoolean() published: boolean;
}

const attachmentSelect = { id: true, fileName: true, mime: true, bytes: true, storageKey: true } satisfies Prisma.TicketAttachmentSelect;
const messageSelect = { id: true, authorType: true, body: true, createdAt: true, attachments: { orderBy: { createdAt: 'asc' }, select: attachmentSelect } } satisfies Prisma.TicketMessageSelect;

@Injectable()
export class SupportService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly notifications: NotificationsService,
    private readonly audit: AuditService,
    private readonly events: ChatEvents,
    private readonly jwt: JwtService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /**
   * A closed (banned / suspended) account cannot sign in, but can still appeal: the sign-in
   * error carried a 2-hour appeal token. One open appeal at a time; text only.
   */
  async appeal(authorization: string | undefined, dto: AppealDto) {
    let userId: string;
    try {
      const p = await this.jwt.verifyAsync<{ sub: string; typ: string }>((authorization ?? '').replace(/^Bearer\s+/i, ''), { secret: this.env.JWT_ACCESS_SECRET });
      if (p.typ !== 'appeal') throw new Error('typ');
      userId = p.sub;
    } catch {
      throw new AppError(ErrorCode.UNAUTHORIZED);
    }
    const open = await this.prisma.supportTicket.findFirst({ where: { userId, category: 'ACCOUNT', subject: 'Account closure appeal', status: { in: ['OPEN', 'PENDING_USER'] } }, select: { id: true } });
    if (open) {
      await this.prisma.ticketMessage.create({ data: { ticketId: open.id, authorType: 'USER', authorId: userId, body: dto.body.trim() } });
      return { ticketId: open.id };
    }
    const t = await this.prisma.$transaction(async (tx) => {
      const ticket = await tx.supportTicket.create({ data: { userId, category: 'ACCOUNT', subject: 'Account closure appeal' } });
      await tx.ticketMessage.create({ data: { ticketId: ticket.id, authorType: 'USER', authorId: userId, body: dto.body.trim() } });
      return ticket;
    });
    return { ticketId: t.id };
  }

  /** Private upload for a support message (image or PDF, ≤ 10 MB). Linked when the message is sent. */
  async upload(userId: string, dto: UploadDto) {
    const pending = await this.prisma.ticketAttachment.count({ where: { uploaderId: userId, messageId: null, createdAt: { gt: new Date(Date.now() - 3_600_000) } } });
    if (pending >= 15) throw new AppError(ErrorCode.RATE_LIMITED, 'Too many pending uploads');
    const key = `support/${userId}/${randomUUID()}`;
    const fileName = dto.fileName.replace(/[\\/\u0000-\u001f]/g, '_').slice(0, 120);
    const a = await this.prisma.ticketAttachment.create({ data: { uploaderId: userId, storageKey: key, fileName, mime: dto.mime, bytes: dto.bytes } });
    return { id: a.id, upload: await this.storage.presignUpload(key, dto.mime, Math.min(dto.bytes + 1024, MAX_BYTES)) };
  }

  private async sign(list: { storageKey: string; [k: string]: unknown }[]) {
    return Promise.all(list.map(async ({ storageKey, ...rest }) => ({ ...rest, url: await this.storage.signedPrivateUrl(storageKey, 3600) })));
  }

  private async signMessage<T extends { attachments: { storageKey: string }[] }>(m: T) {
    return { ...m, attachments: await this.sign(m.attachments) };
  }

  /** Inserts a message and links its uploads (checks they are the author's own, unused, uploaded). */
  private async addMessage(tx: Prisma.TransactionClient, ticketId: string, author: { type: 'USER' | 'ADMIN'; id: string }, dto: TicketMessageDto) {
    const body = dto.body?.trim() ?? '';
    const ids = dto.attachmentIds ?? [];
    if (!body && ids.length === 0) throw new AppError(ErrorCode.VALIDATION, 'Empty message');
    const atts = ids.length ? await tx.ticketAttachment.findMany({ where: { id: { in: ids }, uploaderId: author.id, messageId: null } }) : [];
    if (atts.length !== ids.length) throw new AppError(ErrorCode.VALIDATION, 'Unknown or already used attachment');
    for (const a of atts) {
      const head = await this.storage.head(a.storageKey).catch(() => null);
      if (!head) throw new AppError(ErrorCode.VALIDATION, 'Attachment was not uploaded');
    }
    const m = await tx.ticketMessage.create({ data: { ticketId, authorType: author.type, authorId: author.id, body }, select: { id: true } });
    if (atts.length) await tx.ticketAttachment.updateMany({ where: { id: { in: atts.map((a) => a.id) } }, data: { ticketId, messageId: m.id, status: 'READY' } });
    return tx.ticketMessage.findUniqueOrThrow({ where: { id: m.id }, select: messageSelect });
  }

  private wrap<T>(p: Promise<T>): Promise<T> {
    return p.catch((e: unknown) => {
      throw fromPgError(e) ?? e;
    });
  }

  // ── user ──

  async create(userId: string, dto: CreateTicketDto) {
    const open = await this.prisma.supportTicket.count({ where: { userId, status: { in: ['OPEN', 'PENDING_USER'] } } });
    if (open >= 5) throw new AppError(ErrorCode.RATE_LIMITED, 'Too many open requests');
    const t = await this.wrap(
      this.prisma.$transaction(async (tx) => {
        const ticket = await tx.supportTicket.create({ data: { userId, category: dto.category, subject: dto.subject.trim(), userLastReadAt: new Date() } });
        await this.addMessage(tx, ticket.id, { type: 'USER', id: userId }, dto);
        return ticket;
      }),
    );
    return this.thread(userId, t.id);
  }

  async list(userId: string) {
    const rows = await this.prisma.supportTicket.findMany({
      where: { userId },
      orderBy: { lastMessageAt: 'desc' },
      take: 50,
      select: { id: true, category: true, subject: true, status: true, createdAt: true, lastMessageAt: true, userLastReadAt: true, messages: { orderBy: { createdAt: 'desc' }, take: 1, select: { body: true, authorType: true, createdAt: true } } },
    });
    // unread = staff replies after the user last opened the thread
    const unread = await Promise.all(rows.map((r) => this.prisma.ticketMessage.count({ where: { ticketId: r.id, authorType: 'ADMIN', ...(r.userLastReadAt ? { createdAt: { gt: r.userLastReadAt } } : {}) } })));
    return rows.map(({ messages, userLastReadAt: _r, ...r }, i) => ({ ...r, last: messages[0] ?? null, unread: unread[i] }));
  }

  /** The whole conversation with support, on the same page; opening it marks staff replies read. */
  async thread(userId: string, id: string) {
    const t = await this.prisma.supportTicket.findFirst({
      where: { id, userId },
      select: { id: true, category: true, subject: true, status: true, createdAt: true, lastMessageAt: true, messages: { orderBy: { createdAt: 'asc' }, select: messageSelect } },
    });
    if (!t) throw new AppError(ErrorCode.NOT_FOUND);
    await this.prisma.supportTicket.update({ where: { id }, data: { userLastReadAt: new Date() } });
    return { ...t, messages: await Promise.all(t.messages.map((m) => this.signMessage(m))) };
  }

  async reply(userId: string, id: string, dto: TicketMessageDto) {
    const t = await this.prisma.supportTicket.findFirst({ where: { id, userId }, select: { status: true } });
    if (!t) throw new AppError(ErrorCode.NOT_FOUND);
    if (t.status === 'CLOSED') throw new AppError(ErrorCode.INVALID_STATE, 'This request is closed — open a new one');
    const m = await this.wrap(this.prisma.$transaction((tx) => this.addMessage(tx, id, { type: 'USER', id: userId }, dto)));
    await this.prisma.supportTicket.update({ where: { id }, data: { userLastReadAt: new Date() } });
    return this.signMessage(m);
  }

  async close(userId: string, id: string) {
    const r = await this.prisma.supportTicket.updateMany({ where: { id, userId, status: { not: 'CLOSED' } }, data: { status: 'CLOSED' } });
    if (r.count === 0) throw new AppError(ErrorCode.NOT_FOUND);
    return { id, status: 'CLOSED' };
  }

  async unreadCount(userId: string) {
    const rows = await this.prisma.$queryRaw<{ n: bigint }[]>`
      SELECT count(*) AS n FROM ticket_messages m JOIN support_tickets t ON t.id = m.ticket_id
      WHERE t.user_id = ${userId}::uuid AND m.author_type = 'ADMIN' AND (t.user_last_read_at IS NULL OR m.created_at > t.user_last_read_at)`;
    return { unread: Number(rows[0]?.n ?? 0) };
  }

  // ── FAQ ──

  async faq(lang: string | undefined) {
    const l = asLocale(lang);
    const rows = await this.prisma.faqEntry.findMany({ where: { published: true }, orderBy: [{ category: 'asc' }, { sortOrder: 'asc' }] });
    return rows.map((r) => ({ id: r.id, category: r.category, question: (r.question as Record<string, string>)[l], answer: (r.answer as Record<string, string>)[l] }));
  }

  // ── admin (the panel is built later; these are its endpoints) ──

  adminQueue(q: AdminQueueQuery) {
    return this.prisma.supportTicket.findMany({
      where: { status: q.status ?? { in: ['OPEN', 'PENDING_USER'] } },
      orderBy: { lastMessageAt: 'asc' },
      take: 200,
      select: { id: true, userId: true, category: true, subject: true, status: true, assignedTo: true, createdAt: true, lastMessageAt: true, staffLastReadAt: true },
    });
  }

  async adminThread(admin: AuthAdmin, id: string) {
    const t = await this.prisma.supportTicket.findUnique({
      where: { id },
      select: { id: true, userId: true, category: true, subject: true, status: true, assignedTo: true, createdAt: true, messages: { orderBy: { createdAt: 'asc' }, select: messageSelect } },
    });
    if (!t) throw new AppError(ErrorCode.NOT_FOUND);
    await this.prisma.supportTicket.update({ where: { id }, data: { staffLastReadAt: new Date(), assignedTo: t.assignedTo ?? admin.id } });
    return { ...t, messages: await Promise.all(t.messages.map((m) => this.signMessage(m))) };
  }

  async adminReply(admin: AuthAdmin, id: string, dto: TicketMessageDto) {
    const t = await this.prisma.supportTicket.findUnique({ where: { id }, select: { userId: true, status: true } });
    if (!t) throw new AppError(ErrorCode.NOT_FOUND);
    if (t.status === 'CLOSED') throw new AppError(ErrorCode.INVALID_STATE);
    const m = await this.wrap(
      this.prisma.$transaction(async (tx) => {
        const msg = await this.addMessage(tx, id, { type: 'ADMIN', id: admin.id }, dto);
        await tx.supportTicket.update({ where: { id }, data: { staffLastReadAt: new Date(), assignedTo: admin.id } });
        await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'support.reply', entityType: 'support_ticket', entityId: id }, tx);
        await this.notifications.notify(t.userId, 'SUPPORT_REPLY', 'push.support_reply', { ticketId: id }, tx);
        return msg;
      }),
    );
    const out = await this.signMessage(m);
    this.events.emit('support', { userId: t.userId, ticketId: id, message: out });
    await this.notifications.push(t.userId, 'push.support_reply', { ticketId: id });
    return out;
  }

  async adminStatus(admin: AuthAdmin, id: string, dto: AdminStatusDto) {
    const before = await this.prisma.supportTicket.findUnique({ where: { id }, select: { status: true } });
    if (!before) throw new AppError(ErrorCode.NOT_FOUND);
    await this.prisma.supportTicket.update({ where: { id }, data: { status: dto.status } });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'support.status', entityType: 'support_ticket', entityId: id, before, after: { status: dto.status } });
    return { id, status: dto.status };
  }

  /** Admin uploads use the same private storage; the uploader is the admin. */
  adminUpload(admin: AuthAdmin, dto: UploadDto) {
    return this.upload(admin.id, dto);
  }

  private checkFaq(dto: FaqDto) {
    for (const f of [dto.question, dto.answer]) {
      for (const l of ['ar', 'en', 'fr'] as const) if (typeof f?.[l] !== 'string' || !f[l].trim()) throw new AppError(ErrorCode.VALIDATION, `FAQ needs ${l} text`);
    }
  }

  async faqCreate(admin: AuthAdmin, dto: FaqDto) {
    this.checkFaq(dto);
    const f = await this.prisma.faqEntry.create({ data: dto });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'faq.create', entityType: 'faq', entityId: f.id });
    return f;
  }

  async faqUpdate(admin: AuthAdmin, id: string, dto: FaqDto) {
    this.checkFaq(dto);
    const f = await this.prisma.faqEntry.update({ where: { id }, data: { ...dto, updatedAt: new Date() } }).catch(() => {
      throw new AppError(ErrorCode.NOT_FOUND);
    });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'faq.update', entityType: 'faq', entityId: id });
    return f;
  }

  async faqDelete(admin: AuthAdmin, id: string) {
    await this.prisma.faqEntry.deleteMany({ where: { id } });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'faq.delete', entityType: 'faq', entityId: id });
    return { ok: true };
  }
}

@ApiTags('support')
@ApiBearerAuth()
@Controller('v1/support')
export class SupportController {
  constructor(private readonly svc: SupportService) {}

  /** Public: the Help page shows the FAQ before sign-in too. */
  @Public() @Get('faq')
  faq(@Query('lang') lang?: string) {
    return this.svc.faq(lang);
  }

  /** Closed accounts: appeal with the token from the sign-in error (no session needed). */
  @Public() @RateLimit(5, 3600) @Post('appeal')
  appeal(@Headers('authorization') authorization: string | undefined, @Body() dto: AppealDto) {
    return this.svc.appeal(authorization, dto);
  }

  // AllowPending: people still finishing sign-up (or frozen) can reach support too
  @AllowPending() @RateLimit(30, 3600) @Post('attachments')
  upload(@CurrentUser() u: AuthUser, @Body() dto: UploadDto) {
    return this.svc.upload(u.id, dto);
  }

  @AllowPending() @RateLimit(10, 3600) @Post('tickets')
  create(@CurrentUser() u: AuthUser, @Body() dto: CreateTicketDto) {
    return this.svc.create(u.id, dto);
  }

  @AllowPending() @Get('tickets')
  list(@CurrentUser() u: AuthUser) {
    return this.svc.list(u.id);
  }

  @AllowPending() @Get('unread')
  unread(@CurrentUser() u: AuthUser) {
    return this.svc.unreadCount(u.id);
  }

  @AllowPending() @Get('tickets/:id')
  thread(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.thread(u.id, id);
  }

  @AllowPending() @RateLimit(60, 3600) @Post('tickets/:id/messages')
  reply(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: TicketMessageDto) {
    return this.svc.reply(u.id, id, dto);
  }

  @AllowPending() @Post('tickets/:id/close') @HttpCode(200)
  close(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.close(u.id, id);
  }
}

@ApiTags('admin-support')
@ApiBearerAuth()
@Controller('v1/admin/support')
export class SupportAdminController {
  constructor(private readonly svc: SupportService) {}

  @RequirePermissions('support.manage') @Get('tickets')
  queue(@Query() q: AdminQueueQuery) {
    return this.svc.adminQueue(q);
  }
  @RequirePermissions('support.manage') @Get('tickets/:id')
  thread(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.adminThread(a, id);
  }
  @RequirePermissions('support.manage') @Post('attachments')
  upload(@CurrentAdmin() a: AuthAdmin, @Body() dto: UploadDto) {
    return this.svc.adminUpload(a, dto);
  }
  @RequirePermissions('support.manage') @Post('tickets/:id/messages')
  reply(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: TicketMessageDto) {
    return this.svc.adminReply(a, id, dto);
  }
  @RequirePermissions('support.manage') @Put('tickets/:id/status') @HttpCode(200)
  status(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: AdminStatusDto) {
    return this.svc.adminStatus(a, id, dto);
  }
  @RequirePermissions('support.manage') @Post('faq')
  faqCreate(@CurrentAdmin() a: AuthAdmin, @Body() dto: FaqDto) {
    return this.svc.faqCreate(a, dto);
  }
  @RequirePermissions('support.manage') @Put('faq/:id') @HttpCode(200)
  faqUpdate(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string, @Body() dto: FaqDto) {
    return this.svc.faqUpdate(a, id, dto);
  }
  @RequirePermissions('support.manage') @Delete('faq/:id') @HttpCode(200)
  faqDelete(@CurrentAdmin() a: AuthAdmin, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.faqDelete(a, id);
  }
}

@Module({
  imports: [JwtModule.register({}), MediaModule, MessagingModule],
  controllers: [SupportController, SupportAdminController],
  providers: [SupportService],
})
export class SupportModule {}
