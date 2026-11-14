import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../consultations/presentation/consult_labels.dart' show money;
import '../../subscriptions/application/entitlements_controller.dart';

/// 23 — Payment history: current plan, store subscriptions and consultation
/// payments, grouped by month, with a receipt sheet per payment. Store
/// subscriptions are managed in the App Store / Google Play (as both stores
/// require); consultation refunds go back to the original card.
class PaymentHistoryScreen extends ConsumerStatefulWidget {
  const PaymentHistoryScreen({super.key});
  @override
  ConsumerState<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends ConsumerState<PaymentHistoryScreen> {
  PaymentKind? _kind;

  Future<void> _manage() async {
    final l = AppLocalizations.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final uri = Uri.parse(ios ? 'https://apps.apple.com/account/subscriptions' : 'https://play.google.com/store/account/subscriptions');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) showToast(context, l.storeManageNote);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenPayments)),
      body: AsyncView<List<PaymentRecord>>(
        value: ref.watch(paymentsProvider),
        onRetry: () => ref.invalidate(paymentsProvider),
        data: (all) {
          final list = _kind == null ? all : all.where((p) => p.kind == _kind).toList();
          final fmtMonth = DateFormat.yMMMM(langOf(context));
          final groups = <String, List<PaymentRecord>>{};
          for (final p in list) {
            groups.putIfAbsent(fmtMonth.format(p.date), () => []).add(p);
          }
          return RefreshIndicator(
            color: OlfaColors.primary,
            onRefresh: () => ref.refresh(paymentsProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                // current plan
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: OlfaColors.black, borderRadius: OlfaRadius.all(OlfaRadius.card)),
                  child: Row(children: [
                    const Icon(Icons.workspace_premium_outlined, color: OlfaColors.white, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.currentPlan, style: t.caption.copyWith(color: OlfaColors.white.withValues(alpha: 0.7))),
                        Text(ent == null ? '—' : l.planLabel(ent.plan), style: t.h2.copyWith(color: OlfaColors.white)),
                      ]),
                    ),
                    TextButton(
                      onPressed: () => context.push(Routes.plans),
                      style: TextButton.styleFrom(foregroundColor: OlfaColors.white),
                      child: Text(ent?.plan == PlanCode.premium ? l.viewPlans : l.upgrade),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                ChoiceWrap<PaymentKind?>(
                  options: const [null, PaymentKind.subscription, PaymentKind.consultation],
                  label: (k) => switch (k) { null => l.all, PaymentKind.subscription => l.subscriptions, PaymentKind.consultation => l.consultationsShort },
                  isSelected: (k) => _kind == k,
                  onTap: (k) => setState(() => _kind = k),
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: l.noPaymentsTitle,
                      body: l.noPaymentsBody,
                      action: PrimaryButton(label: l.screenPlans, expand: false, onPressed: () => context.push(Routes.plans)),
                    ),
                  ),
                for (final g in groups.entries) ...[
                  SectionLabel(g.key),
                  TileGroup(children: [for (final p in g.value) _PaymentTile(p: p)]),
                ],
                const SizedBox(height: 16),
                TileGroup(children: [
                  OlfaListTile(icon: Icons.open_in_new_rounded, title: l.manageInStore, subtitle: l.manageInStoreSub, onTap: _manage),
                  OlfaListTile(
                    icon: Icons.restore_rounded,
                    title: l.restorePurchases,
                    onTap: () async {
                      await ref.read(entitlementsProvider.notifier).restore();
                      ref.invalidate(paymentsProvider);
                      if (context.mounted) showToast(context, l.restoredToast);
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                Text(l.paymentsFootnote, style: t.caption),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.p});
  final PaymentRecord p;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = p.kind == PaymentKind.consultation ? l.consultationPayment : '${l.planLabel(p.plan)} · ${l.monthly}';
    final amount = p.amountMinor == null || p.currency == null ? (p.amountLabel ?? '') : money(context, p.amountMinor!, p.currency!);
    return OlfaListTile(
      icon: p.kind == PaymentKind.consultation ? Icons.support_agent_rounded : Icons.workspace_premium_outlined,
      title: title,
      subtitle: '${p.description ?? p.store} · ${DateFormat.MMMd(langOf(context)).format(p.date)}',
      showChevron: false,
      onTap: () => _receipt(context, p, title, amount),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (amount.isNotEmpty) Text(amount, style: context.type.bodyMedium.copyWith(fontWeight: FontWeight.w700, decoration: p.status == PaymentStatus.refunded ? TextDecoration.lineThrough : null)),
        const SizedBox(height: 2),
        _StatusTag(status: p.status),
      ]),
    );
  }

  void _receipt(BuildContext context, PaymentRecord p, String title, String amount) {
    final l = AppLocalizations.of(context);
    final fmt = DateFormat.yMMMd(langOf(context)).add_Hm();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.receipt, style: sheet.type.h2),
            const SizedBox(height: 12),
            TileGroup(children: [
              OlfaListTile(icon: Icons.label_outline_rounded, title: title, subtitle: p.description, showChevron: false),
              if (amount.isNotEmpty) OlfaListTile(icon: Icons.payments_outlined, title: amount, subtitle: l.amount, showChevron: false, trailing: _StatusTag(status: p.status)),
              OlfaListTile(icon: Icons.event_outlined, title: fmt.format(p.date), subtitle: l.date, showChevron: false),
              if (p.refundedAt != null) OlfaListTile(icon: Icons.undo_rounded, title: fmt.format(p.refundedAt!), subtitle: l.refunded, showChevron: false),
              OlfaListTile(icon: Icons.storefront_outlined, title: p.store, subtitle: l.paidVia, showChevron: false),
              if (p.reference != null)
                OlfaListTile(
                  icon: Icons.tag_rounded,
                  title: p.reference!,
                  subtitle: l.receiptReference,
                  showChevron: false,
                  trailing: IconButton(
                    tooltip: l.copy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: p.reference!));
                      showToast(sheet, l.copied);
                    },
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Text(p.kind == PaymentKind.consultation ? l.consultRefundNote : l.storeRefundNote, style: sheet.type.caption),
          ]),
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});
  final PaymentStatus status;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OlfaTag(
      switch (status) {
        PaymentStatus.succeeded => l.paid,
        PaymentStatus.refunded => l.refunded,
        PaymentStatus.failed => l.failed,
        PaymentStatus.pending => l.pending,
      },
      style: status == PaymentStatus.succeeded ? OlfaTagStyle.accent : OlfaTagStyle.neutral,
    );
  }
}
