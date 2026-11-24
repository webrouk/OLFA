import '../../../shared/models/models.dart';

abstract interface class SubscriptionRepository {
  Future<Entitlements> entitlements();

  /// Plans with quotas from the server and prices from the store.
  Future<List<PlanInfo>> plans();

  /// Store subscription as the server last verified it; null on Free.
  Future<StoreSubscription?> storeSubscription();

  /// Opens the store sheet; the server verifies the receipt before anything
  /// changes. Upgrades apply now; downgrades start at the next renewal (store
  /// rules). Returns true when the store reports the payment as pending
  /// (Ask to Buy / slow payment method).
  Future<bool> purchase(PlanCode plan, {PlanCode? from});

  /// Restores this Apple ID / Google account's purchases; returns how many
  /// subscriptions the server re-attached.
  Future<int> restore();
  Future<List<PaymentRecord>> payments();
}
