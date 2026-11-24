import 'dart:async';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../../../core/errors/failure.dart';
import '../../../shared/models/models.dart';

/// What the server needs to verify a store purchase. The app never decides
/// what a purchase is worth: it hands the signed transaction (Apple, StoreKit 2
/// JWS) or the purchase token (Google) to the server, which asks the store.
class StoreReceipt {
  const StoreReceipt({required this.apple, required this.productId, required this.token});
  final bool apple;
  final String productId;
  final String token;
}

/// Outcome of a purchase sheet. `pending` covers Ask to Buy (iOS) and slow
/// payment methods (Google): the plan starts when the store approves it and
/// the server is told by the store's own notification.
enum PurchaseOutcome { completed, pending }

/// Thin port over `in_app_purchase` so the repository stays testable and the
/// demo build never touches a store.
///
/// Rules this class enforces:
/// * a transaction is finished (`completePurchase`) only **after** the server
///   accepted it — if delivery fails, the store re-delivers it on next launch
///   (Apple keeps unfinished transactions; Google returns unacknowledged ones);
/// * the account id is attached to every purchase (`appAccountToken` /
///   `obfuscatedAccountId`) so a receipt can't be claimed by another account;
/// * upgrades/downgrades on Google replace the old subscription
///   (upgrade: immediately with time proration; downgrade: at renewal);
///   on Apple the subscription group handles it.
class StoreBilling {
  StoreBilling({required this.deliver});

  /// Sends a receipt to the server; throws a [Failure] if it is rejected.
  final Future<void> Function(StoreReceipt r) deliver;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Map<String, Completer<PurchaseOutcome>> _waiting = {};
  List<StoreReceipt>? _restoring;
  final List<PurchaseDetails> _restoredUnfinished = [];

  static bool get isApple => Platform.isIOS || Platform.isMacOS;

  /// Call once after sign-in. Unfinished transactions from an earlier run are
  /// delivered here too.
  Future<void> start() async {
    if (_sub != null) return;
    if (isApple) await InAppPurchaseStoreKitPlatform.enableStoreKit2();
    _sub = _iap.purchaseStream.listen(_onUpdates, onError: (_) {});
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<Map<String, ProductDetails>> products(Iterable<String> ids) async {
    if (!await _iap.isAvailable()) return {};
    final r = await _iap.queryProductDetails(ids.toSet());
    final out = <String, ProductDetails>{};
    // Google returns one entry per base plan/offer; keep the first (base plan).
    for (final p in r.productDetails) {
      out.putIfAbsent(p.id, () => p);
    }
    return out;
  }

  Future<PurchaseOutcome> buy({
    required String productId,
    required String accountToken,
    required bool isUpgrade,
  }) async {
    await start();
    if (!await _iap.isAvailable()) throw const ServerFailure('store_unavailable');
    final details = (await products([productId]))[productId];
    if (details == null) throw const ServerFailure('product_unavailable');

    final PurchaseParam param;
    if (!isApple) {
      final old = await _activeGooglePurchase(except: productId);
      param = GooglePlayPurchaseParam(
        productDetails: details,
        applicationUserName: accountToken,
        changeSubscriptionParam: old == null
            ? null
            : ChangeSubscriptionParam(
                oldPurchaseDetails: old,
                replacementMode: isUpgrade ? ReplacementMode.withTimeProration : ReplacementMode.deferred,
              ),
      );
    } else {
      param = PurchaseParam(productDetails: details, applicationUserName: accountToken);
    }

    final done = Completer<PurchaseOutcome>();
    _waiting[productId] = done;
    try {
      final started = await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) throw const ServerFailure('purchase_cancelled');
      return await done.future.timeout(const Duration(minutes: 10), onTimeout: () => PurchaseOutcome.pending);
    } finally {
      _waiting.remove(productId);
    }
  }

  /// Collects the store's purchases for this Apple ID / Google account. The
  /// caller sends them to the server in one restore call.
  Future<List<StoreReceipt>> restore() async {
    await start();
    if (!await _iap.isAvailable()) throw const ServerFailure('store_unavailable');
    final found = _restoring = <StoreReceipt>[];
    try {
      await _iap.restorePurchases();
      // The store answers through the purchase stream; wait until it is quiet.
      var last = found.length;
      for (var i = 0; i < 16; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (i >= 3 && found.length == last) break;
        last = found.length;
      }
      return List.of(found);
    } finally {
      _restoring = null;
    }
  }

  /// Finishes restored transactions once the server has accepted them.
  Future<void> finishRestored() async {
    final list = List.of(_restoredUnfinished);
    _restoredUnfinished.clear();
    for (final p in list) {
      await _finish(p);
    }
  }

  Future<GooglePlayPurchaseDetails?> _activeGooglePurchase({required String except}) async {
    final add = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final r = await add.queryPastPurchases();
    for (final p in r.pastPurchases) {
      if (p.productID != except && (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored)) return p;
    }
    return null;
  }

  Future<void> _onUpdates(List<PurchaseDetails> list) async {
    for (final p in list) {
      final waiter = _waiting[p.productID];
      switch (p.status) {
        case PurchaseStatus.pending:
          if (waiter != null && !waiter.isCompleted) waiter.complete(PurchaseOutcome.pending);
        case PurchaseStatus.canceled:
          await _finish(p);
          if (waiter != null && !waiter.isCompleted) waiter.completeError(const ServerFailure('purchase_cancelled'));
        case PurchaseStatus.error:
          await _finish(p);
          if (waiter != null && !waiter.isCompleted) waiter.completeError(const ServerFailure('purchase_failed'));
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          final receipt = StoreReceipt(apple: isApple, productId: p.productID, token: p.verificationData.serverVerificationData);
          if (_restoring != null && p.status == PurchaseStatus.restored) {
            _restoring!.add(receipt);
            _restoredUnfinished.add(p); // finished after the server accepts the restore
            continue;
          }
          try {
            await deliver(receipt);
            await _finish(p);
            if (waiter != null && !waiter.isCompleted) waiter.complete(PurchaseOutcome.completed);
          } catch (e) {
            // Not finished on purpose: the store will hand it back next launch.
            if (waiter != null && !waiter.isCompleted) waiter.completeError(e is Failure ? e : const ServerFailure('store_verification_failed'));
          }
      }
    }
  }

  Future<void> _finish(PurchaseDetails p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(p);
    } catch (_) {
      // Google: the server may have acknowledged first — nothing to do.
    }
  }
}

/// Store product id for a plan on this platform, from the server's catalogue.
String? productIdFor(List<StoreProductRef> catalogue, PlanCode plan) {
  final provider = StoreBilling.isApple ? 'APPLE' : 'GOOGLE';
  for (final c in catalogue) {
    if (c.plan == plan && c.provider == provider) return c.productId;
  }
  return null;
}
