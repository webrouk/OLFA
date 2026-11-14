import { Controller, Get, Global, HttpCode, Inject, Injectable, Logger, Module, OnModuleInit, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { NotificationType, Prisma } from '@prisma/client';
import { App, cert, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { ENV, Env } from '../../config/env';
import { AllowPending, AuthUser, CurrentUser } from '../../common/http';
import { PrismaService } from '../../common/infra';

/** Server-rendered push texts (the in-app list is rendered client-side from keys). */
const PUSH_TEXT: Record<string, { ar: [string, string]; en: [string, string] }> = {
  'push.new_match': { ar: ['توافق جديد', 'أعجب كلٌّ منكما بالآخر — ابدأ المحادثة'], en: ["It's a match", 'You both liked each other — say hello'] },
  'push.new_like': { ar: ['إعجاب جديد', 'أعجب شخص بملفك'], en: ['New like', 'Someone liked your profile'] },
  'push.new_message': { ar: ['رسالة جديدة', 'لديك رسالة جديدة'], en: ['New message', 'You have a new message'] },
  'push.verification_approved': { ar: ['تم اعتماد ملفك', 'ملفك ظاهر الآن لمن يناسبك'], en: ['Profile approved', 'Your profile is now live'] },
  'push.verification_rejected': { ar: ['نحتاج بعض التعديلات', 'راجع سبب الرفض وأعد الإرسال'], en: ['Changes needed', 'See why and resubmit'] },
};

@Injectable()
export class NotificationsService implements OnModuleInit {
  private readonly log = new Logger('Notifications');
  private fcm: App | null = null;

  constructor(private readonly prisma: PrismaService, @Inject(ENV) private readonly env: Env) {}

  onModuleInit() {
    if (this.env.FCM_CREDENTIALS_JSON) {
      this.fcm = initializeApp({ credential: cert(JSON.parse(this.env.FCM_CREDENTIALS_JSON)) }, 'olfa');
    } else {
      this.log.warn('FCM not configured: notifications are stored but not pushed');
    }
  }

  /** Stores the notification and pushes it to the user's active devices. */
  async notify(userId: string, type: NotificationType, key: string, data: Record<string, string> = {}, tx?: Prisma.TransactionClient) {
    const db = tx ?? this.prisma;
    await db.notification.create({ data: { userId, type, titleKey: `${key}.title`, bodyKey: `${key}.body`, data } });
    if (!tx) await this.push(userId, key, data);
  }

  /** Call after the surrounding transaction commits. */
  async push(userId: string, key: string, data: Record<string, string>) {
    if (!this.fcm) return;
    const [user, sessions] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: userId }, select: { locale: true } }),
      this.prisma.userSession.findMany({ where: { userId, revokedAt: null, fcmToken: { not: null } }, select: { id: true, fcmToken: true } }),
    ]);
    if (sessions.length === 0) return;
    const text = PUSH_TEXT[key]?.[user?.locale ?? 'ar'];
    const res = await getMessaging(this.fcm).sendEachForMulticast({
      tokens: sessions.map((s) => s.fcmToken!),
      notification: text ? { title: text[0], body: text[1] } : undefined,
      data: { type: key, ...data },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    // Drop tokens FCM reports as invalid.
    const dead = res.responses.map((r, i) => (!r.success && /registration-token-not-registered|invalid-argument/.test(r.error?.code ?? '') ? sessions[i].id : null)).filter(Boolean) as string[];
    if (dead.length) await this.prisma.userSession.updateMany({ where: { id: { in: dead } }, data: { fcmToken: null } });
  }

  list(userId: string, before?: Date) {
    return this.prisma.notification.findMany({
      where: { userId, ...(before ? { createdAt: { lt: before } } : {}) },
      orderBy: { createdAt: 'desc' },
      take: 30,
      select: { id: true, type: true, titleKey: true, bodyKey: true, params: true, data: true, readAt: true, createdAt: true },
    });
  }

  markAllRead(userId: string) {
    return this.prisma.notification.updateMany({ where: { userId, readAt: null }, data: { readAt: new Date() } });
  }
}

@ApiTags('notifications')
@ApiBearerAuth()
@Controller('v1/notifications')
export class NotificationsController {
  constructor(private readonly n: NotificationsService) {}

  @AllowPending() @Get()
  list(@CurrentUser() u: AuthUser, @Query('before') before?: string) {
    return this.n.list(u.id, before ? new Date(before) : undefined);
  }

  @AllowPending() @Post('read-all') @HttpCode(204)
  async readAll(@CurrentUser() u: AuthUser) {
    await this.n.markAllRead(u.id);
  }
}

@Global()
@Module({ controllers: [NotificationsController], providers: [NotificationsService], exports: [NotificationsService] })
export class NotificationsModule {}
