import '../../../shared/models/models.dart';

class OtpChallenge {
  const OtpChallenge({required this.id, required this.expiresIn, required this.resendAfter});
  final String id;
  final Duration expiresIn;
  final Duration resendAfter;
}

class AuthResult {
  const AuthResult({required this.isNewUser, required this.accountStatus, required this.profileComplete});
  final bool isNewUser;
  final String accountStatus; // PENDING_VERIFICATION | ACTIVE | REJECTED | …
  final bool profileComplete;
}

abstract interface class AuthRepository {
  /// POST /v1/auth/otp/request
  Future<OtpChallenge> requestOtp({required Country country, required String nationalNumber});

  /// POST /v1/auth/otp/verify — stores the session tokens on success.
  Future<AuthResult> verifyOtp(OtpChallenge challenge, String code);

  Future<void> logout();
}
