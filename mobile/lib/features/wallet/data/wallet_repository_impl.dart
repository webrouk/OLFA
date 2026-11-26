import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/wallet_repository.dart';

class ApiWalletRepository implements WalletRepository {
  ApiWalletRepository(this._api);
  final ApiClient _api;
  Dio get _dio => _api.dio;

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;
  static DateTime _d(Object? v) => DateTime.parse(v as String).toLocal();

  static PayoutKind _kind(Object? v) => fromApiEnum(PayoutKind.values, v, PayoutKind.bankIban);

  static Withdrawal _withdrawal(Map<String, dynamic> j) {
    final pm = j['payoutMethod'] as Map?;
    return Withdrawal(
      id: j['id'] as String,
      amountMinor: _i(j['amountMinor']),
      currency: j['currency'] as String,
      status: fromApiEnum(WithdrawalStatus.values, j['status'], WithdrawalStatus.requested),
      requestedAt: _d(j['requestedAt']),
      processedAt: j['processedAt'] == null ? null : _d(j['processedAt']),
      reference: j['providerRef'] as String?,
      failureReason: j['failureReason'] as String?,
      methodMask: pm?['detailsMask'] as String?,
      methodKind: pm == null ? null : _kind(pm['kind']),
    );
  }

  static PayoutMethod _method(Map<String, dynamic> j) => PayoutMethod(
        id: j['id'] as String,
        kind: _kind(j['kind']),
        holderName: j['holderName'] as String,
        countryIso: j['countryCode'] as String,
        currency: j['currency'] as String,
        mask: j['detailsMask'] as String,
        isDefault: j['isDefault'] == true,
      );

  @override
  Future<WalletSummary> summary() => guard(() async {
        final j = (await _dio.get<Map<String, dynamic>>('/wallet')).data!;
        final mins = Map<String, dynamic>.from(j['minimums'] as Map? ?? const {});
        return WalletSummary(
          commissionPercent: _i(j['commissionPercent']),
          holdDays: _i(j['holdDays']),
          escrowAutoReleaseDays: _i(j['escrowAutoReleaseDays']),
          payoutsOnHold: j['payoutsOnHold'] == true,
          openWithdrawals: [for (final w in j['openWithdrawals'] as List? ?? const []) _withdrawal(Map<String, dynamic>.from(w as Map))],
          balances: [
            for (final b in j['balances'] as List? ?? const [])
              WalletBalance(
                currency: (b as Map)['currency'] as String,
                availableMinor: _i(b['availableMinor']),
                pendingMinor: _i(b['pendingMinor']),
                completedSessions: _i(b['completedSessions']),
                grossMinor: _i(b['grossMinor']),
                platformFeeMinor: _i(b['platformFeeMinor']),
                netEarnedMinor: _i(b['netEarnedMinor']),
                withdrawnMinor: _i(b['withdrawnMinor']),
                minimumMinor: _i(mins[b['currency']]),
                heldMinor: _i(b['heldMinor']),
                heldSessions: _i(b['heldSessions']),
                disputedMinor: _i(b['disputedMinor']),
                disputedSessions: _i(b['disputedSessions']),
              ),
          ],
        );
      });

  @override
  Future<List<WalletEntry>> entries() => guard(() async {
        final j = (await _dio.get<Map<String, dynamic>>('/wallet/entries')).data!;
        return [
          for (final e in j['items'] as List)
            () {
              final m = Map<String, dynamic>.from(e as Map);
              final k = m['consultation'] as Map?;
              return WalletEntry(
                id: m['id'].toString(),
                kind: fromApiEnum(WalletEntryKind.values, m['kind'], WalletEntryKind.adjustment),
                amountMinor: _i(m['amountMinor']),
                currency: m['currency'] as String,
                createdAt: _d(m['createdAt']),
                availableAt: _d(m['availableAt']),
                pending: m['pending'] == true,
                memo: m['memo'] as String?,
                grossMinor: k == null ? null : _i(k['priceMinor']),
                feeMinor: k == null ? null : _i(k['platformFeeMinor']),
                feePercent: k == null ? null : _i(k['platformFeePercent']),
                service: k == null ? null : fromApiEnum(ConsultationService.values, k['service'], ConsultationService.marital),
                durationMinutes: k == null ? null : _i(k['durationMinutes']),
              );
            }(),
        ];
      });

  @override
  Future<List<PayoutMethod>> payoutMethods() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/wallet/payout-methods');
        return [for (final m in r.data!) _method(Map<String, dynamic>.from(m as Map))];
      });

  @override
  Future<PayoutMethod> addPayoutMethod(PayoutMethodDraft d) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/wallet/payout-methods', data: {
          'kind': toApiEnum(d.kind),
          'holderName': d.holderName.trim(),
          'countryCode': d.countryIso,
          'currency': d.currency,
          if (d.iban != null) 'iban': d.iban,
          if (d.accountNumber != null) 'accountNumber': d.accountNumber,
          if (d.bic != null) 'bic': d.bic,
          if (d.bankName != null) 'bankName': d.bankName,
          if (d.email != null) 'email': d.email,
          'makeDefault': d.makeDefault,
        });
        return _method(r.data!);
      });

  @override
  Future<void> removePayoutMethod(String id) => guard(() => _dio.delete<void>('/wallet/payout-methods/$id'));

  @override
  Future<Withdrawal> withdraw({required String payoutMethodId, required String currency, required int amountMinor}) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/wallet/withdrawals', data: {'payoutMethodId': payoutMethodId, 'currency': currency, 'amountMinor': amountMinor});
        return _withdrawal(r.data!);
      });

  @override
  Future<List<Withdrawal>> withdrawals() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/wallet/withdrawals');
        return [for (final w in r.data!) _withdrawal(Map<String, dynamic>.from(w as Map))];
      });

  @override
  Future<void> cancelWithdrawal(String id) => guard(() => _dio.post<void>('/wallet/withdrawals/$id/cancel'));
}

class DemoWalletRepository implements WalletRepository {
  DemoWalletRepository(this._b);
  final DemoBackend _b;
  @override
  Future<WalletSummary> summary() => _b.wallet();
  @override
  Future<List<WalletEntry>> entries() => _b.walletEntries();
  @override
  Future<List<PayoutMethod>> payoutMethods() => _b.payoutMethods();
  @override
  Future<PayoutMethod> addPayoutMethod(PayoutMethodDraft d) => _b.addPayoutMethod(d);
  @override
  Future<void> removePayoutMethod(String id) => _b.removePayoutMethod(id);
  @override
  Future<Withdrawal> withdraw({required String payoutMethodId, required String currency, required int amountMinor}) => _b.withdraw(payoutMethodId, amountMinor);
  @override
  Future<List<Withdrawal>> withdrawals() => _b.withdrawals();
  @override
  Future<void> cancelWithdrawal(String id) => _b.cancelWithdrawal(id);
}

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => useApi ? ApiWalletRepository(ref.watch(apiClientProvider)) : DemoWalletRepository(ref.watch(demoBackendProvider)),
);
