import 'package:dio/dio.dart';

import '../errors/failure.dart';

/// Maps backend error envelopes `{ error: { code, details } }` (see backend
/// src/common/errors.ts) to typed domain failures.
Failure toFailure(Object e, {String quota = 'likes'}) {
  if (e is Failure) return e;
  if (e is! DioException) return const ServerFailure();
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.response == null) {
    return const NetworkFailure();
  }
  final body = e.response?.data;
  final err = body is Map ? body['error'] : null;
  final code = err is Map ? err['code'] as String? : null;
  final details = err is Map && err['details'] is Map ? Map<String, dynamic>.from(err['details'] as Map) : const <String, dynamic>{};
  int? intOf(String k) => details[k] is num ? (details[k] as num).toInt() : null;

  return switch (code) {
    'UNAUTHORIZED' => const UnauthorizedFailure(),
    'OTP_INVALID' => InvalidOtpFailure(intOf('attemptsLeft') ?? 0),
    'OTP_LOCKED' => const InvalidOtpFailure(0),
    'OTP_EXPIRED' => const ServerFailure('otp_expired'),
    'OTP_COOLDOWN' || 'RATE_LIMITED' => OtpRateLimitedFailure(Duration(seconds: intOf('retryAfter') ?? 30)),
    'QUOTA_EXCEEDED' => QuotaExceededFailure(quota),
    'ENTITLEMENT_REQUIRED' => EntitlementRequiredFailure(details['feature'] as String? ?? 'advancedFilters'),
    'DUPLICATE' => const AlreadyActedFailure(),
    'VALIDATION' || 'UNDERAGE' || 'UPLOAD_INVALID' => ValidationFailure(details['field'] as String? ?? code!.toLowerCase()),
    'NOT_ELIGIBLE' => const ServerFailure('not_eligible'),
    'BLOCKED' => const ServerFailure('blocked'),
    'ACCOUNT_NOT_ACTIVE' => const ServerFailure('account_not_active'),
    'NOT_FOUND' => const ServerFailure('not_found'),
    'CONVERSATION_CLOSED' => const ServerFailure('conversation_closed'),
    'CONVERSATION_LOCKED' => const EntitlementRequiredFailure('visibleConversations'),
    'REMATCH_USED' => const ServerFailure('rematch_used'),
    'INVALID_STATE' => const ServerFailure('invalid_state'),
    'NOT_PAID' => const ServerFailure('not_paid'),
    'CONFLICT' => const ServerFailure('conflict'),
    _ => const ServerFailure(),
  };
}

/// Runs an API call and rethrows any error as a [Failure].
Future<T> guard<T>(Future<T> Function() call, {String quota = 'likes'}) async {
  try {
    return await call();
  } catch (e) {
    throw toFailure(e, quota: quota);
  }
}
