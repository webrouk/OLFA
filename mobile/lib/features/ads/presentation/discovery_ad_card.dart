import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../data/native_ad_gateway.dart';

/// A native ad in Discovery, in the same frame as [ProfileCard]: same size,
/// corner radius, border and shadow, with a clear "Sponsored" label above the
/// ad content.
///
/// Touches on the ad go only to the ad: the card has no swipe gesture, it is
/// never wrapped by the like/pass GestureDetector, and Discovery replaces the
/// like/pass/undo buttons with a single "Continue" button while it is shown.
class DiscoveryAdCard extends StatelessWidget {
  const DiscoveryAdCard({super.key, required this.ad});
  final LoadedNativeAd ad;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Semantics(
      container: true,
      label: l.adSponsored,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: OlfaColors.white,
          borderRadius: OlfaRadius.all(OlfaRadius.profileCard),
          border: Border.all(color: OlfaColors.gray),
          boxShadow: [BoxShadow(color: OlfaColors.black.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: OlfaColors.black, borderRadius: BorderRadius.circular(OlfaRadius.chip)),
                    child: Text(l.adSponsored, style: t.caption.copyWith(color: OlfaColors.white, fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  // Outside the ad view, so it never competes with the ad's own taps.
                  TextButton(
                    onPressed: () => context.push(Routes.plans),
                    child: Text(l.adRemove, style: t.caption.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                // Own layer: the platform view repaints without repainting Discovery.
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: OlfaRadius.all(OlfaRadius.card),
                    child: ad.view(),
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
