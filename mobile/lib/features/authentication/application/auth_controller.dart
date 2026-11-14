import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../shared/models/models.dart';
import '../data/auth_repository_impl.dart';

class AuthState {
  const AuthState({
    this.country = const Country('AE', '+971', '🇦🇪', 'الإمارات', 'United Arab Emirates'),
    this.nationalNumber = '',
    this.busy = false,
    this.failure,
    this.resendAt,
    this.attemptsLeft = 5,
  });

  final Country country;
  final String nationalNumber;
  final bool busy;
  final Failure? failure;
  final DateTime? resendAt;
  final int attemptsLeft;

  String get e164 => '${country.dial}${nationalNumber.replaceAll(RegExp(r'\D'), '')}';

  /// Masked for display: +971 50 *** **67
  String get masked {
    final d = nationalNumber.replaceAll(RegExp(r'\D'), '');
    if (d.length < 4) return '${country.dial} $d';
    return '${country.dial} ${d.substring(0, 2)} *** **${d.substring(d.length - 2)}';
  }

  AuthState copyWith({Country? country, String? nationalNumber, bool? busy, Failure? Function()? failure, DateTime? resendAt, int? attemptsLeft}) => AuthState(
        country: country ?? this.country,
        nationalNumber: nationalNumber ?? this.nationalNumber,
        busy: busy ?? this.busy,
        failure: failure != null ? failure() : this.failure,
        resendAt: resendAt ?? this.resendAt,
        attemptsLeft: attemptsLeft ?? this.attemptsLeft,
      );
}

class AuthController extends Notifier<AuthState> {
  static const resendCooldown = Duration(seconds: 45);

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
      await ref.read(authRepositoryProvider).requestOtp(state.e164);
      state = state.copyWith(busy: false, resendAt: DateTime.now().add(resendCooldown), attemptsLeft: 5);
      return true;
    } on Failure catch (f) {
      state = state.copyWith(busy: false, failure: () => f);
      return false;
    }
  }

  Future<bool> verify(String code) async {
    if (state.busy || code.length != 6) return false;
    state = state.copyWith(busy: true, failure: () => null);
    try {
      await ref.read(authRepositoryProvider).verifyOtp(state.e164, code);
      state = state.copyWith(busy: false);
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
