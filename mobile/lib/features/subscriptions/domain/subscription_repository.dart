import '../../../shared/models/models.dart';

abstract interface class SubscriptionRepository {
  Future<Entitlements> entitlements();
  Future<List<PlanInfo>> plans();

  /// Starts the store purchase; the server validates the receipt and returns
  /// the new entitlements. Never trust a client-side purchase result alone.
  Future<Entitlements> purchase(PlanCode plan);
  Future<Entitlements> restore();
  Future<List<PaymentRecord>> payments();
}
