import { Body, Controller, Get, HttpCode, Injectable, Logger, Module, Param, ParseUUIDPipe, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Prisma } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsIn, IsInt, IsObject, IsOptional, IsString, IsUUID, Length, Matches, Max, Min, ValidateNested,
} from 'class-validator';
import { randomUUID } from 'node:crypto';
import { AppError, ErrorCode, fromPgError } from '../../common/errors';
import { AuthAdmin, AuthUser, CurrentAdmin, CurrentUser, MembersOnly, RateLimit, RequirePermissions } from '../../common/http';
import { AuditService, PrismaService, SettingsService } from '../../common/infra';
import { COMPAT_DOMAINS, pickQuestionSets, scoreCompat, type CompatDomain, type CompatQuestionDef } from '../../domain/compat';
import { ChatEvents, MessagingModule, MessagingService } from '../messaging/messaging.module';
import { NotificationsModule, NotificationsService } from '../notifications/notifications.module';

// ───────────── DTOs ─────────────

class AnswerDto {
  @ApiProperty() @IsUUID() questionId: string;
  @ApiProperty() @IsString() @Length(1, 20) optionKey: string;
}

class AnswersDto {
  @ApiProperty({ type: [AnswerDto] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(60) @ValidateNested({ each: true }) @Type(() => AnswerDto) answers: AnswerDto[];
}

class I18nText {
  @ApiProperty() @IsString() @Length(1, 300) ar: string;
  @ApiProperty() @IsString() @Length(1, 300) en: string;
  @ApiProperty() @IsString() @Length(1, 300) fr: string;
}

class OptionDto {
  @ApiProperty() @IsString() @Matches(/^[a-z0-9_]{1,20}$/) key: string;
  @ApiProperty({ minimum: 0, maximum: 10 }) @IsInt() @Min(0) @Max(10) value: number;
  @ApiProperty({ type: I18nText }) @ValidateNested() @Type(() => I18nText) label: I18nText;
}

class QuestionDto {
  @ApiProperty() @IsString() @Matches(/^[a-z][a-z0-9_]{1,39}$/) topic: string;
  @ApiProperty({ enum: COMPAT_DOMAINS }) @IsIn(COMPAT_DOMAINS as unknown as string[]) domain: CompatDomain;
  @ApiProperty({ enum: ['ALL', 'MALE', 'FEMALE'] }) @IsIn(['ALL', 'MALE', 'FEMALE']) audience: 'ALL' | 'MALE' | 'FEMALE';
  @ApiProperty({ type: I18nText }) @IsObject() @ValidateNested() @Type(() => I18nText) prompt: I18nText;
  @ApiProperty({ type: [OptionDto] }) @IsArray() @ArrayMinSize(2) @ArrayMaxSize(6) @ValidateNested({ each: true }) @Type(() => OptionDto) options: OptionDto[];
  @ApiProperty({ minimum: 1, maximum: 10 }) @IsInt() @Min(1) @Max(10) weight: number;
  @ApiProperty({ enum: ['SCALE', 'MATCH'] }) @IsIn(['SCALE', 'MATCH']) scoring: 'SCALE' | 'MATCH';
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(100000) sortOrder?: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
}

class ActiveDto {
  @ApiProperty() @IsBoolean() active: boolean;
}

// ───────────── service ─────────────

type ResultOut = { score: number; domains: { domain: CompatDomain; score: number; topics: number }[]; agreed: number; talkAbout: string[]; computedAt: Date };

@Injectable()
export class CompatService {
  private readonly log = new Logger('Compat');
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    private readonly messaging: MessagingService,
    private readonly events: ChatEvents,
    private readonly notifications: NotificationsService,
  ) {}

  /** Match chats only, between two members of an ACTIVE match. */
  private async assertMatchChat(userId: string, conversationId: string, forWrite: boolean) {
    const r = await this.messaging.assertCanChat(userId, conversationId, { forWrite });
    if (r.kind !== 'MATCH') throw new AppError(ErrorCode.NOT_ELIGIBLE, 'compatibility questions are for match chats');
    return r;
  }

  private toDef(q: { id: string; topic: string; domain: CompatDomain; weight: number; scoring: string; options: Prisma.JsonValue }): CompatQuestionDef {
    return { id: q.id, topic: q.topic, domain: q.domain, weight: q.weight, scoring: q.scoring === 'MATCH' ? 'MATCH' : 'SCALE', options: (q.options as { key: string; value: number }[]).map((o) => ({ key: o.key, value: o.value })) };
  }

  /**
   * What this member may see: their own questions and answers, the other
   * person's progress (started / finished — never their answers), and the
   * result once both finished.
   */
  async state(userId: string, conversationId: string) {
    const { peerId } = await this.assertMatchChat(userId, conversationId, false);
    const enabled = await this.settings.get('compat.enabled', true);
    const session = await this.prisma.compatSession.findUnique({ where: { conversationId }, include: { result: true } });
    if (!session) return { enabled, status: 'NOT_STARTED' as const, me: null, peer: null, questions: [], result: null };
    const progress = await this.progress(conversationId);
    const me = progress.get(userId) ?? { answered: 0, total: 0 };
    const peer = progress.get(peerId) ?? { answered: 0, total: 0 };
    const myIds = await this.myQuestionIds(conversationId, userId);
    const [questions, mine] = await Promise.all([
      this.prisma.compatQuestion.findMany({ where: { id: { in: myIds } } }),
      this.prisma.compatAnswer.findMany({ where: { conversationId, userId }, select: { questionId: true, optionKey: true } }),
    ]);
    const byId = new Map(questions.map((q) => [q.id, q]));
    const myAnswer = new Map(mine.map((a) => [a.questionId, a.optionKey]));
    const result = session.result ? this.resultOut(session.result) : null;
    return {
      enabled,
      status: result ? ('RESULT' as const) : ('IN_PROGRESS' as const),
      startedByMe: session.startedBy === userId,
      me: { answered: me.answered, total: me.total, completed: me.total > 0 && me.answered === me.total },
      peer: { started: peer.answered > 0, completed: peer.total > 0 && peer.answered === peer.total },
      questions: myIds.map((id) => byId.get(id)).filter((q): q is NonNullable<typeof q> => !!q).map((q) => ({
        id: q.id, domain: q.domain, prompt: q.prompt,
        options: (q.options as { key: string; label: unknown }[]).map((o) => ({ key: o.key, label: o.label })),
        answer: myAnswer.get(q.id) ?? null,
      })),
      result,
    };
  }

  private resultOut(r: { score: number; breakdown: Prisma.JsonValue; computedAt: Date }): ResultOut {
    const b = r.breakdown as { domains?: ResultOut['domains']; agreed?: number; talkAbout?: string[] };
    return { score: r.score, domains: b.domains ?? [], agreed: b.agreed ?? 0, talkAbout: b.talkAbout ?? [], computedAt: r.computedAt };
  }

  private async progress(conversationId: string) {
    const rows = await this.prisma.$queryRaw<{ user_id: string; answered: number; total: number }[]>`SELECT * FROM olfa_compat_progress(${conversationId}::uuid)`;
    return new Map(rows.map((r) => [r.user_id, { answered: Number(r.answered), total: Number(r.total) }]));
  }

  private async myQuestionIds(conversationId: string, userId: string) {
    const [row] = await this.prisma.$queryRaw<{ ids: string[] | null }[]>`SELECT olfa_compat_my_questions(${conversationId}::uuid, ${userId}::uuid) AS ids`;
    return row?.ids ?? [];
  }

  /** Either person starts it; the question set is fixed at this moment. */
  async start(userId: string, conversationId: string) {
    const { peerId } = await this.assertMatchChat(userId, conversationId, true);
    if (!(await this.settings.get('compat.enabled', true))) throw new AppError(ErrorCode.NOT_ELIGIBLE, 'compatibility questions are switched off');
    const exists = await this.prisma.compatSession.findUnique({ where: { conversationId }, select: { conversationId: true } });
    if (!exists) {
      const active = await this.prisma.compatQuestion.findMany({ where: { active: true }, select: { id: true, audience: true, sortOrder: true } });
      const sets = pickQuestionSets(active);
      if (!sets.male.length || !sets.female.length) throw new AppError(ErrorCode.NOT_ELIGIBLE, 'no active questions');
      try {
        await this.prisma.compatSession.create({ data: { conversationId, startedBy: userId, maleQuestions: sets.male, femaleQuestions: sets.female } });
        await this.notifications.push(peerId, 'push.compat_started', { conversationId }).catch(() => undefined);
      } catch (e) {
        const err = fromPgError(e);
        if (err?.code !== ErrorCode.CONFLICT) throw err ?? e; // started by the other person at the same moment: fine
      }
      this.events.emit('compat', { conversationId, userIds: [userId, peerId] });
    }
    return this.state(userId, conversationId);
  }

  /**
   * Save answers (any number, any order; changeable until the result is out).
   * When both have answered everything, the result is computed once and added
   * to the chat as its own message — the rest of the conversation is untouched.
   */
  async answer(userId: string, conversationId: string, dto: AnswersDto) {
    const { peerId } = await this.assertMatchChat(userId, conversationId, true);
    try {
      await this.prisma.$transaction(
        dto.answers.map((a) =>
          this.prisma.compatAnswer.upsert({
            where: { conversationId_userId_questionId: { conversationId, userId, questionId: a.questionId } },
            create: { conversationId, userId, questionId: a.questionId, optionKey: a.optionKey },
            update: { optionKey: a.optionKey },
          }),
        ),
      );
    } catch (e) {
      throw fromPgError(e) ?? e;
    }
    const p = await this.progress(conversationId);
    const done = [...p.values()].filter((x) => x.total > 0 && x.answered === x.total).length;
    if (done === 2) await this.finish(userId, peerId, conversationId);
    else this.events.emit('compat', { conversationId, userIds: [userId, peerId] });
    return this.state(userId, conversationId);
  }

  private async finish(userId: string, peerId: string, conversationId: string) {
    const answers = await this.prisma.compatAnswer.findMany({ where: { conversationId }, include: { question: true } });
    const defs = [...new Map(answers.map((a) => [a.questionId, this.toDef(a.question)])).values()];
    const of = (u: string) => Object.fromEntries(answers.filter((a) => a.userId === u).map((a) => [a.questionId, a.optionKey]));
    const outcome = scoreCompat(defs, of(userId), of(peerId));
    let messageId: string | null = null;
    try {
      messageId = await this.prisma.$transaction(async (tx) => {
        // the card takes its place in the message order like any message
        const m = await tx.message.create({ data: { conversationId, senderId: userId, clientMessageId: randomUUID(), type: 'COMPAT', body: '' } });
        await tx.messageReceipt.create({ data: { messageId: m.id, userId: peerId } });
        await tx.compatResult.create({
          data: { conversationId, score: outcome.score, breakdown: { domains: outcome.domains, agreed: outcome.agreed, talkAbout: outcome.talkAbout } as unknown as Prisma.InputJsonValue, messageId: m.id },
        });
        return m.id;
      });
    } catch (e) {
      const err = fromPgError(e);
      if (err?.code === ErrorCode.CONFLICT) return; // the other person's request finished it first
      throw err ?? e;
    }
    const out = await this.messaging.messageOut(messageId);
    this.events.emit('message', { conversationId, userIds: [userId, peerId], message: out });
    for (const u of [userId, peerId]) await this.notifications.push(u, 'push.compat_ready', { conversationId }).catch((e: unknown) => this.log.warn(`push failed: ${String(e)}`));
  }

  // ───────────── admin ─────────────

  questions() {
    return this.prisma.compatQuestion.findMany({
      orderBy: [{ domain: 'asc' }, { sortOrder: 'asc' }],
      include: { _count: { select: { answers: true } } },
    });
  }

  async createQuestion(dto: QuestionDto, admin: AuthAdmin) {
    try {
      const q = await this.prisma.compatQuestion.create({ data: { ...dto, prompt: { ...dto.prompt }, options: dto.options as unknown as Prisma.InputJsonValue } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'compat.question_created', entityType: 'compat_question', entityId: q.id, after: dto as unknown as Prisma.InputJsonValue });
      return q;
    } catch (e) {
      throw fromPgError(e) ?? e;
    }
  }

  async updateQuestion(id: string, dto: QuestionDto, admin: AuthAdmin) {
    const before = await this.prisma.compatQuestion.findUnique({ where: { id } });
    if (!before) throw new AppError(ErrorCode.NOT_FOUND);
    try {
      const q = await this.prisma.compatQuestion.update({ where: { id }, data: { ...dto, prompt: { ...dto.prompt }, options: dto.options as unknown as Prisma.InputJsonValue } });
      await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'compat.question_updated', entityType: 'compat_question', entityId: id, before: before as unknown as Prisma.InputJsonValue, after: dto as unknown as Prisma.InputJsonValue });
      return q;
    } catch (e) {
      throw fromPgError(e) ?? e;
    }
  }

  async setActive(id: string, active: boolean, admin: AuthAdmin) {
    await this.prisma.compatQuestion.update({ where: { id }, data: { active } }).catch(() => { throw new AppError(ErrorCode.NOT_FOUND); });
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: active ? 'compat.question_on' : 'compat.question_off', entityType: 'compat_question', entityId: id });
  }

  async setEnabled(enabled: boolean, admin: AuthAdmin) {
    await this.settings.set('compat.enabled', enabled, admin.id);
    await this.audit.record({ actorType: 'ADMIN', actorId: admin.id, action: 'settings.compat', entityType: 'system_setting', entityId: 'compat.enabled', after: { enabled } });
  }

  /** Aggregates only — never anybody's answers. */
  async stats() {
    const [[t], buckets, domains, perQuestion, enabled] = await Promise.all([
      this.prisma.$queryRaw<{ started: number; finished: number; avg: number | null; last30: number; finished30: number }[]>`
        SELECT (SELECT count(*)::int FROM compat_sessions) AS started,
               (SELECT count(*)::int FROM compat_results) AS finished,
               (SELECT round(avg(score))::int FROM compat_results) AS avg,
               (SELECT count(*)::int FROM compat_sessions WHERE created_at > now() - interval '30 days') AS last30,
               (SELECT count(*)::int FROM compat_results WHERE computed_at > now() - interval '30 days') AS "finished30"`,
      this.prisma.$queryRaw<{ bucket: string; n: number }[]>`
        SELECT CASE WHEN score >= 80 THEN '80-100' WHEN score >= 60 THEN '60-79' WHEN score >= 40 THEN '40-59' ELSE '0-39' END AS bucket, count(*)::int AS n
        FROM compat_results GROUP BY 1`,
      this.prisma.$queryRaw<{ domain: string; avg: number }[]>`
        SELECT d->>'domain' AS domain, round(avg((d->>'score')::int))::int AS avg
        FROM compat_results r, jsonb_array_elements(r.breakdown->'domains') d GROUP BY 1`,
      this.prisma.$queryRaw<{ question_id: string; answers: number }[]>`SELECT question_id, count(*)::int AS answers FROM compat_answers GROUP BY 1`,
      this.settings.get('compat.enabled', true),
    ]);
    return {
      enabled,
      started: t.started,
      finished: t.finished,
      completionRate: t.started ? Math.round((100 * t.finished) / t.started) : 0,
      averageScore: t.avg,
      last30Days: { started: t.last30, finished: t.finished30 },
      distribution: ['0-39', '40-59', '60-79', '80-100'].map((b) => ({ bucket: b, count: buckets.find((x) => x.bucket === b)?.n ?? 0 })),
      domains: COMPAT_DOMAINS.map((d) => ({ domain: d, averageScore: domains.find((x) => x.domain === d)?.avg ?? null })),
      answersPerQuestion: Object.fromEntries(perQuestion.map((r) => [r.question_id, r.answers])),
    };
  }
}

// ───────────── controllers ─────────────

@ApiTags('compatibility')
@ApiBearerAuth()
@Controller('v1/conversations')
export class CompatController {
  constructor(private readonly compat: CompatService) {}

  @MembersOnly() @Get(':id/compat')
  state(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.compat.state(u.id, id);
  }

  @MembersOnly() @RateLimit(20, 3600) @Post(':id/compat/start') @HttpCode(200)
  start(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.compat.start(u.id, id);
  }

  @MembersOnly() @RateLimit(240, 3600) @Put(':id/compat/answers') @HttpCode(200)
  answer(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: AnswersDto) {
    return this.compat.answer(u.id, id, dto);
  }
}

@ApiTags('admin')
@ApiBearerAuth()
@Controller('v1/admin/compat')
export class AdminCompatController {
  constructor(private readonly compat: CompatService) {}

  @RequirePermissions('settings.manage') @Get('questions')
  questions() {
    return this.compat.questions();
  }

  @RequirePermissions('settings.manage') @Post('questions')
  create(@Body() dto: QuestionDto, @CurrentAdmin() a: AuthAdmin) {
    return this.compat.createQuestion(dto, a);
  }

  @RequirePermissions('settings.manage') @Put('questions/:id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: QuestionDto, @CurrentAdmin() a: AuthAdmin) {
    return this.compat.updateQuestion(id, dto, a);
  }

  @RequirePermissions('settings.manage') @Post('questions/:id/active') @HttpCode(204)
  setActive(@Param('id', ParseUUIDPipe) id: string, @Body() dto: ActiveDto, @CurrentAdmin() a: AuthAdmin) {
    return this.compat.setActive(id, dto.active, a);
  }

  @RequirePermissions('settings.manage') @Put('enabled') @HttpCode(204)
  setEnabled(@Body() dto: ActiveDto, @CurrentAdmin() a: AuthAdmin) {
    return this.compat.setEnabled(dto.active, a);
  }

  @RequirePermissions('users.read') @Get('stats')
  stats() {
    return this.compat.stats();
  }
}

@Module({
  imports: [MessagingModule, NotificationsModule],
  controllers: [CompatController, AdminCompatController],
  providers: [CompatService],
})
export class CompatModule {}
