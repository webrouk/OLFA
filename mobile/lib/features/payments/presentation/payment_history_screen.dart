import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';

/// 23 — Payment history.
class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.screenPayments)),
      body: AsyncView<List<PaymentRecord>>(
        value: ref.watch(paymentsProvider),
        onRetry: () => ref.invalidate(paymentsProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l.noPaymentsTitle,
              body: l.noPaymentsBody,
              action: PrimaryButton(label: l.screenPlans, expand: false, onPressed: () => context.push(Routes.plans)),
            );
          }
          final fmt = DateFormat.yMMMd(langOf(context));
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TileGroup(children: [
                for (final p in list)
                  OlfaListTile(
                    icon: Icons.receipt_long_outlined,
                    title: '${l.planLabel(p.plan)} · ${l.monthly}',
                    subtitle: '${p.store} · ${fmt.format(p.date)} · ${p.id}',
                    trailing: OlfaTag(
                      switch (p.status) {
                        PaymentStatus.succeeded => l.paid,
                        PaymentStatus.refunded => l.refunded,
                        PaymentStatus.failed => l.failed,
                      },
                      style: p.status == PaymentStatus.succeeded ? OlfaTagStyle.accent : OlfaTagStyle.neutral,
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              TileGroup(children: [
                OlfaListTile(icon: Icons.open_in_new_rounded, title: l.manageInStore, onTap: () => showToast(context, l.storeManageNote)),
                OlfaListTile(
                  icon: Icons.restore_rounded,
                  title: l.restorePurchases,
                  onTap: () async {
                    await ref.read(entitlementsProvider.notifier).restore();
                    if (context.mounted) showToast(context, l.restoredToast);
                  },
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}
