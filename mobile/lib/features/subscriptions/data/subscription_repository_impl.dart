import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/subscription_repository.dart';

/// Entitlements and quotas always come from the server; the app never decides
/// what a plan allows.
class ApiSubscriptionRepository implements SubscriptionRepository {
  ApiSubscriptionRepository(this._api);
  final ApiClient _api;

  @override
  Future<Entitlements> entitlements() => guard(() async {
        final r = await _api.dio.get<Map<String, dynamic>>('/me/entitlements');
        return ApiMappers.entitlements(r.data!);
      });

  @override
  Future<List<PlanInfo>> plans() => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/plans', options: ApiClient.public());
        return r.data!.map((j) => ApiMappers.plan(Map<String, dynamic>.from(j as Map))).toList();
      });

  /// Store purchases (StoreKit / Play Billing + server receipt validation)
  /// are delivered in the payments phase.
  @override
  Future<Entitlements> purchase(PlanCode plan) async => throw const ServerFailure('purchase_unavailable');

  @override
  Future<Entitlements> restore() => entitlements();

  @override
  Future<List<PaymentRecord>> payments() => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/me/payments');
        return r.data!.map((x) {
          final j = Map<String, dynamic>.from(x as Map);
          final plan = ((j['subscription'] as Map?)?['plan'] as Map?)?['code'];
          return PaymentRecord(
            id: j['id'] as String,
            plan: fromApiEnum(PlanCode.values, plan, PlanCode.plus),
            store: switch (j['provider']) { 'APPLE' => 'App Store', 'GOOGLE' => 'Google Play', _ => 'Web' },
            date: DateTime.parse(j['createdAt'] as String).toLocal(),
            status: switch (j['status']) { 'REFUNDED' => PaymentStatus.refunded, 'FAILED' => PaymentStatus.failed, _ => PaymentStatus.succeeded },
          );
        }).toList();
      });
}

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

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => useApi ? ApiSubscriptionRepository(ref.watch(apiClientProvider)) : DemoSubscriptionRepository(ref.watch(demoBackendProvider)),
);
