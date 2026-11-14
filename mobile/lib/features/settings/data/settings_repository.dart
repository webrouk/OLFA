import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../core/security/secure_store.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';

abstract interface class SettingsRepository {
  Future<PrivacySettings> privacy();
  Future<PrivacySettings> updatePrivacy(PrivacySettings s);
  Future<List<BlockedUser>> blocked();
  Future<void> unblock(String userId);
  Future<int> blockedCount();
  /// [messageId]: report one specific message (moderators see a snapshot of it).
  Future<void> report(String userId, String reason, {bool block = false, String? messageId, String? details});
  Future<void> block(String userId);
  Future<List<DeviceSession>> devices();
  Future<void> signOutDevice(String sessionId);

  /// Take a break: hidden everywhere, everything kept (subscription included).
  Future<void> freeze({String? reason});
  Future<void> unfreeze();

  /// JSON copy of the user's data (GET /me/export).
  Future<String> exportData();

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
  'inappropriate_message': 'HARASSMENT', // offensive / sexual / threatening message
};

class ApiSettingsRepository implements SettingsRepository {
  ApiSettingsRepository(this._api, this._store);
  final ApiClient _api;
  final SecureStore _store;

  @override
  Future<PrivacySettings> privacy() => guard(() async => PrivacySettings.fromJson((await _api.dio.get<Map<String, dynamic>>('/me/privacy')).data!));

  @override
  Future<PrivacySettings> updatePrivacy(PrivacySettings s) =>
      guard(() async => PrivacySettings.fromJson((await _api.dio.put<Map<String, dynamic>>('/me/privacy', data: s.toJson())).data!));

  @override
  Future<List<BlockedUser>> blocked() => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/blocks');
        return r.data!.map((x) {
          final j = Map<String, dynamic>.from(x as Map);
          final b = Map<String, dynamic>.from(j['blocked'] as Map);
          return BlockedUser(userId: b['id'] as String, name: (b['profile'] as Map?)?['displayName'] as String? ?? '—', blockedAt: DateTime.parse(j['createdAt'] as String).toLocal());
        }).toList();
      });

  @override
  Future<void> unblock(String userId) => guard(() => _api.dio.delete<void>('/blocks/$userId'));

  @override
  Future<int> blockedCount() async => (await blocked()).length;

  @override
  Future<void> report(String userId, String reason, {bool block = false, String? messageId, String? details}) => guard(() => _api.dio.post<void>('/reports', data: {
        'userId': userId,
        'reason': _reportReasons[reason] ?? 'OTHER',
        'block': block,
        if (messageId != null) ...{'targetType': 'MESSAGE', 'targetId': messageId},
        if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
      }));

  @override
  Future<void> block(String userId) => guard(() => _api.dio.post<void>('/blocks', data: {'userId': userId}));

  @override
  Future<List<DeviceSession>> devices() => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/auth/sessions');
        return r.data!.map((x) {
          final j = Map<String, dynamic>.from(x as Map);
          return DeviceSession(
            id: j['id'] as String,
            platform: j['platform'] as String? ?? '',
            appVersion: j['appVersion'] as String?,
            createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
            lastUsedAt: DateTime.parse(j['lastUsedAt'] as String).toLocal(),
            current: j['current'] == true,
          );
        }).toList();
      });

  @override
  Future<void> signOutDevice(String sessionId) => guard(() => _api.dio.delete<void>('/auth/sessions/$sessionId'));

  @override
  Future<void> freeze({String? reason}) => guard(() => _api.dio.post<void>('/me/freeze', data: {if (reason != null) 'reason': reason}));

  @override
  Future<void> unfreeze() => guard(() => _api.dio.post<void>('/me/unfreeze'));

  @override
  Future<String> exportData() => guard(() async {
        final r = await _api.dio.get<Map<String, dynamic>>('/me/export');
        return const JsonEncoder.withIndent('  ').convert(r.data);
      });

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
  Future<PrivacySettings> updatePrivacy(PrivacySettings s) => _b.setPrivacy(s);
  @override
  Future<List<BlockedUser>> blocked() => _b.blockedUsers();
  @override
  Future<void> unblock(String userId) => _b.unblock(userId);
  @override
  Future<int> blockedCount() => _b.blockedCount();
  @override
  Future<void> report(String userId, String reason, {bool block = false, String? messageId, String? details}) => _b.report(userId, reason, block: block);
  @override
  Future<void> block(String userId) => _b.block(userId);
  @override
  Future<List<DeviceSession>> devices() => _b.devices();
  @override
  Future<void> signOutDevice(String sessionId) => _b.signOutDevice(sessionId);
  @override
  Future<void> freeze({String? reason}) => _b.freeze();
  @override
  Future<void> unfreeze() => _b.unfreeze();
  @override
  Future<String> exportData() async => '{"demo": true}';
  @override
  Future<void> requestDeletion(String? reason) => _b.requestDeletion(reason);
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => useApi
      ? ApiSettingsRepository(ref.watch(apiClientProvider), ref.watch(secureStoreProvider))
      : DemoSettingsRepository(ref.watch(demoBackendProvider)),
);

/// Privacy toggles with optimistic update + rollback on server refusal.
class PrivacyController extends AsyncNotifier<PrivacySettings> {
  @override
  Future<PrivacySettings> build() => ref.watch(settingsRepositoryProvider).privacy();

  /// Returns null on success, or the failure to show.
  Future<Object?> change(PrivacySettings next) async {
    final prev = state.valueOrNull;
    state = AsyncData(next);
    try {
      state = AsyncData(await ref.read(settingsRepositoryProvider).updatePrivacy(next));
      return null;
    } catch (e) {
      if (prev != null) state = AsyncData(prev);
      return e;
    }
  }
}

final privacyProvider = AsyncNotifierProvider<PrivacyController, PrivacySettings>(PrivacyController.new);

final blockedCountProvider = FutureProvider<int>((ref) => ref.watch(settingsRepositoryProvider).blockedCount());

final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>((ref) => ref.watch(settingsRepositoryProvider).blocked());

final devicesProvider = FutureProvider.autoDispose<List<DeviceSession>>((ref) => ref.watch(settingsRepositoryProvider).devices());
