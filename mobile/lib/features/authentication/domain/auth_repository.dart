abstract interface class AuthRepository {
  /// POST /v1/auth/otp/request
  Future<void> requestOtp(String e164);

  /// POST /v1/auth/otp/verify — stores tokens on success.
  Future<void> verifyOtp(String e164, String code);
}
