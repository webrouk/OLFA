/// Domain-level failures thrown by repositories and surfaced to presentation.
/// Each carries a stable [code] that the UI maps to a localised message.
sealed class Failure implements Exception {
  const Failure(this.code);
  final String code;

  @override
  String toString() => 'Failure($code)';
}

class NetworkFailure extends Failure {
  const NetworkFailure() : super('network');
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure() : super('unauthorized');
}

class InvalidOtpFailure extends Failure {
  const InvalidOtpFailure(this.attemptsLeft) : super('otp_invalid');
  final int attemptsLeft;
}

class OtpRateLimitedFailure extends Failure {
  const OtpRateLimitedFailure(this.retryAfter) : super('otp_rate_limited');
  final Duration retryAfter;
}

/// Daily quota exhausted (likes, conversation starters, undos).
class QuotaExceededFailure extends Failure {
  const QuotaExceededFailure(this.quota) : super('quota');
  final String quota; // likes | messages | undos
}

/// The server refused a paid feature for the current plan.
class EntitlementRequiredFailure extends Failure {
  const EntitlementRequiredFailure(this.feature) : super('entitlement');
  final String feature;
}

/// Duplicate action (e.g. liking the same profile twice).
class AlreadyActedFailure extends Failure {
  const AlreadyActedFailure() : super('duplicate');
}

class ValidationFailure extends Failure {
  const ValidationFailure(this.field) : super('validation');
  final String field;
}

class ServerFailure extends Failure {
  const ServerFailure([super.code = 'server']);
}
