import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../data/wallet_repository_impl.dart';

final walletSummaryProvider = FutureProvider.autoDispose<WalletSummary>((ref) => ref.watch(walletRepositoryProvider).summary());
final walletEntriesProvider = FutureProvider.autoDispose<List<WalletEntry>>((ref) => ref.watch(walletRepositoryProvider).entries());
final payoutMethodsProvider = FutureProvider.autoDispose<List<PayoutMethod>>((ref) => ref.watch(walletRepositoryProvider).payoutMethods());
final withdrawalsProvider = FutureProvider.autoDispose<List<Withdrawal>>((ref) => ref.watch(walletRepositoryProvider).withdrawals());

/// Refresh everything after a wallet change.
void invalidateWallet(Ref ref) {
  ref
    ..invalidate(walletSummaryProvider)
    ..invalidate(walletEntriesProvider)
    ..invalidate(payoutMethodsProvider)
    ..invalidate(withdrawalsProvider);
}
