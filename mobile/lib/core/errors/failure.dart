/// Domain-level failure surfaced to the presentation layer.
sealed class Failure {
  const Failure(this.code);
  final String code; // i18n key, e.g. "errors.network"
}

class NetworkFailure extends Failure {
  const NetworkFailure() : super('errors.network');
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure() : super('errors.unauthorized');
}

class QuotaExceededFailure extends Failure {
  const QuotaExceededFailure(this.resetsAt) : super('errors.quota');
  final DateTime resetsAt;
}

class ServerFailure extends Failure {
  const ServerFailure([super.code = 'errors.server']);
}
