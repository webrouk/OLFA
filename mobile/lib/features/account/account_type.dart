import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_errors.dart';
import '../../shared/models/models.dart';
import '../../shared/services/demo_backend.dart';

/// The signed-in account's type. It decides the navigation (marriage tabs vs
/// the counselor workspace) and which screens exist at all; the server applies
/// the same rule to every request.
class AccountTypeController extends Notifier<AccountType?> {
  @override
  AccountType? build() => useApi ? null : ref.read(demoBackendProvider).accountType;

  /// From the sign-in response or GET /me.
  void set(AccountType? t) {
    state = t;
    accountTypeListenable.value = t;
  }

  /// Sign-up step after gender (locked by the server once a profile exists).
  Future<void> choose(AccountType t) async {
    if (useApi) {
      await guard(() => ref.read(apiClientProvider).dio.put<void>('/me/account-type', data: {'accountType': t.api}));
    } else {
      await ref.read(demoBackendProvider).setAccountType(t);
    }
    set(t);
  }

  /// Re-reads it from the server (app start).
  Future<void> refresh() async {
    if (!useApi) {
      set(ref.read(demoBackendProvider).accountType);
      return;
    }
    try {
      final r = await ref.read(apiClientProvider).dio.get<Map<String, dynamic>>('/me');
      set(AccountType.fromApi(r.data?['accountType'] as String?));
    } catch (_) {
      // keep the last known value (offline); the server still enforces the type
    }
  }
}

final accountTypeProvider = NotifierProvider<AccountTypeController, AccountType?>(AccountTypeController.new);

/// Lets the router re-check its redirects when the type changes.
final accountTypeListenable = ValueNotifier<AccountType?>(useApi ? null : AccountType.member);

bool isProfessional(AccountType? t) => t?.isProfessional ?? false;
