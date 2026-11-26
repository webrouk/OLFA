import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens live only in Keychain / Android Keystore — never in prefs or logs.
class SecureStore {
  SecureStore(this._s);
  final FlutterSecureStorage _s;

  static const _access = 'olfa.access';
  static const _refresh = 'olfa.refresh';
  static const _device = 'olfa.device';
  static const _setupDraft = 'olfa.setupDraft';

  Future<String?> readAccessToken() => _s.read(key: _access);
  Future<String?> readRefreshToken() => _s.read(key: _refresh);

  Future<void> saveTokens({required String access, required String refresh}) async {
    await _s.write(key: _access, value: access);
    await _s.write(key: _refresh, value: refresh);
  }

  /// Clears the session (and any unfinished sign-up answers) but keeps the install id.
  Future<void> clear() async {
    await _s.delete(key: _access);
    await _s.delete(key: _refresh);
    await _s.delete(key: _setupDraft);
  }

  /// Unfinished sign-up answers (JSON), encrypted like the tokens.
  Future<String?> readSetupDraft() => _s.read(key: _setupDraft);
  Future<void> writeSetupDraft(String json) => _s.write(key: _setupDraft, value: json);
  Future<void> clearSetupDraft() => _s.delete(key: _setupDraft);

  /// Stable per-install id, used for device-bound OTP and sessions.
  Future<String> deviceId() async {
    final existing = await _s.read(key: _device);
    if (existing != null) return existing;
    final r = Random.secure();
    final id = 'd-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    await _s.write(key: _device, value: id);
    return id;
  }
}

final secureStoreProvider = Provider<SecureStore>((_) => SecureStore(const FlutterSecureStorage()));
