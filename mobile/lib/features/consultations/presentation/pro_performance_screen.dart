import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../application/consultation_providers.dart';

/// Counselor tab "Performance" (the round button of the counselor bar): the
/// counselor plan, how the profile is placed in the directory, the last 30
/// days (counselor Plus / Premium) and what helps clients choose you.
/// Who looked at the profile is never shown.
class ProPerformanceScreen extends ConsumerWidget {
  const ProPerformanceScreen({super.key});

  Future<void> _plans(BuildContext context, WidgetRef ref) async {
    await context.push(Routes.proPlans);
    ref.invalidate(myInsightsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenProPerformance), automaticallyImplyLeading: context.canPop()),
      body: AsyncView<ProInsights>(
        value: ref.watch(myInsightsProvider),
        onRetry: () => ref.invalidate(myInsightsProvider),
        data: (x) => RefreshIndicator(
          color: OlfaColors.primary,
          onRefresh: () => ref.refresh(myInsightsProvider.future),
          child: ContentWidth(
            child: ListView(
              // leaves room for the floating tab bar (this is a tab)
              padding: EdgeInsets.fromLTRB(20, 4, 20, OlfaSize.navBarClearance(context) + 8),
              children: [
                _PlanHeader(x: x, onPlans: () => _plans(context, ref)),
                const SizedBox(height: 20),
                Text(l.last30Days, style: t.h3),
                const SizedBox(height: 10),
                if (x.available) _Stats(x: x) else _Locked(onPlans: () => _plans(context, ref)),
                const SizedBox(height: 20),
                Text(l.growTitle, style: t.h3),
                const SizedBox(height: 10),
                TileGroup(children: [
                  OlfaListTile(icon: Icons.badge_outlined, title: l.growProfile, subtitle: l.growProfileSub, onTap: () => context.go(Routes.proProfile)),
                  OlfaListTile(icon: Icons.event_available_outlined, title: l.growHours, subtitle: l.growHoursSub, onTap: () => context.push(Routes.counselorSchedule)),
                  OlfaListTile(icon: Icons.bolt_rounded, title: l.growReply, subtitle: l.growReplySub, onTap: () => context.go(Routes.counselorDesk)),
                ]),
                const SizedBox(height: 12),
                Text(l.insightsPrivacyNote, style: t.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.x, required this.onPlans});
  final ProInsights x;
  final VoidCallback onPlans;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final placement = switch (x.boost) { 2 => l.visibilityTop, 1 => l.visibilityPriority, _ => l.visibilityStandard };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: OlfaColors.black, borderRadius: OlfaRadius.all(OlfaRadius.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.workspace_premium_outlined, color: OlfaColors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(l.yourProPlan(l.planLabel(x.plan)), style: t.h3.copyWith(color: OlfaColors.white))),
          if (x.featured) OlfaTag(l.featuredCounselor, style: OlfaTagStyle.primary, icon: Icons.verified_rounded),
        ]),
        const SizedBox(height: 8),
        Text(placement, style: t.bodyMedium.copyWith(color: OlfaColors.white.withValues(alpha: 0.8))),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OlfaColors.white, foregroundColor: OlfaColors.black, shape: const StadiumBorder()),
            onPressed: onPlans,
            child: Text(x.plan == PlanCode.free ? l.seeProPlans : l.manageProPlan),
          ),
        ),
      ]),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.x});
  final ProInsights x;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Latin digits in every language, like prices across the app (ar_AE)
    final loc = switch (langOf(context)) { 'ar' => 'ar_AE', 'fr' => 'fr', _ => 'en' };
    final n = NumberFormat.decimalPattern(loc);
    final pct = NumberFormat.percentPattern(loc);
    Widget tile(IconData icon, String value, String label) => Expanded(
          child: Semantics(
            label: '$label: $value',
            excludeSemantics: true,
            child: OlfaCard(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: OlfaColors.primary, size: 22),
                  const SizedBox(height: 8),
                  Text(value, style: context.type.h2),
                  Text(label, style: context.type.caption, maxLines: 2),
                ]),
              ),
            ),
          ),
        );
    return Column(children: [
      Row(children: [
        tile(Icons.visibility_outlined, n.format(x.views), l.statViews),
        const SizedBox(width: 10),
        tile(Icons.person_outline_rounded, n.format(x.uniqueVisitors), l.statVisitors),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile(Icons.inbox_outlined, n.format(x.requests), l.statRequests),
        const SizedBox(width: 10),
        tile(Icons.trending_up_rounded, pct.format(x.conversion), l.statConversion),
      ]),
    ]);
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.onPlans});
  final VoidCallback onPlans;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return OlfaCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_outline_rounded, color: OlfaColors.primary),
          const SizedBox(height: 8),
          Text(l.insightsLockedTitle, style: t.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l.insightsLockedBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
          const SizedBox(height: 12),
          PrimaryButton(label: l.seeProPlans, expand: false, onPressed: onPlans),
        ]),
      ),
    );
  }
}
