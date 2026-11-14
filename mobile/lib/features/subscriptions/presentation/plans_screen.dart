import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/components/subscription_card.dart';
import '../../../shared/models/models.dart';
import '../application/entitlements_controller.dart';

/// 22 — Subscription plans. Quotas come from the server (admin-editable);
/// prices come from the store at purchase time — never hard-coded.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});
  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  PlanCode? _selected;
  bool _busy = false;

  Future<void> _buy(PlanCode code) async {
    final l = AppLocalizations.of(context);
    final ok = await showConfirmation(
      context,
      title: l.confirmPurchaseTitle(l.planLabel(code)),
      body: l.confirmPurchaseBody,
      confirmLabel: l.subscribe,
      icon: Icons.workspace_premium_outlined,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(entitlementsProvider.notifier).purchase(code);
      if (mounted) showToast(context, l.subscribedToast(l.planLabel(code)));
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    final current = ent?.plan ?? PlanCode.free;
    final sel = _selected ?? (current == PlanCode.free ? PlanCode.plus : current);
    return Scaffold(
      appBar: AppBar(title: Text(l.screenPlans)),
      body: AsyncView<List<PlanInfo>>(
        value: ref.watch(plansProvider),
        onRetry: () => ref.invalidate(plansProvider),
        data: (plans) => Column(
          children: [
            Expanded(
              child: ContentWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    Text(l.plansBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
                    const SizedBox(height: 18),
                    for (final p in plans) ...[
                      SubscriptionCard(plan: p, highlight: p.code == PlanCode.plus, selected: sel == p.code, current: current == p.code, onTap: () => setState(() => _selected = p.code)),
                      const SizedBox(height: 12),
                    ],
                    Text(l.autoRenewNote, style: t.caption),
                    const SizedBox(height: 8),
                    Wrap(spacing: 4, children: [
                      TextButton(
                        onPressed: () async {
                          await ref.read(entitlementsProvider.notifier).restore();
                          if (context.mounted) showToast(context, l.restoredToast);
                        },
                        child: Text(l.restorePurchases),
                      ),
                      TextButton(onPressed: () => showToast(context, l.legalLinkNote), child: Text(l.terms)),
                      TextButton(onPressed: () => showToast(context, l.legalLinkNote), child: Text(l.privacyPolicy)),
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
                  child: PrimaryButton(
                    label: sel == current ? l.currentPlan : (sel == PlanCode.free ? l.manageInStore : l.subscribeTo(l.planLabel(sel))),
                    loading: _busy,
                    onPressed: sel == current
                        ? null
                        : (sel == PlanCode.free ? () => showToast(context, l.downgradeNote) : () => _buy(sel)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
