import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../authentication/presentation/auth_screens.dart';

enum Gender { male, female }

/// 7 — Gender selection (step 1/4)
class GenderScreen extends StatefulWidget {
  const GenderScreen({super.key});
  @override
  State<GenderScreen> createState() => _GenderScreenState();
}

class _GenderScreenState extends State<GenderScreen> {
  Gender? _g;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    Widget card(Gender g, String label, IconData icon) {
      final on = _g == g;
      return Expanded(
        child: Material(
          color: on ? OlfaColors.primaryTint() : OlfaColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: OlfaRadius.all(18),
            side: BorderSide(color: on ? OlfaColors.primary : OlfaColors.gray, width: 1.5),
          ),
          child: InkWell(
            borderRadius: OlfaRadius.all(18),
            onTap: () => setState(() => _g = g),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: on ? OlfaColors.primary : OlfaColors.gray,
                    child: Icon(icon, size: 30, color: on ? OlfaColors.white : OlfaColors.black),
                  ),
                  const SizedBox(height: 14),
                  Text(label, style: t.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return FormPage(
      header: const SetupProgress(step: 1),
      action: OlfaButton(label: l.continueLabel, onPressed: _g == null ? null : () => context.push(Routes.profileInfo)),
      children: [
        Text(l.genderTitle, style: t.h1),
        const SizedBox(height: 8),
        Text(l.genderBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
        const SizedBox(height: 26),
        Row(children: [card(Gender.male, l.man, Icons.male_rounded), const SizedBox(width: 12), card(Gender.female, l.woman, Icons.female_rounded)]),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(16)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: OlfaColors.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(l.genderNote, style: t.bodySmall)),
            ],
          ),
        ),
      ],
    );
  }
}
