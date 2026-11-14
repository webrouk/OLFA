import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../shared/models/models.dart';
import '../data/auth_repository_impl.dart';
import '../domain/auth_repository.dart';

class AuthState {
  const AuthState({
    this.country = const Country('AE', '+971', '🇦🇪', 'الإمارات العربية المتحدة', 'United Arab Emirates', 'AE'),
    this.nationalNumber = '',
    this.busy = false,
    this.failure,
    this.resendAt,
    this.attemptsLeft = 5,
    this.challenge,
    this.result,
  });

  final Country country;
  final String nationalNumber;
  final bool busy;
  final Failure? failure;
  final DateTime? resendAt;
  final int attemptsLeft;
  final OtpChallenge? challenge;
  final AuthResult? result;

  String get e164 => '${country.dial}${nationalNumber.replaceAll(RegExp(r'\D'), '')}';

  /// Masked for display: +971 50 *** **67
  String get masked {
    final d = nationalNumber.replaceAll(RegExp(r'\D'), '');
    if (d.length < 4) return '${country.dial} $d';
    return '${country.dial} ${d.substring(0, 2)} *** **${d.substring(d.length - 2)}';
  }

  AuthState copyWith({Country? country, String? nationalNumber, bool? busy, Failure? Function()? failure, DateTime? resendAt, int? attemptsLeft, OtpChallenge? challenge, AuthResult? result}) => AuthState(
        country: country ?? this.country,
        nationalNumber: nationalNumber ?? this.nationalNumber,
        busy: busy ?? this.busy,
        failure: failure != null ? failure() : this.failure,
        resendAt: resendAt ?? this.resendAt,
        attemptsLeft: attemptsLeft ?? this.attemptsLeft,
        challenge: challenge ?? this.challenge,
        result: result ?? this.result,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  void setCountry(Country c) => state = state.copyWith(country: c, failure: () => null);
  void setNumber(String n) => state = state.copyWith(nationalNumber: n, failure: () => null);

  bool get phoneValid {
    final d = state.nationalNumber.replaceAll(RegExp(r'\D'), '');
    return d.length >= 7 && d.length <= 12;
  }

  /// Returns true on success. Guards against double submission.
  Future<bool> requestOtp() async {
    if (state.busy) return false;
    final now = DateTime.now();
    if (state.resendAt != null && now.isBefore(state.resendAt!)) return false;
    state = state.copyWith(busy: true, failure: () => null);
    try {
      final c = await ref.read(authRepositoryProvider).requestOtp(country: state.country, nationalNumber: state.nationalNumber);
      state = state.copyWith(busy: false, challenge: c, resendAt: DateTime.now().add(c.resendAfter), attemptsLeft: 5);
      return true;
    } on OtpRateLimitedFailure catch (f) {
      state = state.copyWith(busy: false, failure: () => f, resendAt: DateTime.now().add(f.retryAfter));
      return false;
    } on Failure catch (f) {
      state = state.copyWith(busy: false, failure: () => f);
      return false;
    }
  }

  Future<bool> verify(String code) async {
    final c = state.challenge;
    if (state.busy || code.length != 6 || c == null) return false;
    state = state.copyWith(busy: true, failure: () => null);
    try {
      final r = await ref.read(authRepositoryProvider).verifyOtp(c, code);
      state = state.copyWith(busy: false, result: r);
      return true;
    } on InvalidOtpFailure catch (f) {
      state = state.copyWith(busy: false, failure: () => f, attemptsLeft: f.attemptsLeft);
      return false;
    } on Failure catch (f) {
      state = state.copyWith(busy: false, failure: () => f);
      return false;
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
