import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../consultations/application/consultation_providers.dart';
import '../../consultations/presentation/consult_labels.dart';
import '../../consultations/presentation/consultation_screens.dart';
import '../../wallet/application/wallet_providers.dart';

/// Professional account — Profile tab. The counselor sees their public card as
/// clients (and the admin dashboard) see it, its review status, and every
/// place they manage: prices, hours, reviews, wallet, payout methods, policy
/// and account settings.
class ProfessionalProfileScreen extends ConsumerWidget {
  const ProfessionalProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final me = ref.watch(myCounselorProvider);
    final wallet = ref.watch(walletSummaryProvider).valueOrNull;
    final balance = wallet == null || wallet.balances.isEmpty ? null : wallet.balances.first;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenMyProfile), automaticallyImplyLeading: false),
      body: RefreshIndicator(
        color: OlfaColors.primary,
        onRefresh: () async {
          ref.invalidate(walletSummaryProvider);
          await ref.refresh(myCounselorProvider.future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, OlfaSize.navBarClearance(context) + 8),
          children: [
            AsyncView<Counselor?>(
              value: me,
              onRetry: () => ref.invalidate(myCounselorProvider),
              loading: const OlfaSkeleton(height: 132, radius: OlfaRadius.card),
              data: (c) => c == null ? _NotApplied() : _Header(c: c),
            ),
            if (me.valueOrNull?.status == CounselorStatus.approved && me.valueOrNull!.offerings.isEmpty) ...[
              const SizedBox(height: 12),
              InfoBanner(accent: true, icon: Icons.sell_outlined, text: l.counselorApprovedBody),
            ],
            SectionLabel(l.pricing),
            TileGroup(children: [
              OlfaListTile(
                icon: Icons.sell_outlined,
                title: l.pricing,
                subtitle: me.valueOrNull == null ? null : _pricesSummary(context, me.valueOrNull!),
                onTap: me.valueOrNull == null ? null : () => showOfferingSheet(context, ref, me.valueOrNull),
              ),
              OlfaListTile(icon: Icons.schedule_rounded, title: l.myHours, onTap: () => context.push(Routes.counselorSchedule)),
              OlfaListTile(
                icon: Icons.star_outline_rounded,
                title: l.ratingsAndReviews,
                subtitle: me.valueOrNull == null || me.valueOrNull!.ratingCount == 0 ? null : '${me.valueOrNull!.ratingAvg.toStringAsFixed(1)} · ${l.reviewsCount(me.valueOrNull!.ratingCount)}',
                onTap: () => context.push(Routes.counselorReviews),
              ),
            ]),
            SectionLabel(l.walletTitle),
            TileGroup(children: [
              OlfaListTile(
                icon: Icons.account_balance_wallet_outlined,
                title: l.walletAvailable,
                trailing: balance == null ? null : Text(money(context, balance.availableMinor, balance.currency), textDirection: TextDirection.ltr, style: t.number(15)),
                onTap: () => context.go(Routes.wallet),
              ),
              OlfaListTile(icon: Icons.account_balance_outlined, title: l.payoutMethods, onTap: () => context.push(Routes.payoutMethods)),
              OlfaListTile(icon: Icons.receipt_long_outlined, title: l.withdrawalHistory, onTap: () => context.push(Routes.withdrawals)),
            ]),
            SectionLabel(l.screenProPlans),
            TileGroup(children: [
              OlfaListTile(icon: Icons.workspace_premium_outlined, title: l.screenProPlans, subtitle: l.proPlansTileSub, accent: true, onTap: () => context.push(Routes.proPlans)),
              OlfaListTile(icon: Icons.insights_outlined, title: l.screenProPerformance, onTap: () => context.go(Routes.proPerformance)),
            ]),
            SectionLabel(l.screenSettings),
            TileGroup(children: [
              OlfaListTile(icon: Icons.gavel_rounded, title: l.professionalPolicy, onTap: () => context.push(Routes.professionalPolicy)),
              OlfaListTile(icon: Icons.notifications_none_rounded, title: l.screenNotifications, onTap: () => context.push(Routes.notifications)),
              OlfaListTile(icon: Icons.shield_outlined, title: l.screenPrivacy, onTap: () => context.push(Routes.privacy)),
              OlfaListTile(icon: Icons.help_outline_rounded, title: l.screenHelp, onTap: () => context.push(Routes.help)),
              OlfaListTile(icon: Icons.settings_outlined, title: l.screenSettings, onTap: () => context.push(Routes.settings)),
            ]),
          ],
        ),
      ),
    );
  }

  String _pricesSummary(BuildContext context, Counselor c) {
    final l = AppLocalizations.of(context);
    final from = cheapestOffering(c);
    if (from == null) return l.noOfferingsYet;
    return l.priceFrom(money(context, from.priceMinor, from.currency), from.durationMinutes);
  }
}

/// The counselor's public card — the same facts the client directory and the
/// admin dashboard show — plus the review status of the application.
class _Header extends StatelessWidget {
  const _Header({required this.c});
  final Counselor c;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final (statusText, statusStyle) = switch (c.status) {
      CounselorStatus.approved => (l.statusApproved, OlfaTagStyle.primary),
      CounselorStatus.rejected => (l.statusRejected, OlfaTagStyle.dark),
      CounselorStatus.suspended => (l.statusRejected, OlfaTagStyle.dark),
      _ => (l.statusPending, OlfaTagStyle.neutral),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OlfaCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CounselorAvatar(size: 64, name: c.name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(c.name, style: t.h3, overflow: TextOverflow.ellipsis)),
                  if (c.status == CounselorStatus.approved) ...[const SizedBox(width: 6), VerifiedBadge(size: 16, semanticLabel: l.licenseVerified)],
                ]),
                Text('${kindLabel(l, c.kind)} · ${l.yearsCount(c.yearsExperience)}', style: t.caption),
                const SizedBox(height: 4),
                RatingLine(avg: c.ratingAvg, count: c.ratingCount),
              ]),
            ),
            OlfaTag(statusText, style: statusStyle),
          ]),
          if (c.services.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in c.services) OlfaTag(serviceLabel(l, s)),
              for (final lg in c.languages) OlfaTag(languageName(context, lg), style: OlfaTagStyle.accent),
            ]),
          ],
          const SizedBox(height: 12),
          SecondaryButton(label: l.screenCounselor, icon: Icons.visibility_outlined, onPressed: () => context.push(Routes.counselorDetails(c.id))),
        ]),
      ),
      if (c.status == CounselorStatus.pending) ...[
        const SizedBox(height: 12),
        InfoBanner(icon: Icons.hourglass_top_rounded, text: '${l.counselorPending} — ${l.counselorPendingBody}'),
      ],
      if (c.status == CounselorStatus.rejected && c.rejectReason != null) ...[
        const SizedBox(height: 12),
        InfoBanner(accent: true, icon: Icons.info_outline_rounded, text: '${l.counselorRejected}: ${c.rejectReason}'),
      ],
    ]);
  }
}

class _NotApplied extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OlfaCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.screenCounselorApply, style: context.type.h3),
        const SizedBox(height: 6),
        Text(l.professionalsRegisterNote, style: context.type.bodySmall),
        const SizedBox(height: 12),
        PrimaryButton(label: l.screenCounselorApply, onPressed: () => context.push(Routes.counselorApply)),
      ]),
    );
  }
}
