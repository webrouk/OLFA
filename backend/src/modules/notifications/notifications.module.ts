import { Controller, Delete, Get, Global, HttpCode, Inject, Injectable, Logger, Module, OnModuleInit, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { NotificationType, Prisma } from '@prisma/client';
import { App, cert, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { ENV, Env } from '../../config/env';
import { AllowPending, AuthUser, CurrentUser } from '../../common/http';
import { PrismaService } from '../../common/infra';
import { AppLocaleCode, asLocale } from '../../domain/locale';

/** Server-rendered push texts (the in-app list is rendered client-side from keys). */
const PUSH_TEXT: Record<string, Record<AppLocaleCode, [string, string]>> = {
  'push.support_reply': { ar: ['رد من الدعم', 'وصل رد جديد على طلب الدعم الخاص بك'], en: ['Support replied', 'There is a new reply to your support request'], fr: ['Réponse du support', 'Votre demande d’assistance a reçu une réponse'] },
  'push.escrow_released': { ar: ['تم تحويل أجر الاستشارة', 'أكّد العميل الجلسة وقيّمها — أُضيف المبلغ إلى محفظتك'], en: ['Consultation fee released', 'The client confirmed and rated the session — the amount is in your wallet'], fr: ['Honoraires débloqués', 'Le client a confirmé et noté la séance — le montant est dans votre portefeuille'] },
  'push.review_reminder': { ar: ['قيّم جلستك', 'أكّد حدوث الاستشارة وقيّم المستشار ليتم تحويل الأجر'], en: ['Rate your session', 'Confirm the consultation took place and rate the counselor to release the fee'], fr: ['Notez votre séance', 'Confirmez la consultation et notez le conseiller pour débloquer le paiement'] },
  'push.escrow_disputed': { ar: ['استشارة قيد المراجعة', 'أفاد العميل بأن الجلسة لم تتم — سيتواصل معك فريق الدعم'], en: ['Consultation under review', 'The client reported the session did not happen — support will contact you'], fr: ['Consultation en examen', 'Le client indique que la séance n’a pas eu lieu — le support vous contactera'] },
  'push.new_match': { ar: ['توافق جديد', 'أعجب كلٌّ منكما بالآخر — ابدأ المحادثة'], en: ["It's a match", 'You both liked each other — say hello'], fr: ['C’est réciproque', 'Vous vous plaisez mutuellement — dites bonjour'] },
  'push.new_like': { ar: ['إعجاب جديد', 'أعجب شخص بملفك'], en: ['New like', 'Someone liked your profile'], fr: ['Nouveau j’aime', 'Quelqu’un a aimé votre profil'] },
  'push.new_message': { ar: ['رسالة جديدة', 'لديك رسالة جديدة'], en: ['New message', 'You have a new message'], fr: ['Nouveau message', 'Vous avez un nouveau message'] },
  'push.new_photo': { ar: ['صورة جديدة', 'أرسل إليك صورة'], en: ['New photo', 'You received a photo'], fr: ['Nouvelle photo', 'Vous avez reçu une photo'] },
  'push.new_voice': { ar: ['رسالة صوتية', 'وصلتك رسالة صوتية'], en: ['Voice message', 'You received a voice message'], fr: ['Message vocal', 'Vous avez reçu un message vocal'] },
  'push.verification_approved': { ar: ['تم اعتماد ملفك', 'ملفك ظاهر الآن لمن يناسبك'], en: ['Profile approved', 'Your profile is now live'], fr: ['Profil approuvé', 'Votre profil est maintenant en ligne'] },
  'push.verification_rejected': { ar: ['نحتاج بعض التعديلات', 'راجع سبب الرفض وأعد الإرسال'], en: ['Changes needed', 'See why and resubmit'], fr: ['Modifications nécessaires', 'Voyez pourquoi et renvoyez-le'] },
  'push.new_compliment': { ar: ['رسالة إطراء', 'وصلك إطراء مع إعجاب — اطّلع عليه'], en: ['A compliment for you', 'Someone liked you and left a compliment'], fr: ['Un compliment pour vous', 'Quelqu’un vous a aimé(e) et a laissé un compliment'] },
  'push.rematch_request': { ar: ['طلب إعادة تطابق', 'يرغب شخص في إعادة التطابق معك'], en: ['Re-match request', 'Someone would like to match again'], fr: ['Demande de reprise', 'Quelqu’un souhaite renouer l’affinité'] },
  'push.rematch_accepted': { ar: ['تمت إعادة التطابق', 'المحادثة مفتوحة من جديد'], en: ['Matched again', 'Your chat is open again'], fr: ['Affinité rétablie', 'Votre conversation est de nouveau ouverte'] },
  'push.compat_started': { ar: ['أسئلة التوافق', 'بدأ الطرف الآخر أسئلة التوافق في محادثتكما'], en: ['Compatibility questions', 'Your match started the compatibility questions in your chat'], fr: ['Questions de compatibilité', 'Votre affinité a commencé les questions de compatibilité'] },
  'push.compat_ready': { ar: ['نتيجة التوافق جاهزة', 'أكملتما الأسئلة — النتيجة في المحادثة'], en: ['Compatibility result ready', 'You both finished — the result is in your chat'], fr: ['Résultat de compatibilité prêt', 'Vous avez terminé tous les deux — le résultat est dans la conversation'] },
  'push.conversation_expiring': { ar: ['محادثة ستُحذف قريبًا', 'أرسل رسالة لتبقى المحادثة'], en: ['A chat expires soon', 'Send a message to keep it'], fr: ['Une conversation expire bientôt', 'Envoyez un message pour la garder'] },
  'push.consultation_request': { ar: ['طلب استشارة مدفوع', 'لديك طلب جديد بانتظار التأكيد'], en: ['Paid consultation request', 'A new request is waiting for you'], fr: ['Demande de consultation payée', 'Une nouvelle demande vous attend'] },
  'push.consultation_confirmed': { ar: ['تم تأكيد استشارتك', 'يمكنك الآن التحدث مع الاستشاري'], en: ['Consultation confirmed', 'You can now chat with your counselor'], fr: ['Consultation confirmée', 'Vous pouvez maintenant échanger avec votre conseiller'] },
  'push.consultation_declined': { ar: ['اعتذر الاستشاري', 'سيُسترد المبلغ كاملًا'], en: ['Counselor declined', 'You will be refunded in full'], fr: ['Le conseiller a refusé', 'Vous serez remboursé(e) intégralement'] },
  'push.consultation_completed': { ar: ['اكتملت الجلسة', 'شاركنا تقييمك للاستشاري'], en: ['Session completed', 'Rate your counselor'], fr: ['Séance terminée', 'Évaluez votre conseiller'] },
  'push.counselor_approved': { ar: ['تم اعتماد ملفك كاستشاري', 'أضف أسعارك لاستقبال الطلبات'], en: ['Counselor profile approved', 'Add your prices to receive requests'], fr: ['Profil de conseiller approuvé', 'Ajoutez vos tarifs pour recevoir des demandes'] },
  'push.counselor_rejected': { ar: ['طلب الاستشاري', 'راجع ملاحظات المراجعة'], en: ['Counselor application', 'See the review notes'], fr: ['Candidature de conseiller', 'Consultez les remarques de l’examen'] },
  'push.review_required': { ar: ['كيف كانت جلستك؟', 'أجب عن أسئلة التقييم القصيرة — تقييمك يحمي المجتمع'], en: ['How was your session?', 'Answer the short review — it keeps the community safe'], fr: ['Comment s’est passée votre séance ?', 'Répondez au court questionnaire — il protège la communauté'] },
  'push.integrity_case': { ar: ['مراجعة التزام بسياسة المختصين', 'نحتاج ردّك خلال 7 أيام — افتح لوحة المستشار'], en: ['Professional policy review', 'Please respond within 7 days — open your desk'], fr: ['Examen de conformité professionnelle', 'Merci de répondre sous 7 jours — ouvrez votre bureau'] },
  'push.integrity_decision': { ar: ['قرار المراجعة', 'اطّلع على نتيجة المراجعة في لوحة المستشار'], en: ['Review decision', 'See the outcome in your desk'], fr: ['Décision de l’examen', 'Consultez le résultat dans votre bureau'] },
  'push.withdrawal_paid': { ar: ['تم تحويل أرباحك', 'أُرسل طلب السحب إلى حسابك'], en: ['Payout sent', 'Your withdrawal was sent to your account'], fr: ['Versement envoyé', 'Votre retrait a été envoyé sur votre compte'] },
  'push.withdrawal_rejected': { ar: ['تعذّر تنفيذ طلب السحب', 'أُعيد المبلغ إلى محفظتك — راجع التفاصيل'], en: ['Withdrawal not completed', 'The amount is back in your wallet — see details'], fr: ['Retrait non effectué', 'Le montant est de retour dans votre portefeuille — voir les détails'] },
  'push.earning_available': { ar: ['أرباح متاحة للسحب', 'انتهت فترة الانتظار وأصبحت أرباحك متاحة'], en: ['Earnings available', 'Your earnings are now available to withdraw'], fr: ['Gains disponibles', 'Vos gains peuvent maintenant être retirés'] },
  'push.subscription_billing_issue': { ar: ['مشكلة في تجديد الاشتراك', 'حدّث طريقة الدفع في المتجر لتستمر مزاياك'], en: ['Subscription payment issue', 'Update your payment method in the store to keep your plan'], fr: ['Problème de paiement de l’abonnement', 'Mettez à jour votre moyen de paiement dans la boutique pour garder votre offre'] },
  'push.subscription_expired': { ar: ['انتهى اشتراكك', 'يمكنك التجديد في أي وقت من صفحة الخطط'], en: ['Your subscription ended', 'Renew any time from Plans'], fr: ['Votre abonnement a pris fin', 'Renouvelez à tout moment depuis les Offres'] },
};

/** Message sounds vs. everything else; a match / compliment gets the warm chime. */
export function soundFor(key: string): { ios: string; android: string; channel: string } {
  if (key === 'push.new_message' || key === 'push.new_photo' || key === 'push.new_voice') return { ios: 'olfa_message.wav', android: 'olfa_message', channel: 'olfa_messages' };
  if (key === 'push.new_match' || key === 'push.new_compliment' || key === 'push.rematch_accepted') return { ios: 'olfa_match.wav', android: 'olfa_match', channel: 'olfa_matches' };
  return { ios: 'olfa_notification.wav', android: 'olfa_notification', channel: 'olfa_general' };
}

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
    const text = PUSH_TEXT[key]?.[asLocale(user?.locale)];
    const res = await getMessaging(this.fcm).sendEachForMulticast({
      tokens: sessions.map((s) => s.fcmToken!),
      notification: text ? { title: text[0], body: text[1] } : undefined,
      data: { type: key, ...data },
      // OLFA's own sounds (bundled in the app): one for messages, one for everything else.
      apns: { payload: { aps: { sound: soundFor(key).ios, 'thread-id': data.conversationId ?? key } } },
      android: { notification: { channelId: soundFor(key).channel, sound: soundFor(key).android, tag: data.conversationId } },
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

  markRead(userId: string, id: string) {
    return this.prisma.notification.updateMany({ where: { id, userId, readAt: null }, data: { readAt: new Date() } });
  }

  remove(userId: string, id: string) {
    return this.prisma.notification.deleteMany({ where: { id, userId } });
  }

  unreadCount(userId: string) {
    return this.prisma.notification.count({ where: { userId, readAt: null } });
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

  @AllowPending() @Get('unread-count')
  async unread(@CurrentUser() u: AuthUser) {
    return { count: await this.n.unreadCount(u.id) };
  }

  @AllowPending() @Post('read-all') @HttpCode(204)
  async readAll(@CurrentUser() u: AuthUser) {
    await this.n.markAllRead(u.id);
  }

  @AllowPending() @Post(':id/read') @HttpCode(204)
  async readOne(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.n.markRead(u.id, id);
  }

  @AllowPending() @Delete(':id') @HttpCode(204)
  async remove(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.n.remove(u.id, id);
  }
}

@Global()
@Module({ controllers: [NotificationsController], providers: [NotificationsService], exports: [NotificationsService] })
export class NotificationsModule {}
