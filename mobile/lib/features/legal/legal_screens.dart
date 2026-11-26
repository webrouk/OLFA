import 'package:flutter/material.dart';

import '../../core/theme/olfa_colors.dart';
import '../../core/theme/olfa_typography.dart';
import '../../shared/components/labels.dart';
import 'legal_content.dart';

/// Terms of Use / Privacy Policy, in the app's language, readable offline.
class LegalScreen extends StatelessWidget {
  const LegalScreen.terms({super.key}) : privacy = false, professional = false;
  const LegalScreen.privacy({super.key}) : privacy = true, professional = false;
  const LegalScreen.professional({super.key}) : privacy = false, professional = true;
  final bool privacy;
  final bool professional;

  @override
  Widget build(BuildContext context) {
    final lang = langOf(context);
    final doc = professional ? professionalPolicyOf(lang) : privacy ? privacyOf(lang) : termsOf(lang);
    final t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            Text(doc.updated, style: t.caption),
            const SizedBox(height: 12),
            Text(doc.intro, style: t.bodyLarge),
            for (final s in doc.sections) ...[
              const SizedBox(height: 22),
              Semantics(header: true, child: Text(s.title, style: t.h3.copyWith(color: OlfaColors.primary))),
              const SizedBox(height: 8),
              Text(s.body, style: t.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
