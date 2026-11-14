import 'package:flutter/material.dart';

import '../../core/localization/generated/app_localizations.dart';
import '../../core/theme/olfa_colors.dart';
import '../models/models.dart';

/// Two distinct ticks next to a member's name:
///  • burgundy ✓ — photo verified (reviewed by our team / live selfie match);
///  • black ✓ — personal details verified (identity document check).
/// Each appears only when earned; long-press shows what it means.
class VerificationTicks extends StatelessWidget {
  const VerificationTicks({super.key, required this.profile, this.size = 18});
  final UserProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final photo = profile.photosReviewed || profile.livenessVerified;
    final data = profile.identityVerified;
    if (!photo && !data) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (photo) _Tick(size: size, color: OlfaColors.primary, label: l.tickPhoto),
      if (photo && data) const SizedBox(width: 3),
      if (data) _Tick(size: size, color: OlfaColors.black, label: l.tickIdentity),
    ]);
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.size, required this.color, required this.label});
  final double size;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.longPress,
        child: Semantics(
          label: label,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: size * 0.66, color: OlfaColors.white),
          ),
        ),
      );
}
