import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../data/subscription_repository_impl.dart';

/// Current plan + daily quotas, sourced from the server. The UI may update it
/// optimistically after an action, but every refresh re-reads the server.
class EntitlementsController extends AsyncNotifier<Entitlements> {
  @override
  Future<Entitlements> build() => ref.watch(subscriptionRepositoryProvider).entitlements();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(subscriptionRepositoryProvider).entitlements());
  }

  void applyLocal(Entitlements Function(Entitlements e) f) {
    final cur = state.valueOrNull;
    if (cur != null) state = AsyncData(f(cur));
  }

  Future<void> purchase(PlanCode plan) async {
    final e = await ref.read(subscriptionRepositoryProvider).purchase(plan);
    state = AsyncData(e);
    ref.invalidate(paymentsProvider);
  }

  Future<void> restore() async {
    state = AsyncData(await ref.read(subscriptionRepositoryProvider).restore());
  }
}

final entitlementsProvider = AsyncNotifierProvider<EntitlementsController, Entitlements>(EntitlementsController.new);

final plansProvider = FutureProvider<List<PlanInfo>>((ref) => ref.watch(subscriptionRepositoryProvider).plans());

final paymentsProvider = FutureProvider<List<PaymentRecord>>((ref) => ref.watch(subscriptionRepositoryProvider).payments());
