import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/demo_backend.dart';
import '../domain/auth_repository.dart';

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository(this._b);
  final DemoBackend _b;

  @override
  Future<void> requestOtp(String e164) => _b.requestOtp(e164);

  @override
  Future<void> verifyOtp(String e164, String code) => _b.verifyOtp(code);
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => DemoAuthRepository(ref.watch(demoBackendProvider)));
