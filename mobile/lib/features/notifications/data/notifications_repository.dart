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
/// Mirrors PUSH_TEXT in backend/src/modules/notifications.
(String, String?) notificationText(String lang, String key) {
  const ar = <String, (String, String)>{
    'push.new_match': ('توافق جديد', 'أعجب كلٌّ منكما بالآخر — ابدأ المحادثة'),
    'push.new_like': ('إعجاب جديد', 'أعجب شخص بملفك'),
    'push.new_compliment': ('رسالة إطراء', 'وصلك إطراء مع إعجاب — اطّلع عليه'),
    'push.new_message': ('رسالة جديدة', 'لديك رسالة جديدة'),
    'push.new_photo': ('صورة جديدة', 'أرسل إليك صورة'),
    'push.new_voice': ('رسالة صوتية', 'وصلتك رسالة صوتية'),
    'push.verification_approved': ('تم اعتماد ملفك', 'ملفك ظاهر الآن لمن يناسبك'),
    'push.verification_rejected': ('نحتاج بعض التعديلات', 'راجع سبب الرفض وأعد الإرسال'),
    'push.rematch_request': ('طلب إعادة تطابق', 'يرغب شخص في إعادة التطابق معك'),
    'push.rematch_accepted': ('تمت إعادة التطابق', 'المحادثة مفتوحة من جديد'),
    'push.conversation_expiring': ('محادثة ستُحذف قريبًا', 'أرسل رسالة لتبقى المحادثة'),
    'push.consultation_request': ('طلب استشارة مدفوع', 'لديك طلب جديد بانتظار التأكيد'),
    'push.consultation_confirmed': ('تم تأكيد استشارتك', 'يمكنك الآن التحدث مع الاستشاري'),
    'push.consultation_declined': ('اعتذر الاستشاري', 'سيُسترد المبلغ كاملًا'),
    'push.consultation_completed': ('اكتملت الجلسة', 'شاركنا تقييمك للاستشاري'),
    'push.counselor_approved': ('تم اعتماد ملفك كاستشاري', 'أضف أسعارك لاستقبال الطلبات'),
    'push.counselor_rejected': ('طلب الاستشاري', 'راجع ملاحظات المراجعة'),
  };
  const en = <String, (String, String)>{
    'push.new_match': ("It's a match", 'You both liked each other — say hello'),
    'push.new_like': ('New like', 'Someone liked your profile'),
    'push.new_compliment': ('A compliment for you', 'Someone liked you and left a compliment'),
    'push.new_message': ('New message', 'You have a new message'),
    'push.new_photo': ('New photo', 'You received a photo'),
    'push.new_voice': ('Voice message', 'You received a voice message'),
    'push.verification_approved': ('Profile approved', 'Your profile is now live'),
    'push.verification_rejected': ('Changes needed', 'See why and resubmit'),
    'push.rematch_request': ('Re-match request', 'Someone would like to match again'),
    'push.rematch_accepted': ('Matched again', 'Your chat is open again'),
    'push.conversation_expiring': ('A chat expires soon', 'Send a message to keep it'),
    'push.consultation_request': ('Paid consultation request', 'A new request is waiting for you'),
    'push.consultation_confirmed': ('Consultation confirmed', 'You can now chat with your counselor'),
    'push.consultation_declined': ('Counselor declined', 'You will be refunded in full'),
    'push.consultation_completed': ('Session completed', 'Rate your counselor'),
    'push.counselor_approved': ('Counselor profile approved', 'Add your prices to receive requests'),
    'push.counselor_rejected': ('Counselor application', 'See the review notes'),
  };
  final t = (lang == 'ar' ? ar : en)[key];
  return t == null ? (key, null) : (t.$1, t.$2);
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  if (!useApi) return DemoNotificationsRepository(ref.watch(demoBackendProvider));
  return ApiNotificationsRepository(ref.watch(apiClientProvider), ref.watch(localeProvider).languageCode);
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) => ref.watch(notificationsRepositoryProvider).list());

final unreadNotificationsProvider = Provider<int>((ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0);
