import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => DemoSettingsRepository(ref.watch(demoBackendProvider)));

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
