import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/subscription_repository.dart';

class DemoSubscriptionRepository implements SubscriptionRepository {
  DemoSubscriptionRepository(this._b);
  final DemoBackend _b;

  @override
  Future<Entitlements> entitlements() => _b.entitlements();

  @override
  Future<List<PlanInfo>> plans() => _b.listPlans();

  @override
  Future<Entitlements> purchase(PlanCode plan) async {
    await _b.purchase(plan);
    return _b.entitlements();
  }

  @override
  Future<Entitlements> restore() => _b.entitlements();

  @override
  Future<List<PaymentRecord>> payments() => _b.payments();
}

final subscriptionRepositoryProvider =
    Provider<SubscriptionRepository>((ref) => DemoSubscriptionRepository(ref.watch(demoBackendProvider)));
