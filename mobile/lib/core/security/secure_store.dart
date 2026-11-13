import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens live only in Keychain / Android Keystore — never in prefs or logs.
class SecureStore {
  SecureStore(this._s);
  final FlutterSecureStorage _s;

  static const _access = 'olfa.access';
  static const _refresh = 'olfa.refresh';

  Future<String?> readAccessToken() => _s.read(key: _access);
  Future<String?> readRefreshToken() => _s.read(key: _refresh);
  Future<void> saveTokens({required String access, required String refresh}) async {
    await _s.write(key: _access, value: access);
    await _s.write(key: _refresh, value: refresh);
  }

  Future<void> clear() => _s.deleteAll();
}

final secureStoreProvider = Provider<SecureStore>((_) => SecureStore(const FlutterSecureStorage()));
