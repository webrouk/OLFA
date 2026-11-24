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

  /// Returns true when the store reports the payment as pending.
  Future<bool> purchase(PlanCode plan) async {
    final from = state.valueOrNull?.plan;
    final pending = await ref.read(subscriptionRepositoryProvider).purchase(plan, from: from);
    await refresh();
    ref.invalidate(storeSubscriptionProvider);
    ref.invalidate(paymentsProvider);
    return pending;
  }

  /// Returns how many subscriptions were restored.
  Future<int> restore() async {
    final n = await ref.read(subscriptionRepositoryProvider).restore();
    await refresh();
    ref.invalidate(storeSubscriptionProvider);
    ref.invalidate(paymentsProvider);
    return n;
  }
}

final entitlementsProvider = AsyncNotifierProvider<EntitlementsController, Entitlements>(EntitlementsController.new);

final plansProvider = FutureProvider<List<PlanInfo>>((ref) => ref.watch(subscriptionRepositoryProvider).plans());

final storeSubscriptionProvider = FutureProvider<StoreSubscription?>((ref) => ref.watch(subscriptionRepositoryProvider).storeSubscription());

/// Keeps the store transaction listener alive while signed in, so renewals,
/// Ask to Buy approvals and interrupted purchases reach the server.
final storeListenerProvider = Provider<void>((ref) {
  final repo = ref.watch(subscriptionRepositoryProvider);
  if (repo is ApiSubscriptionRepository) repo.start().ignore();
});

final paymentsProvider = FutureProvider<List<PaymentRecord>>((ref) => ref.watch(subscriptionRepositoryProvider).payments());
