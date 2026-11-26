import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/subscription_repository.dart';
import 'store_billing.dart';

/// Entitlements and quotas always come from the server; the app never decides
/// what a plan allows.
class ApiSubscriptionRepository implements SubscriptionRepository {
  ApiSubscriptionRepository(this._api) {
    _store = StoreBilling(deliver: _deliver);
  }
  final ApiClient _api;
  late final StoreBilling _store;
  List<StoreProductRef>? _catalogue;

  /// Starts listening for store transactions (renewals finished on another
  /// device, Ask to Buy approvals, purchases interrupted by a crash).
  Future<void> start() => _store.start();

  Future<void> _deliver(StoreReceipt r) => guard(() async {
        if (r.apple) {
          await _api.dio.post<void>('/subscriptions/apple', data: {'signedTransaction': r.token});
        } else {
          await _api.dio.post<void>('/subscriptions/google', data: {'productId': r.productId, 'purchaseToken': r.token});
        }
      });

  Future<List<StoreProductRef>> _products() async => _catalogue ??= await guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/subscriptions/products', options: ApiClient.public());
        return [
          for (final x in r.data!)
            StoreProductRef(
              plan: fromApiEnum(PlanCode.values, (x as Map)['plan'], PlanCode.free),
              provider: x['provider'] as String,
              productId: x['productId'] as String,
            ),
        ];
      });

  Future<Map<String, dynamic>> _me() => guard(() async => (await _api.dio.get<Map<String, dynamic>>('/subscriptions/me')).data!);

  @override
  Future<StoreSubscription?> storeSubscription() async {
    final s = (await _me())['store'] as Map?;
    if (s == null) return null;
    DateTime? d(Object? v) => v is String ? DateTime.parse(v).toLocal() : null;
    return StoreSubscription(
      plan: fromApiEnum(PlanCode.values, s['plan'], PlanCode.plus),
      status: fromApiEnum(StoreSubStatus.values, s['status'], StoreSubStatus.active),
      autoRenew: s['autoRenew'] as bool? ?? true,
      expiresAt: d(s['expiresAt']),
      graceUntil: d(s['graceUntil']),
      pendingPlan: s['pendingPlan'] == null ? null : fromApiEnum(PlanCode.values, s['pendingPlan'], PlanCode.plus),
      isApple: s['provider'] == 'APPLE',
      manageUrl: s['manageUrl'] as String?,
    );
  }

  @override
  Future<bool> purchase(PlanCode plan, {PlanCode? from}) async {
    final id = productIdFor(await _products(), plan);
    if (id == null) throw const ServerFailure('product_unavailable');
    final token = (await _me())['accountToken'] as String;
    final out = await _store.buy(productId: id, accountToken: token, isUpgrade: from == null || plan.index > from.index);
    return out == PurchaseOutcome.pending;
  }

  @override
  Future<int> restore() async {
    final receipts = await _store.restore();
    final r = await guard(() async => (await _api.dio.post<Map<String, dynamic>>('/subscriptions/restore', data: {
          'apple': [for (final x in receipts) if (x.apple) x.token],
          'google': [for (final x in receipts) if (!x.apple) {'productId': x.productId, 'purchaseToken': x.token}],
        }))
            .data!);
    await _store.finishRestored();
    return (r['restored'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<Entitlements> entitlements() => guard(() async {
        final r = await _api.dio.get<Map<String, dynamic>>('/me/entitlements');
        return ApiMappers.entitlements(r.data!);
      });

  @override
  Future<List<PlanInfo>> plans({bool professional = false}) async {
    final plans = await guard(() async {
      final r = await _api.dio.get<List<dynamic>>('/plans', queryParameters: {if (professional) 'audience': 'PROFESSIONAL'}, options: ApiClient.public());
      return r.data!.map((j) => ApiMappers.plan(Map<String, dynamic>.from(j as Map))).toList();
    });
    // Prices are the store's localized prices — never hard-coded.
    try {
      final cat = await _products();
      final ids = {for (final p in plans) p.code: productIdFor(cat, p.code)};
      final store = await _store.products(ids.values.whereType<String>());
      return [
        for (final p in plans)
          ids[p.code] == null
              ? p
              : PlanInfo(
                  code: p.code,
                  dailyLikes: p.dailyLikes,
                  dailyMessages: p.dailyMessages,
                  dailyUndos: p.dailyUndos,
                  advancedFilters: p.advancedFilters,
                  seeWhoLikedYou: p.seeWhoLikedYou,
                  priorityVisibility: p.priorityVisibility,
                  storeProductId: ids[p.code],
                  localizedPrice: store[ids[p.code]]?.price,
                  directoryBoost: p.directoryBoost,
                  featuredBadge: p.featuredBadge,
                  profileInsights: p.profileInsights,
                ),
      ];
    } catch (_) {
      return plans; // store unreachable: show plans without prices; purchase will report it
    }
  }

  @override
  Future<List<PaymentRecord>> payments() => guard(() async {
        final out = <PaymentRecord>[];
        String? cursor;
        do {
          final r = await _api.dio.get<Map<String, dynamic>>('/me/payments', queryParameters: {if (cursor != null) 'cursor': cursor});
          for (final x in r.data!['items'] as List) {
            final j = Map<String, dynamic>.from(x as Map);
            final sub = j['subscription'] as Map?;
            final k = j['consultation'] as Map?;
            out.add(PaymentRecord(
              id: j['id'] as String,
              kind: j['kind'] == 'CONSULTATION' ? PaymentKind.consultation : PaymentKind.subscription,
              plan: fromApiEnum(PlanCode.values, (sub?['plan'] as Map?)?['code'], PlanCode.plus),
              store: switch (j['provider']) { 'APPLE' => 'App Store', 'GOOGLE' => 'Google Play', 'ADMIN_GRANT' => 'OLFA', _ => 'Card' },
              date: DateTime.parse(j['createdAt'] as String).toLocal(),
              status: switch (j['status']) {
                'REFUNDED' => PaymentStatus.refunded,
                'FAILED' => PaymentStatus.failed,
                'PENDING' => PaymentStatus.pending,
                _ => PaymentStatus.succeeded,
              },
              amountMinor: (j['amountMinor'] as num?)?.toInt(),
              currency: j['currency'] as String?,
              reference: j['reference'] as String?,
              refundedAt: j['refundedAt'] is String ? DateTime.parse(j['refundedAt'] as String).toLocal() : null,
              description: k == null ? null : '${k['counselor']} · ${k['durationMinutes']}′',
            ));
          }
          cursor = r.data!['nextCursor'] as String?;
        } while (cursor != null && out.length < 300);
        return out;
      });
}

class DemoSubscriptionRepository implements SubscriptionRepository {
  DemoSubscriptionRepository(this._b);
  final DemoBackend _b;

  @override
  Future<Entitlements> entitlements() => _b.entitlements();
  @override
  Future<List<PlanInfo>> plans({bool professional = false}) => _b.listPlans(professional: professional);
  @override
  Future<StoreSubscription?> storeSubscription() => _b.storeSubscription();
  @override
  Future<bool> purchase(PlanCode plan, {PlanCode? from}) async {
    await _b.changePlan(plan);
    return false;
  }

  @override
  Future<int> restore() => _b.restore();
  @override
  Future<List<PaymentRecord>> payments() => _b.payments();
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => useApi ? ApiSubscriptionRepository(ref.watch(apiClientProvider)) : DemoSubscriptionRepository(ref.watch(demoBackendProvider)),
);
