import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/locale_provider.dart';
import '../security/secure_store.dart';
import 'api_errors.dart';

/// `--dart-define=API_BASE_URL=https://api.olfa.app` switches every repository
/// from the demo data source to the real backend. Empty = demo mode.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const useApi = apiBaseUrl != '';

/// Dio with: bearer auth, Accept-Language, and single-flight refresh-token
/// rotation on 401 (the backend revokes the whole family on token reuse).
class ApiClient {
  ApiClient(this._store, this._lang) {
    dio = Dio(BaseOptions(
      baseUrl: '$apiBaseUrl/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      contentType: Headers.jsonContentType,
    ));
    dio.interceptors.add(QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        options.headers['Accept-Language'] = _lang();
        if (options.extra['auth'] != false) {
          final token = await _store.readAccessToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        // Closed by the admin panel → closed-account screen, even outside a repository call.
        final err = e.response?.data is Map ? (e.response!.data as Map)['error'] : null;
        if (err is Map && (err['code'] == 'ACCOUNT_BANNED' || err['code'] == 'ACCOUNT_SUSPENDED')) {
          toFailure(e);
          return handler.next(e);
        }
        final retried = e.requestOptions.extra['retried'] == true;
        if (e.response?.statusCode == 401 && !retried && e.requestOptions.extra['auth'] != false) {
          final ok = await _refresh();
          if (ok) {
            final opts = e.requestOptions..extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer ${await _store.readAccessToken()}';
            opts.headers['Accept-Language'] = _lang();
            try {
              // Retry on a bare client: re-entering this queued interceptor would deadlock.
              return handler.resolve(await Dio(dio.options).fetch(opts));
            } on DioException catch (e2) {
              return handler.next(e2);
            }
          }
          await _store.clear();
          onSessionExpired?.call();
        }
        handler.next(e);
      },
    ));
  }

  final SecureStore _store;
  final String Function() _lang;
  late final Dio dio;
  void Function()? onSessionExpired;
  Future<bool>? _refreshing;

  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final rt = await _store.readRefreshToken();
    if (rt == null) return false;
    try {
      final r = await Dio(BaseOptions(baseUrl: '$apiBaseUrl/v1')).post<Map<String, dynamic>>('/auth/refresh', data: {'refreshToken': rt});
      await _store.saveTokens(access: r.data!['accessToken'] as String, refresh: r.data!['refreshToken'] as String);
      return true;
    } on DioException {
      return false;
    }
  }

  /// Requests that must not carry a token (OTP, plans).
  static Options public() => Options(extra: {'auth': false});
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.read(secureStoreProvider), () => ref.read(localeProvider).languageCode);
});
