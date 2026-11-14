import 'package:flutter/material.dart';

import '../../core/localization/generated/app_localizations.dart';
import '../../core/theme/olfa_colors.dart';
import '../../core/theme/olfa_spacing.dart';
import '../../core/theme/olfa_typography.dart';
import '../../core/widgets/olfa_widgets.dart';
import '../models/models.dart';
import 'labels.dart';

class SubscriptionCard extends StatelessWidget {
  const SubscriptionCard({super.key, required this.plan, required this.selected, required this.current, required this.onTap, this.highlight = false});
  final PlanInfo plan;
  final bool selected;
  final bool current;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final fg = highlight ? OlfaColors.white : OlfaColors.black;
    final features = <String>[
      l.planLikesPerDay(plan.dailyLikes),
      l.planStartersPerDay(plan.dailyMessages),
      plan.code == PlanCode.free ? l.planBasicFilters : (plan.code == PlanCode.plus ? l.planExtraFilters : l.planAllFilters),
      if (plan.seeWhoLikedYou) l.planSeeLikes,
      if (plan.dailyUndos > 0) l.planUndos(plan.dailyUndos),
      if (plan.priorityVisibility) l.planPriority,
    ];
    return Semantics(
      selected: selected,
      button: true,
      child: PressScale(
        child: Material(
          color: highlight ? OlfaColors.black : OlfaColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: OlfaRadius.all(22),
            side: BorderSide(color: selected ? OlfaColors.primary : (highlight ? OlfaColors.black : OlfaColors.gray), width: selected ? 2.5 : 1.5),
          ),
          child: InkWell(
            borderRadius: OlfaRadius.all(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(l.planLabel(plan.code), style: t.h3.copyWith(fontSize: 19, color: fg)),
                      const SizedBox(width: 8),
                      if (highlight) OlfaTag(l.mostPopular, style: OlfaTagStyle.primary),
                      if (current) ...[const SizedBox(width: 6), OlfaTag(l.currentPlan, style: highlight ? OlfaTagStyle.onImage : OlfaTagStyle.accent)],
                      const Spacer(),
                      Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? (highlight ? OlfaColors.white : OlfaColors.primary) : (highlight ? OlfaColors.white : OlfaColors.textDisabled)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.code == PlanCode.free ? l.planFree : (plan.localizedPrice ?? l.priceFromStore),
                    style: t.caption.copyWith(color: highlight ? OlfaColors.white.withValues(alpha: 0.7) : null),
                  ),
                  const SizedBox(height: 12),
                  for (final f in features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.check_rounded, size: 18, color: highlight ? OlfaColors.white : OlfaColors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f, style: t.bodyMedium.copyWith(color: fg))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
