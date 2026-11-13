import 'package:flutter/material.dart';

import '../../core/localization/generated/app_localizations.dart';
import '../../core/widgets/olfa_widgets.dart';

/// Temporary route target for screens whose approved design lives in
/// preview/index.html and whose Flutter implementation is scheduled for
/// Phase 2. It is clearly labelled — never presented as a finished feature.
class InProgressScreen extends StatelessWidget {
  const InProgressScreen({super.key, required this.title, this.showBack = true});
  final String title;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: showBack),
      body: OlfaEmptyState(icon: Icons.construction_rounded, title: l.inProgressTitle, body: l.inProgressBody),
    );
  }
}
