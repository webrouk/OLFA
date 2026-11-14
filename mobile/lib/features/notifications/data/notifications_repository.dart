import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> list();
  Future<void> markAllRead();
}

/// Server stores i18n keys; titles are rendered client-side in the user's language.
class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository(this._api, this._title);
  final ApiClient _api;
  final String Function(String key) _title;

  @override
  Future<List<AppNotification>> list() => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/notifications');
        return r.data!.map((x) {
          final j = Map<String, dynamic>.from(x as Map);
          return AppNotification(
            id: j['id'] as String,
            kind: ApiMappers.notificationKind(j['type'] as String),
            title: _title(j['titleKey'] as String),
            createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
            read: j['readAt'] != null,
          );
        }).toList();
      });

  @override
  Future<void> markAllRead() => guard(() => _api.dio.post<void>('/notifications/read-all'));
}

class DemoNotificationsRepository implements NotificationsRepository {
  DemoNotificationsRepository(this._b);
  final DemoBackend _b;
  @override
  Future<List<AppNotification>> list() => _b.notifications();
  @override
  Future<void> markAllRead() => _b.markAllNotificationsRead();
}

/// Maps server keys (push.new_match.title …) to short localised titles.
String notificationTitle(String lang, String key) {
  const ar = {
    'push.new_match.title': 'توافق جديد',
    'push.new_like.title': 'إعجاب جديد',
    'push.new_message.title': 'رسالة جديدة',
    'push.verification_approved.title': 'تم اعتماد ملفك',
    'push.verification_rejected.title': 'نحتاج بعض التعديلات على ملفك',
  };
  const en = {
    'push.new_match.title': "It's a match",
    'push.new_like.title': 'New like',
    'push.new_message.title': 'New message',
    'push.verification_approved.title': 'Your profile is approved',
    'push.verification_rejected.title': 'Your profile needs a few changes',
  };
  return (lang == 'ar' ? ar : en)[key] ?? key;
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  if (!useApi) return DemoNotificationsRepository(ref.watch(demoBackendProvider));
  final lang = ref.watch(localeProvider).languageCode;
  return ApiNotificationsRepository(ref.watch(apiClientProvider), (k) => notificationTitle(lang, k));
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) => ref.watch(notificationsRepositoryProvider).list());
