import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/network/api_client.dart' show useApi;
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/components/subscription_card.dart';
import '../../../shared/models/models.dart';
import '../application/entitlements_controller.dart';

/// 22 — Subscription plans. Quotas come from the server (admin-editable);
/// prices come from the store — never hard-coded. Plan changes follow store
/// rules: an upgrade starts now, a downgrade at the next renewal, and
/// cancelling happens in the store (the app links there).
/// [professional]: the counselor plans (Free, Plus, Premium for counselors),
/// with their own benefits; the same store flow.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key, this.professional = false});
  final bool professional;
  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  PlanCode? _selected;
  bool _busy = false;
  bool _restoring = false;

  Future<void> _buy(PlanCode code, PlanCode current) async {
    final l = AppLocalizations.of(context);
    if (!useApi) {
      final ok = await showConfirmation(
        context,
        title: l.confirmPurchaseTitle(l.planLabel(code)),
        body: l.confirmPurchaseBody,
        confirmLabel: l.subscribe,
        icon: Icons.workspace_premium_outlined,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final pending = await ref.read(entitlementsProvider.notifier).purchase(code);
      if (!mounted) return;
      final downgrade = current != PlanCode.free && code.index < current.index;
      showToast(context, pending ? l.purchasePending : (downgrade ? l.downgradeScheduled(l.planLabel(code)) : l.subscribedToast(l.planLabel(code))));
    } on ServerFailure catch (e) {
      if (mounted && e.code != 'purchase_cancelled') showToast(context, _storeError(l, e));
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _storeError(AppLocalizations l, ServerFailure e) => switch (e.code) {
        'store_unavailable' => l.storeUnavailable,
        'product_unavailable' => l.productUnavailable,
        'purchase_failed' => l.purchaseFailed,
        _ => failureMessage(context, e),
      };

  Future<void> _restore() async {
    final l = AppLocalizations.of(context);
    setState(() => _restoring = true);
    try {
      final n = await ref.read(entitlementsProvider.notifier).restore();
      if (mounted) showToast(context, n > 0 ? l.restoredToast : l.nothingToRestore);
    } on ServerFailure catch (e) {
      if (mounted) showToast(context, _storeError(l, e));
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _manage(StoreSubscription? s) async {
    final l = AppLocalizations.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final url = s?.manageUrl ?? (ios ? 'https://apps.apple.com/account/subscriptions' : 'https://play.google.com/store/account/subscriptions');
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && mounted) showToast(context, l.storeManageNote);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    final store = ref.watch(storeSubscriptionProvider).valueOrNull;
    final pro = widget.professional;
    final current = ent?.plan ?? PlanCode.free;
    final plusCode = pro ? PlanCode.proPlus : PlanCode.plus;
    final sel = _selected ?? (current == PlanCode.free ? plusCode : current);
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag());

    final String label;
    VoidCallback? action;
    if (sel == current) {
      label = l.currentPlan;
    } else if (sel == PlanCode.free) {
      label = l.cancelInStore;
      action = () => _manage(store);
    } else if (store?.pendingPlan == sel) {
      label = l.changeScheduled;
    } else {
      label = current != PlanCode.free && sel.index < current.index ? l.downgradeTo(l.planLabel(sel)) : l.subscribeTo(l.planLabel(sel));
      action = () => _buy(sel, current);
    }

    return Scaffold(
      appBar: AppBar(title: Text(pro ? l.screenProPlans : l.screenPlans)),
      body: AsyncView<List<PlanInfo>>(
        value: ref.watch(pro ? proPlansProvider : plansProvider),
        onRetry: () => ref.invalidate(pro ? proPlansProvider : plansProvider),
        data: (plans) => Column(
          children: [
            Expanded(
              child: ContentWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    Text(pro ? l.proPlansBody : l.plansBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
                    const SizedBox(height: 14),
                    if (store != null) ...[
                      if (store.billingIssue)
                        InfoBanner(
                          text: store.graceUntil == null ? l.billingIssueBody : l.billingIssueGrace(date.format(store.graceUntil!)),
                          icon: Icons.credit_card_off_outlined,
                          accent: true,
                          trailing: TextButton(onPressed: () => _manage(store), child: Text(l.updatePayment)),
                        )
                      else if (store.pendingPlan != null && store.expiresAt != null)
                        InfoBanner(text: l.planChangesOn(l.planLabel(store.pendingPlan!), date.format(store.expiresAt!)), icon: Icons.event_repeat_rounded)
                      else if (!store.autoRenew && store.expiresAt != null)
                        InfoBanner(text: l.planEndsOn(date.format(store.expiresAt!)), icon: Icons.event_busy_outlined, trailing: TextButton(onPressed: () => _manage(store), child: Text(l.resubscribe)))
                      else if (store.status == StoreSubStatus.pending)
                        InfoBanner(text: l.purchasePending, icon: Icons.hourglass_top_rounded),
                      const SizedBox(height: 14),
                    ],
                    for (final p in plans) ...[
                      SubscriptionCard(plan: p, professional: pro, highlight: p.code == plusCode, selected: sel == p.code, current: current == p.code, onTap: () => setState(() => _selected = p.code)),
                      const SizedBox(height: 12),
                    ],
                    Text(l.planChangeRules, style: t.caption),
                    const SizedBox(height: 6),
                    Text(l.autoRenewNote, style: t.caption),
                    const SizedBox(height: 8),
                    Wrap(spacing: 4, children: [
                      TextButton(onPressed: _restoring ? null : _restore, child: Text(_restoring ? l.restoring : l.restorePurchases)),
                      if (current != PlanCode.free) TextButton(onPressed: () => _manage(store), child: Text(l.manageInStore)),
                      TextButton(onPressed: () => context.push(Routes.terms), child: Text(l.terms)),
                      TextButton(onPressed: () => context.push(Routes.privacyPolicy), child: Text(l.privacyPolicy)),
                    ]),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(color: OlfaColors.white, border: Border(top: BorderSide(color: OlfaColors.gray))),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: PrimaryButton(label: label, loading: _busy, onPressed: _busy ? null : action),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
