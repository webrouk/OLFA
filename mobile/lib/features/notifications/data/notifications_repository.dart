import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> list({DateTime? before});
  Future<void> markAllRead();
  Future<void> markRead(String id);
  Future<void> remove(String id);
}

/// The server stores i18n keys; titles and bodies are rendered on the device
/// in the user's language (so switching language re-renders old ones too).
class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository(this._api, this._lang);
  final ApiClient _api;
  final String _lang;

  @override
  Future<List<AppNotification>> list({DateTime? before}) => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/notifications', queryParameters: {if (before != null) 'before': before.toUtc().toIso8601String()});
        return r.data!.map((x) {
          final j = Map<String, dynamic>.from(x as Map);
          final key = (j['titleKey'] as String).replaceAll(RegExp(r'\.title$'), '');
          final (title, body) = notificationText(_lang, key);
          return AppNotification(
            id: j['id'] as String,
            kind: ApiMappers.notificationKind(j['type'] as String),
            title: title,
            body: body,
            data: Map<String, dynamic>.from(j['data'] as Map? ?? const {}).map((k, v) => MapEntry(k, '$v')),
            createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
            read: j['readAt'] != null,
          );
        }).toList();
      });

  @override
  Future<void> markAllRead() => guard(() => _api.dio.post<void>('/notifications/read-all'));
  @override
  Future<void> markRead(String id) => guard(() => _api.dio.post<void>('/notifications/$id/read'));
  @override
  Future<void> remove(String id) => guard(() => _api.dio.delete<void>('/notifications/$id'));
}

class DemoNotificationsRepository implements NotificationsRepository {
  DemoNotificationsRepository(this._b);
  final DemoBackend _b;
  @override
  Future<List<AppNotification>> list({DateTime? before}) => _b.notifications();
  @override
  Future<void> markAllRead() => _b.markAllNotificationsRead();
  @override
  Future<void> markRead(String id) => _b.markNotificationRead(id);
  @override
  Future<void> remove(String id) => _b.removeNotification(id);
}

/// Server key (push.new_match …) → (title, body) in the user's language.
/// Generated from PUSH_TEXT in backend/src/modules/notifications (same 25 keys).
(String, String?) notificationText(String lang, String key) {
  const ar = <String, (String, String)>{
    'push.new_match': ('توافق جديد', 'أعجب كلٌّ منكما بالآخر — ابدأ المحادثة'),
    'push.new_like': ('إعجاب جديد', 'أعجب شخص بملفك'),
    'push.new_message': ('رسالة جديدة', 'لديك رسالة جديدة'),
    'push.new_photo': ('صورة جديدة', 'أرسل إليك صورة'),
    'push.new_voice': ('رسالة صوتية', 'وصلتك رسالة صوتية'),
    'push.verification_approved': ('تم اعتماد ملفك', 'ملفك ظاهر الآن لمن يناسبك'),
    'push.verification_rejected': ('نحتاج بعض التعديلات', 'راجع سبب الرفض وأعد الإرسال'),
    'push.new_compliment': ('رسالة إطراء', 'وصلك إطراء مع إعجاب — اطّلع عليه'),
    'push.rematch_request': ('طلب إعادة تطابق', 'يرغب شخص في إعادة التطابق معك'),
    'push.rematch_accepted': ('تمت إعادة التطابق', 'المحادثة مفتوحة من جديد'),
    'push.conversation_expiring': ('محادثة ستُحذف قريبًا', 'أرسل رسالة لتبقى المحادثة'),
    'push.consultation_request': ('طلب استشارة مدفوع', 'لديك طلب جديد بانتظار التأكيد'),
    'push.consultation_confirmed': ('تم تأكيد استشارتك', 'يمكنك الآن التحدث مع الاستشاري'),
    'push.consultation_declined': ('اعتذر الاستشاري', 'سيُسترد المبلغ كاملًا'),
    'push.consultation_completed': ('اكتملت الجلسة', 'شاركنا تقييمك للاستشاري'),
    'push.counselor_approved': ('تم اعتماد ملفك كاستشاري', 'أضف أسعارك لاستقبال الطلبات'),
    'push.counselor_rejected': ('طلب الاستشاري', 'راجع ملاحظات المراجعة'),
    'push.review_required': ('كيف كانت جلستك؟', 'أجب عن أسئلة التقييم القصيرة — تقييمك يحمي المجتمع'),
    'push.integrity_case': ('مراجعة التزام بسياسة المختصين', 'نحتاج ردّك خلال 7 أيام — افتح لوحة المستشار'),
    'push.integrity_decision': ('قرار المراجعة', 'اطّلع على نتيجة المراجعة في لوحة المستشار'),
    'push.withdrawal_paid': ('تم تحويل أرباحك', 'أُرسل طلب السحب إلى حسابك'),
    'push.withdrawal_rejected': ('تعذّر تنفيذ طلب السحب', 'أُعيد المبلغ إلى محفظتك — راجع التفاصيل'),
    'push.earning_available': ('أرباح متاحة للسحب', 'انتهت فترة الانتظار وأصبحت أرباحك متاحة'),
    'push.subscription_billing_issue': ('مشكلة في تجديد الاشتراك', 'حدّث طريقة الدفع في المتجر لتستمر مزاياك'),
    'push.subscription_expired': ('انتهى اشتراكك', 'يمكنك التجديد في أي وقت من صفحة الخطط'),
  };
  const en = <String, (String, String)>{
    'push.new_match': ('It\'s a match', 'You both liked each other — say hello'),
    'push.new_like': ('New like', 'Someone liked your profile'),
    'push.new_message': ('New message', 'You have a new message'),
    'push.new_photo': ('New photo', 'You received a photo'),
    'push.new_voice': ('Voice message', 'You received a voice message'),
    'push.verification_approved': ('Profile approved', 'Your profile is now live'),
    'push.verification_rejected': ('Changes needed', 'See why and resubmit'),
    'push.new_compliment': ('A compliment for you', 'Someone liked you and left a compliment'),
    'push.rematch_request': ('Re-match request', 'Someone would like to match again'),
    'push.rematch_accepted': ('Matched again', 'Your chat is open again'),
    'push.conversation_expiring': ('A chat expires soon', 'Send a message to keep it'),
    'push.consultation_request': ('Paid consultation request', 'A new request is waiting for you'),
    'push.consultation_confirmed': ('Consultation confirmed', 'You can now chat with your counselor'),
    'push.consultation_declined': ('Counselor declined', 'You will be refunded in full'),
    'push.consultation_completed': ('Session completed', 'Rate your counselor'),
    'push.counselor_approved': ('Counselor profile approved', 'Add your prices to receive requests'),
    'push.counselor_rejected': ('Counselor application', 'See the review notes'),
    'push.review_required': ('How was your session?', 'Answer the short review — it keeps the community safe'),
    'push.integrity_case': ('Professional policy review', 'Please respond within 7 days — open your desk'),
    'push.integrity_decision': ('Review decision', 'See the outcome in your desk'),
    'push.withdrawal_paid': ('Payout sent', 'Your withdrawal was sent to your account'),
    'push.withdrawal_rejected': ('Withdrawal not completed', 'The amount is back in your wallet — see details'),
    'push.earning_available': ('Earnings available', 'Your earnings are now available to withdraw'),
    'push.subscription_billing_issue': ('Subscription payment issue', 'Update your payment method in the store to keep your plan'),
    'push.subscription_expired': ('Your subscription ended', 'Renew any time from Plans'),
  };
  const fr = <String, (String, String)>{
    'push.new_match': ('C’est réciproque', 'Vous vous plaisez mutuellement — dites bonjour'),
    'push.new_like': ('Nouveau j’aime', 'Quelqu’un a aimé votre profil'),
    'push.new_message': ('Nouveau message', 'Vous avez un nouveau message'),
    'push.new_photo': ('Nouvelle photo', 'Vous avez reçu une photo'),
    'push.new_voice': ('Message vocal', 'Vous avez reçu un message vocal'),
    'push.verification_approved': ('Profil approuvé', 'Votre profil est maintenant en ligne'),
    'push.verification_rejected': ('Modifications nécessaires', 'Voyez pourquoi et renvoyez-le'),
    'push.new_compliment': ('Un compliment pour vous', 'Quelqu’un vous a aimé(e) et a laissé un compliment'),
    'push.rematch_request': ('Demande de reprise', 'Quelqu’un souhaite renouer l’affinité'),
    'push.rematch_accepted': ('Affinité rétablie', 'Votre conversation est de nouveau ouverte'),
    'push.conversation_expiring': ('Une conversation expire bientôt', 'Envoyez un message pour la garder'),
    'push.consultation_request': ('Demande de consultation payée', 'Une nouvelle demande vous attend'),
    'push.consultation_confirmed': ('Consultation confirmée', 'Vous pouvez maintenant échanger avec votre conseiller'),
    'push.consultation_declined': ('Le conseiller a refusé', 'Vous serez remboursé(e) intégralement'),
    'push.consultation_completed': ('Séance terminée', 'Évaluez votre conseiller'),
    'push.counselor_approved': ('Profil de conseiller approuvé', 'Ajoutez vos tarifs pour recevoir des demandes'),
    'push.counselor_rejected': ('Candidature de conseiller', 'Consultez les remarques de l’examen'),
    'push.review_required': ('Comment s’est passée votre séance ?', 'Répondez au court questionnaire — il protège la communauté'),
    'push.integrity_case': ('Examen de conformité professionnelle', 'Merci de répondre sous 7 jours — ouvrez votre bureau'),
    'push.integrity_decision': ('Décision de l’examen', 'Consultez le résultat dans votre bureau'),
    'push.withdrawal_paid': ('Versement envoyé', 'Votre retrait a été envoyé sur votre compte'),
    'push.withdrawal_rejected': ('Retrait non effectué', 'Le montant est de retour dans votre portefeuille — voir les détails'),
    'push.earning_available': ('Gains disponibles', 'Vos gains peuvent maintenant être retirés'),
    'push.subscription_billing_issue': ('Problème de paiement de l’abonnement', 'Mettez à jour votre moyen de paiement dans la boutique pour garder votre offre'),
    'push.subscription_expired': ('Votre abonnement a pris fin', 'Renouvelez à tout moment depuis les Offres'),
  };
  final t = (switch (lang) { 'ar' => ar, 'fr' => fr, _ => en })[key];
  return t == null ? (key, null) : (t.$1, t.$2);
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  if (!useApi) return DemoNotificationsRepository(ref.watch(demoBackendProvider));
  return ApiNotificationsRepository(ref.watch(apiClientProvider), ref.watch(localeProvider).languageCode);
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) => ref.watch(notificationsRepositoryProvider).list());

final unreadNotificationsProvider = Provider<int>((ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0);
