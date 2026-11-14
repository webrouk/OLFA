import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> list();
  Future<void> markAllRead();
}

class DemoNotificationsRepository implements NotificationsRepository {
  DemoNotificationsRepository(this._b);
  final DemoBackend _b;
  @override
  Future<List<AppNotification>> list() => _b.notifications();
  @override
  Future<void> markAllRead() => _b.markAllNotificationsRead();
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => DemoNotificationsRepository(ref.watch(demoBackendProvider)));

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) => ref.watch(notificationsRepositoryProvider).list());
