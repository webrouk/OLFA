import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/locale_provider.dart';
import '../security/secure_store.dart';

/// API base URL comes from --dart-define=API_BASE_URL=... (never hard-coded keys).
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3000/v1');

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));
  final store = ref.read(secureStoreProvider);
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      options.headers['Accept-Language'] = ref.read(localeProvider).languageCode;
      final token = await store.readAccessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
    // Phase 2: 401 → refresh-token rotation, then retry once.
  ));
  return dio;
});
