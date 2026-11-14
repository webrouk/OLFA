import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../core/security/secure_store.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';

abstract interface class SettingsRepository {
  Future<PrivacySettings> privacy();
  Future<void> updatePrivacy(PrivacySettings s);
  Future<int> blockedCount();
  Future<void> report(String userId, String reason, {bool block = false});
  Future<void> block(String userId);

  /// Hides the account immediately; permanent deletion after 30 days.
  Future<void> requestDeletion(String? reason);
}

const _reportReasons = {
  'fake': 'FAKE_PROFILE',
  'photos': 'INAPPROPRIATE_PHOTO',
  'harassment': 'HARASSMENT',
  'scam': 'SPAM_SCAM',
  'underage': 'UNDERAGE',
  'not_serious': 'NOT_SERIOUS',
};

class ApiSettingsRepository implements SettingsRepository {
  ApiSettingsRepository(this._api, this._store, this._localPrivacy);
  final ApiClient _api;
  final SecureStore _store;
  // Privacy toggles are persisted server-side in the admin/privacy phase;
  // until then they live on the device.
  final DemoBackend _localPrivacy;

  @override
  Future<PrivacySettings> privacy() async => _localPrivacy.privacy;
  @override
  Future<void> updatePrivacy(PrivacySettings s) async => _localPrivacy.privacy = s;

  @override
  Future<int> blockedCount() => guard(() async => ((await _api.dio.get<List<dynamic>>('/blocks')).data ?? const []).length);

  @override
  Future<void> report(String userId, String reason, {bool block = false}) =>
      guard(() => _api.dio.post<void>('/reports', data: {'userId': userId, 'reason': _reportReasons[reason] ?? 'OTHER', 'block': block}));

  @override
  Future<void> block(String userId) => guard(() => _api.dio.post<void>('/blocks', data: {'userId': userId}));

  @override
  Future<void> requestDeletion(String? reason) => guard(() async {
        await _api.dio.delete<void>('/me', data: {if (reason != null) 'reason': reason});
        await _store.clear();
      });
}

class DemoSettingsRepository implements SettingsRepository {
  DemoSettingsRepository(this._b);
  final DemoBackend _b;
  @override
  Future<PrivacySettings> privacy() => _b.getPrivacy();
  @override
  Future<void> updatePrivacy(PrivacySettings s) => _b.setPrivacy(s);
  @override
  Future<int> blockedCount() => _b.blockedCount();
  @override
  Future<void> report(String userId, String reason, {bool block = false}) => _b.report(userId, reason, block: block);
  @override
  Future<void> block(String userId) => _b.block(userId);
  @override
  Future<void> requestDeletion(String? reason) => _b.requestDeletion(reason);
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => useApi
      ? ApiSettingsRepository(ref.watch(apiClientProvider), ref.watch(secureStoreProvider), ref.watch(demoBackendProvider))
      : DemoSettingsRepository(ref.watch(demoBackendProvider)),
);

/// Privacy toggles with optimistic update + rollback on server refusal.
class PrivacyController extends AsyncNotifier<PrivacySettings> {
  @override
  Future<PrivacySettings> build() => ref.watch(settingsRepositoryProvider).privacy();

  Future<bool> change(PrivacySettings next) async {
    final prev = state.valueOrNull;
    state = AsyncData(next);
    try {
      await ref.read(settingsRepositoryProvider).updatePrivacy(next);
      return true;
    } catch (_) {
      if (prev != null) state = AsyncData(prev);
      return false;
    }
  }
}

final privacyProvider = AsyncNotifierProvider<PrivacyController, PrivacySettings>(PrivacyController.new);

final blockedCountProvider = FutureProvider<int>((ref) => ref.watch(settingsRepositoryProvider).blockedCount());
