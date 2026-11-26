import '../../../shared/models/models.dart';

/// Counselor wallet: earnings (net of the 15% platform commission), the
/// hold period, payout destinations and withdrawal requests. The server owns
/// the ledger; the app only reads it and asks for withdrawals.
abstract interface class WalletRepository {
  /// GET /v1/wallet
  Future<WalletSummary> summary();

  /// GET /v1/wallet/entries
  Future<List<WalletEntry>> entries();

  /// GET /v1/wallet/payout-methods
  Future<List<PayoutMethod>> payoutMethods();

  /// POST /v1/wallet/payout-methods — details are sealed on the server; only a mask comes back.
  Future<PayoutMethod> addPayoutMethod(PayoutMethodDraft d);

  /// DELETE /v1/wallet/payout-methods/:id
  Future<void> removePayoutMethod(String id);

  /// POST /v1/wallet/withdrawals
  Future<Withdrawal> withdraw({required String payoutMethodId, required String currency, required int amountMinor});

  /// GET /v1/wallet/withdrawals
  Future<List<Withdrawal>> withdrawals();

  /// POST /v1/wallet/withdrawals/:id/cancel
  Future<void> cancelWithdrawal(String id);
}
