import 'package:flutter/material.dart';

import '../../core/localization/generated/app_localizations.dart';
import '../../core/theme/olfa_colors.dart';
import '../models/models.dart';

/// The single verification mark shown next to a member's name.
///
/// One check only, never two:
///  • burgundy — both the live selfie and the ID document are verified;
///  • grey — exactly one of them is verified;
///  • nothing — neither is.
/// Long-press explains which checks are done.
class VerificationMark extends StatelessWidget {
  const VerificationMark({super.key, required this.profile, this.size = 18});
  final UserProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) => VerificationMarkIcon(
        level: profile.verificationLevel,
        selfie: profile.livenessVerified,
        size: size,
      );
}

/// The mark itself, for callers that only know the level.
class VerificationMarkIcon extends StatelessWidget {
  const VerificationMarkIcon({super.key, required this.level, this.selfie = false, this.size = 18});
  final VerificationLevel level;

  /// For a partial mark: whether the verified half is the selfie (else the ID).
  final bool selfie;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (level == VerificationLevel.none) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final full = level == VerificationLevel.full;
    final label = full ? l.verifiedFull : (selfie ? l.verifiedSelfieOnly : l.verifiedIdOnly);
    return Tooltip(
      message: label,
      triggerMode: TooltipTriggerMode.longPress,
      child: Semantics(
        label: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: full ? OlfaColors.primary : OlfaColors.markGray, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: size * 0.66, color: OlfaColors.white),
        ),
      ),
    );
  }
}
