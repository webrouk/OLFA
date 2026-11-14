import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../core/security/secure_store.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/auth_repository.dart';

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api, this._store);
  final ApiClient _api;
  final SecureStore _store;

  @override
  Future<OtpChallenge> requestOtp({required Country country, required String nationalNumber}) => guard(() async {
        final r = await _api.dio.post<Map<String, dynamic>>(
          '/auth/otp/request',
          data: {'dialCode': country.dial, 'nationalNumber': nationalNumber, 'country': country.iso, 'deviceId': await _store.deviceId()},
          options: ApiClient.public(),
        );
        final d = r.data!;
        return OtpChallenge(
          id: d['challengeId'] as String,
          expiresIn: Duration(seconds: (d['expiresInSeconds'] as num).toInt()),
          resendAfter: Duration(seconds: (d['resendAfterSeconds'] as num).toInt()),
        );
      });

  @override
  Future<AuthResult> verifyOtp(OtpChallenge challenge, String code) => guard(() async {
        final r = await _api.dio.post<Map<String, dynamic>>(
          '/auth/otp/verify',
          data: {
            'challengeId': challenge.id,
            'code': code,
            'deviceId': await _store.deviceId(),
            'platform': kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android'),
            'timezone': await _timezone(), // IANA, e.g. Asia/Dubai — quotas reset at local midnight
          }..removeWhere((_, v) => v == null),
          options: ApiClient.public(),
        );
        final d = r.data!;
        await _store.saveTokens(access: d['accessToken'] as String, refresh: d['refreshToken'] as String);
        return AuthResult(isNewUser: d['isNewUser'] as bool, accountStatus: d['accountStatus'] as String, profileComplete: d['profileComplete'] as bool);
      });

  Future<String?> _timezone() async {
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      return null; // server falls back to UTC
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _api.dio.post<void>('/auth/logout');
    } finally {
      await _store.clear();
    }
  }
}

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository(this._b);
  final DemoBackend _b;

  @override
  Future<OtpChallenge> requestOtp({required Country country, required String nationalNumber}) async {
    await _b.requestOtp('${country.dial}${nationalNumber.replaceAll(RegExp(r'\D'), '')}');
    return const OtpChallenge(id: 'demo', expiresIn: Duration(minutes: 5), resendAfter: Duration(seconds: 45));
  }

  @override
  Future<AuthResult> verifyOtp(OtpChallenge challenge, String code) async {
    await _b.verifyOtp(code);
    return const AuthResult(isNewUser: true, accountStatus: 'PENDING_VERIFICATION', profileComplete: false);
  }

  @override
  Future<void> logout() async {}
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => useApi ? ApiAuthRepository(ref.watch(apiClientProvider), ref.watch(secureStoreProvider)) : DemoAuthRepository(ref.watch(demoBackendProvider)),
);
