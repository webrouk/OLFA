import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/payout_validation.dart';
import '../../consultations/presentation/consult_labels.dart';
import '../application/wallet_providers.dart';
import '../data/wallet_repository_impl.dart';

String _date(BuildContext c, DateTime d) => DateFormat.yMMMd(langOf(c)).format(d);

String payoutKindLabel(AppLocalizations l, PayoutKind k) => switch (k) {
      PayoutKind.bankIban => l.payoutIban,
      PayoutKind.bankSwift => l.payoutSwift,
      PayoutKind.wise => 'Wise',
      PayoutKind.paypal => 'PayPal',
      PayoutKind.payoneer => 'Payoneer',
    };

String withdrawalStatusLabel(AppLocalizations l, WithdrawalStatus s) => switch (s) {
      WithdrawalStatus.requested => l.wdRequested,
      WithdrawalStatus.processing => l.wdProcessing,
      WithdrawalStatus.paid => l.wdPaid,
      WithdrawalStatus.rejected => l.wdRejected,
      WithdrawalStatus.failed => l.wdFailed,
      WithdrawalStatus.cancelled => l.wdCancelled,
    };

/// Counselor wallet: withdrawable balance, fees held until clients confirm and rate (escrow),
/// how the 15% commission works, payout accounts and the full ledger.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final summary = ref.watch(walletSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.walletTitle), automaticallyImplyLeading: false),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletSummaryProvider);
          ref.invalidate(walletEntriesProvider);
          await ref.read(walletSummaryProvider.future);
        },
        child: AsyncView<WalletSummary>(
          value: summary,
          onRetry: () => ref.invalidate(walletSummaryProvider),
          data: (s) => ListView(
            padding: EdgeInsets.fromLTRB(20, 4, 20, OlfaSize.navBarClearance(context) + 8),
            children: [
              if (s.payoutsOnHold) ...[InfoBanner(text: l.walletOnHold, icon: Icons.pause_circle_outline_rounded, accent: true), const SizedBox(height: 14)],
              if (s.balances.isEmpty)
                _BalanceCard(balance: WalletBalance(currency: 'AED', availableMinor: 0, pendingMinor: 0, completedSessions: 0, grossMinor: 0, platformFeeMinor: 0, netEarnedMinor: 0, withdrawnMinor: 0, minimumMinor: 5000), holdDays: s.holdDays, canWithdraw: false)
              else
                for (final b in s.balances) ...[_BalanceCard(balance: b, holdDays: s.holdDays, canWithdraw: !s.payoutsOnHold && b.availableMinor >= b.minimumMinor && s.openWithdrawals.every((w) => w.currency != b.currency)), const SizedBox(height: 12)],
              for (final w in s.openWithdrawals) _OpenWithdrawal(w: w),
              const SizedBox(height: 6),
              _EscrowSteps(autoReleaseDays: s.escrowAutoReleaseDays),
              const SizedBox(height: 12),
              _CommissionCard(percent: s.commissionPercent, balance: s.balances.isEmpty ? null : s.balances.first),
              const SizedBox(height: 14),
              TileGroup(children: [
                OlfaListTile(icon: Icons.account_balance_outlined, title: l.payoutMethods, subtitle: l.payoutMethodsHint, onTap: () => context.push(Routes.payoutMethods)),
                OlfaListTile(icon: Icons.receipt_long_outlined, title: l.withdrawalHistory, onTap: () => context.push(Routes.withdrawals)),
                OlfaListTile(icon: Icons.policy_outlined, title: l.professionalPolicy, onTap: () => context.push(Routes.professionalPolicy)),
              ]),
              SectionLabel(l.walletActivity),
              const _Ledger(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.balance, required this.holdDays, required this.canWithdraw});
  final WalletBalance balance;
  final int holdDays;
  final bool canWithdraw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final b = balance;
    final soon = b.pendingMinor; // released, still in the (optional) hold period
    final total = b.availableMinor + soon + b.heldMinor + b.disputedMinor;
    final white70 = OlfaColors.white.withValues(alpha: 0.7);
    Widget part(String label, int amount, Color dot, {String? sub}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: t.caption.copyWith(color: white70), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 3),
            Text(money(context, amount, b.currency), style: t.bodyMedium.copyWith(color: OlfaColors.white, fontWeight: FontWeight.w700), textDirection: TextDirection.ltr),
            if (sub != null) Text(sub, style: t.caption.copyWith(color: white70)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: OlfaColors.black, borderRadius: OlfaRadius.all(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(l.walletAvailable, style: t.caption.copyWith(color: white70))),
            OlfaTag(b.currency, style: OlfaTagStyle.onImage),
          ]),
          const SizedBox(height: 6),
          Text(money(context, b.availableMinor, b.currency), style: t.h1.copyWith(color: OlfaColors.white, fontSize: 34), textDirection: TextDirection.ltr),
          const SizedBox(height: 16),
          // where the money is: available · held until clients confirm · under review
          if (total > 0)
            Semantics(
              excludeSemantics: true,
              label: l.walletBreakdownA11y(money(context, b.availableMinor + soon, b.currency), money(context, b.heldMinor, b.currency), money(context, b.disputedMinor, b.currency)),
              child: ClipRRect(
                borderRadius: OlfaRadius.all(6),
                child: SizedBox(
                  height: 8,
                  child: Row(children: [
                    if (b.availableMinor + soon > 0) Expanded(flex: b.availableMinor + soon, child: const ColoredBox(color: OlfaColors.white)),
                    if (b.heldMinor > 0) Expanded(flex: b.heldMinor, child: const ColoredBox(color: OlfaColors.primary)),
                    if (b.disputedMinor > 0) Expanded(flex: b.disputedMinor, child: ColoredBox(color: OlfaColors.white.withValues(alpha: 0.3))),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            part(l.walletHeld, b.heldMinor, OlfaColors.primary, sub: b.heldSessions > 0 ? l.walletSessionsCount(b.heldSessions) : null),
            const SizedBox(width: 10),
            part(l.walletUnderReview, b.disputedMinor, OlfaColors.white.withValues(alpha: 0.3), sub: b.disputedSessions > 0 ? l.walletSessionsCount(b.disputedSessions) : null),
            if (soon > 0) ...[const SizedBox(width: 10), part(l.walletSoon, soon, OlfaColors.white, sub: l.walletSoonDays(holdDays))],
          ]),
          const SizedBox(height: 18),
          PrimaryButton(
            label: l.withdraw,
            icon: Icons.south_west_rounded,
            inverted: true,
            onPressed: canWithdraw ? () => showWithdrawSheet(context, ref, b) : null,
          ),
          if (!canWithdraw && b.availableMinor < b.minimumMinor) ...[
            const SizedBox(height: 8),
            Text(l.walletMinimum(money(context, b.minimumMinor, b.currency)), style: t.caption.copyWith(color: white70)),
          ],
        ],
      ),
    );
  }
}

/// How a consultation fee reaches the wallet (escrow).
class _EscrowSteps extends StatelessWidget {
  const _EscrowSteps({required this.autoReleaseDays});
  final int autoReleaseDays;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final steps = [
      (Icons.lock_outline_rounded, l.escrowStep1Title, l.escrowStep1Body),
      (Icons.video_call_outlined, l.escrowStep2Title, l.escrowStep2Body),
      (Icons.star_outline_rounded, l.escrowStep3Title, l.escrowStep3Body),
      (Icons.account_balance_wallet_outlined, l.escrowStep4Title, l.escrowStep4Body),
    ];
    return OlfaCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.escrowHowTitle, style: t.h3),
        const SizedBox(height: 12),
        for (final (i, (icon, title, body)) in steps.indexed)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: i == steps.length - 1 ? OlfaColors.primary : OlfaColors.primaryTint(), shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: i == steps.length - 1 ? OlfaColors.white : OlfaColors.primary),
                ),
                if (i < steps.length - 1) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: OlfaColors.gray)),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14, top: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(body, style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
                  ]),
                ),
              ),
            ]),
          ),
        InfoBanner(text: autoReleaseDays > 0 ? l.escrowAutoRelease(autoReleaseDays) : l.escrowNoAutoRelease, icon: Icons.info_outline_rounded),
      ]),
    );
  }
}

class _OpenWithdrawal extends ConsumerWidget {
  const _OpenWithdrawal({required this.w});
  final Withdrawal w;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OlfaCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.hourglass_top_rounded, color: OlfaColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${withdrawalStatusLabel(l, w.status)} · ${money(context, w.amountMinor, w.currency)}', style: context.type.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
              Text('${w.methodMask ?? ''} · ${_date(context, w.requestedAt)}', style: context.type.caption),
            ]),
          ),
          if (w.status == WithdrawalStatus.requested)
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(walletRepositoryProvider).cancelWithdrawal(w.id);
                  ref.invalidate(walletSummaryProvider);
                  ref.invalidate(walletEntriesProvider);
                } on Failure catch (e) {
                  if (context.mounted) showToast(context, failureMessage(context, e));
                }
              },
              child: Text(l.cancel),
            ),
        ]),
      ),
    );
  }
}

/// "Where does the 15% go?" — shown to every professional, with their own numbers.
class _CommissionCard extends StatelessWidget {
  const _CommissionCard({required this.percent, this.balance});
  final int percent;
  final WalletBalance? balance;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final b = balance;
    Widget stat(String label, String value, {bool strong = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.caption),
            const SizedBox(height: 2),
            Text(value, style: t.bodyMedium.copyWith(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: strong ? OlfaColors.primary : OlfaColors.black), textDirection: TextDirection.ltr),
          ]),
        );
    return OlfaCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: OlfaColors.primary, borderRadius: OlfaRadius.all(12)),
            child: Text('$percent%', style: t.h3.copyWith(color: OlfaColors.white), textDirection: TextDirection.ltr),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l.commissionTitle, style: t.h3)),
        ]),
        const SizedBox(height: 10),
        Text(l.commissionBody(percent), style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (ic, txt) in [(Icons.build_outlined, l.commissionDev), (Icons.campaign_outlined, l.commissionMarketing), (Icons.ads_click_rounded, l.commissionAds), (Icons.person_search_outlined, l.commissionPromote)])
            OlfaTag(txt, icon: ic),
        ]),
        if (b != null && b.completedSessions > 0) ...[
          const Divider(height: 28),
          Text(l.commissionYourNumbers(b.completedSessions), style: t.caption),
          const SizedBox(height: 8),
          Row(children: [
            stat(l.clientsPaid, money(context, b.grossMinor, b.currency)),
            stat(l.platformFee(percent), '− ${money(context, b.platformFeeMinor, b.currency)}'),
            stat(l.yourShare, money(context, b.netEarnedMinor, b.currency), strong: true),
          ]),
        ],
      ]),
    );
  }
}

class _Ledger extends ConsumerWidget {
  const _Ledger();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final entries = ref.watch(walletEntriesProvider);
    return AsyncView<List<WalletEntry>>(
      value: entries,
      onRetry: () => ref.invalidate(walletEntriesProvider),
      data: (list) => list.isEmpty
          ? Padding(padding: const EdgeInsets.all(24), child: Text(l.walletEmpty, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center))
          : TileGroup(children: [
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: e.amountMinor > 0 ? OlfaColors.primaryTint(0.12) : OlfaColors.gray,
                      child: Icon(switch (e.kind) {
                        WalletEntryKind.earning => Icons.south_west_rounded,
                        WalletEntryKind.withdrawal => Icons.north_east_rounded,
                        WalletEntryKind.withdrawalReturn => Icons.undo_rounded,
                        WalletEntryKind.earningReversal => Icons.remove_circle_outline_rounded,
                        WalletEntryKind.adjustment => Icons.tune_rounded,
                      }, size: 18, color: e.amountMinor > 0 ? OlfaColors.primary : OlfaColors.black),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(switch (e.kind) {
                          WalletEntryKind.earning => e.service == null ? l.ledgerEarning : '${serviceLabel(l, e.service!)} · ${l.minutesShort(e.durationMinutes!)}',
                          WalletEntryKind.withdrawal => l.ledgerWithdrawal,
                          WalletEntryKind.withdrawalReturn => l.ledgerReturn,
                          WalletEntryKind.earningReversal => l.ledgerReversal,
                          WalletEntryKind.adjustment => l.ledgerAdjustment,
                        }, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                        if (e.kind == WalletEntryKind.earning && e.grossMinor != null)
                          Text('${money(context, e.grossMinor!, e.currency)} − ${e.feePercent}% = ${money(context, e.amountMinor, e.currency)}', style: t.caption, textDirection: TextDirection.ltr),
                        Text(e.pending ? l.availableOn(_date(context, e.availableAt)) : _date(context, e.createdAt), style: t.caption.copyWith(color: e.pending ? OlfaColors.primary : null)),
                      ]),
                    ),
                    Text('${e.amountMinor > 0 ? '+' : ''}${money(context, e.amountMinor, e.currency)}',
                        style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: e.pending ? OlfaColors.textMuted : OlfaColors.black), textDirection: TextDirection.ltr),
                  ]),
                ),
            ]),
    );
  }
}

/// Withdraw: pick an account, amount (≥ minimum, ≤ available). Funds are reserved at once.
Future<void> showWithdrawSheet(BuildContext context, WidgetRef ref, WalletBalance b) async {
  final l = AppLocalizations.of(context);
  final methods = await ref.read(walletRepositoryProvider).payoutMethods();
  if (!context.mounted) return;
  if (methods.isEmpty) {
    showToast(context, l.addPayoutFirst);
    context.push(Routes.payoutMethods);
    return;
  }
  var method = methods.firstWhere((m) => m.isDefault, orElse: () => methods.first);
  final amount = TextEditingController(text: '');
  var busy = false;
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.withdraw, style: ctx.type.h2),
          const SizedBox(height: 4),
          Text(l.walletAvailableAmount(money(ctx, b.availableMinor, b.currency)), style: ctx.type.bodySmall.copyWith(color: OlfaColors.textMuted)),
          const SizedBox(height: 16),
          Text(l.payoutTo, style: ctx.type.inputLabel),
          const SizedBox(height: 8),
          DropdownButtonFormField<PayoutMethod>(
            value: method,
            isExpanded: true,
            items: [for (final m in methods) DropdownMenuItem(value: m, child: Text('${payoutKindLabel(l, m.kind)} · ${m.mask}', textDirection: TextDirection.ltr))],
            onChanged: (m) => set(() => method = m ?? method),
          ),
          const SizedBox(height: 14),
          OlfaTextField(
            label: '${l.amount} (${b.currency})',
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            error: error,
            suffix: TextButton(onPressed: () => set(() => amount.text = (b.availableMinor / _pow(kCurrencyExponent[b.currency] ?? 2)).toStringAsFixed(kCurrencyExponent[b.currency] ?? 2)), child: Text(l.max)),
          ),
          Text(l.walletMinimum(money(ctx, b.minimumMinor, b.currency)), style: ctx.type.caption),
          const SizedBox(height: 8),
          Text(l.withdrawNote, style: ctx.type.caption),
          const SizedBox(height: 16),
          PrimaryButton(
            label: l.requestWithdrawal,
            loading: busy,
            onPressed: busy
                ? null
                : () async {
                    final minor = parseMinor(amount.text, b.currency);
                    if (minor == null || minor < b.minimumMinor || minor > b.availableMinor) {
                      set(() => error = l.withdrawAmountError);
                      return;
                    }
                    set(() => busy = true);
                    try {
                      await ref.read(walletRepositoryProvider).withdraw(payoutMethodId: method.id, currency: b.currency, amountMinor: minor);
                      ref.invalidate(walletSummaryProvider);
                      ref.invalidate(walletEntriesProvider);
                      ref.invalidate(withdrawalsProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) showToast(context, l.withdrawRequested);
                    } on Failure catch (e) {
                      set(() => busy = false);
                      if (ctx.mounted) set(() => error = failureMessage(ctx, e));
                    }
                  },
          ),
        ]),
      ),
    ),
  );
  amount.dispose();
}

int _pow(int e) => e == 0 ? 1 : 10 * _pow(e - 1);

/// Saved payout accounts (bank IBAN / SWIFT, Wise, PayPal, Payoneer).
class PayoutMethodsScreen extends ConsumerWidget {
  const PayoutMethodsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(payoutMethodsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.payoutMethods)),
      body: AsyncView<List<PayoutMethod>>(
        value: list,
        onRetry: () => ref.invalidate(payoutMethodsProvider),
        data: (ms) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            InfoBanner(text: l.payoutSecurity, icon: Icons.lock_outline_rounded),
            const SizedBox(height: 14),
            if (ms.isEmpty)
              EmptyState(icon: Icons.account_balance_outlined, title: l.noPayoutMethods, body: l.payoutMethodsHint)
            else
              TileGroup(children: [
                for (final m in ms)
                  OlfaListTile(
                    icon: m.kind == PayoutKind.bankIban || m.kind == PayoutKind.bankSwift ? Icons.account_balance_outlined : Icons.alternate_email_rounded,
                    title: '${payoutKindLabel(l, m.kind)} · ${m.mask}',
                    subtitle: '${m.holderName} · ${m.currency}${m.isDefault ? ' · ${l.defaultLabel}' : ''}',
                    showChevron: false,
                    trailing: IconButton(
                      tooltip: l.remove,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        try {
                          await ref.read(walletRepositoryProvider).removePayoutMethod(m.id);
                          ref.invalidate(payoutMethodsProvider);
                        } on Failure catch (e) {
                          if (context.mounted) showToast(context, failureMessage(context, e));
                        }
                      },
                    ),
                  ),
              ]),
            const SizedBox(height: 16),
            SecondaryButton(label: l.addPayoutMethod, icon: Icons.add_rounded, onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _AddPayoutSheet())),
          ],
        ),
      ),
    );
  }
}

class _AddPayoutSheet extends ConsumerStatefulWidget {
  const _AddPayoutSheet();
  @override
  ConsumerState<_AddPayoutSheet> createState() => _AddPayoutSheetState();
}

class _AddPayoutSheetState extends ConsumerState<_AddPayoutSheet> {
  PayoutKind _kind = PayoutKind.bankIban;
  final _holder = TextEditingController(), _iban = TextEditingController(), _acct = TextEditingController(), _bic = TextEditingController(), _bank = TextEditingController(), _email = TextEditingController();
  String _country = 'AE', _currency = 'AED';
  bool _default = true, _busy = false, _submitted = false;

  @override
  void dispose() {
    for (final c in [_holder, _iban, _acct, _bic, _bank, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String?> _errors(AppLocalizations l) => {
        'holder': _holder.text.trim().length < 3 ? l.errorRequired : null,
        if (_kind == PayoutKind.bankIban) 'iban': isValidIban(_iban.text) ? null : l.invalidIban,
        if (_kind == PayoutKind.bankSwift) 'bic': isValidBic(_bic.text) ? null : l.invalidBic,
        if (_kind == PayoutKind.bankSwift) 'acct': RegExp(r'^[A-Za-z0-9]{5,34}$').hasMatch(_acct.text.replaceAll(RegExp(r'[\s-]'), '')) ? null : l.errorValidation,
        if (_kind.index >= PayoutKind.wise.index) 'email': isValidPayoutEmail(_email.text) ? null : l.invalidEmail,
      };

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() => _submitted = true);
    if (_errors(l).values.any((e) => e != null)) return;
    setState(() => _busy = true);
    try {
      await ref.read(walletRepositoryProvider).addPayoutMethod(PayoutMethodDraft(
            kind: _kind,
            holderName: _holder.text,
            countryIso: _country,
            currency: _currency,
            iban: _kind == PayoutKind.bankIban ? normalizeIban(_iban.text) : null,
            accountNumber: _kind == PayoutKind.bankSwift ? _acct.text.trim() : null,
            bic: _kind == PayoutKind.bankSwift ? _bic.text.trim().toUpperCase() : null,
            bankName: _kind.index <= PayoutKind.bankSwift.index && _bank.text.trim().isNotEmpty ? _bank.text.trim() : null,
            email: _kind.index >= PayoutKind.wise.index ? _email.text.trim() : null,
            makeDefault: _default,
          ));
      ref.invalidate(payoutMethodsProvider);
      if (mounted) Navigator.pop(context);
    } on Failure catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, failureMessage(context, e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final err = _submitted ? _errors(l) : const <String, String?>{};
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.addPayoutMethod, style: context.type.h2),
          const SizedBox(height: 14),
          ChoiceWrap<PayoutKind>(options: PayoutKind.values, label: (k) => payoutKindLabel(l, k), isSelected: (k) => k == _kind, onTap: (k) => setState(() => _kind = k)),
          const SizedBox(height: 16),
          OlfaTextField(label: l.accountHolder, controller: _holder, error: err['holder'], autofillHints: const [AutofillHints.name]),
          if (_kind == PayoutKind.bankIban)
            OlfaTextField(label: 'IBAN', controller: _iban, hint: 'AE07 0331 2345 6789 0123 456', error: err['iban'], onChanged: (_) => setState(() {})),
          if (_kind == PayoutKind.bankSwift) ...[
            OlfaTextField(label: l.accountNumber, controller: _acct, error: err['acct']),
            OlfaTextField(label: 'SWIFT / BIC', controller: _bic, hint: 'NBADAEAA', error: err['bic']),
          ],
          if (_kind.index <= PayoutKind.bankSwift.index) OlfaTextField(label: l.bankNameOptional, controller: _bank),
          if (_kind.index >= PayoutKind.wise.index) OlfaTextField(label: l.accountEmail, controller: _email, keyboardType: TextInputType.emailAddress, error: err['email']),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _country,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.country),
                items: [for (final c in kCountries) DropdownMenuItem(value: c.iso, child: Text('${c.flag} ${c.label(langOf(context))}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _country = v ?? _country),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                value: _currency,
                decoration: InputDecoration(labelText: l.currency),
                items: [for (final c in kPriceCurrencies) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => _currency = v ?? _currency),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          OlfaCheck(value: _default, onChanged: (v) => setState(() => _default = v), label: l.makeDefault),
          const SizedBox(height: 6),
          Text(l.payoutSecurity, style: context.type.caption),
          const SizedBox(height: 14),
          PrimaryButton(label: l.save, loading: _busy, onPressed: _busy ? null : _save),
        ]),
      ),
    );
  }
}

/// Every withdrawal with its status and the bank / provider reference once paid.
class WithdrawalsScreen extends ConsumerWidget {
  const WithdrawalsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(withdrawalsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.withdrawalHistory)),
      body: AsyncView<List<Withdrawal>>(
        value: list,
        onRetry: () => ref.invalidate(withdrawalsProvider),
        data: (ws) => ws.isEmpty
            ? EmptyState(icon: Icons.receipt_long_outlined, title: l.noWithdrawals, body: l.withdrawNote)
            : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
                TileGroup(children: [
                  for (final w in ws)
                    OlfaListTile(
                      icon: w.status == WithdrawalStatus.paid ? Icons.check_circle_outline_rounded : (w.open ? Icons.hourglass_top_rounded : Icons.error_outline_rounded),
                      accent: w.status == WithdrawalStatus.paid,
                      title: money(context, w.amountMinor, w.currency),
                      subtitle: [
                        withdrawalStatusLabel(l, w.status),
                        if (w.methodMask != null) w.methodMask!,
                        _date(context, w.requestedAt),
                        if (w.reference != null) '${l.reference}: ${w.reference}',
                        if (w.failureReason != null) w.failureReason!,
                      ].join(' · '),
                      showChevron: false,
                      trailing: w.reference == null
                          ? null
                          : IconButton(tooltip: l.copy, icon: const Icon(Icons.copy_rounded, size: 18), onPressed: () => Clipboard.setData(ClipboardData(text: w.reference!))),
                    ),
                ]),
              ]),
      ),
    );
  }
}
