import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../discovery/application/discover_controller.dart';
import '../../matching/data/matching_repository_impl.dart';
import '../../messaging/data/messaging_repository_impl.dart';
import '../data/settings_repository.dart';

/// Report + optional block. Reports go to the moderation queue in the admin
/// dashboard; blocking hides both users from each other everywhere.
Future<void> showReportSheet(BuildContext context, WidgetRef ref, UserProfile user) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(user: user),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.user});
  final UserProfile user;
  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String? _reason;
  bool _block = true;
  bool _busy = false;

  Future<void> _submit() async {
    if (_reason == null || _busy) return;
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    try {
      await ref.read(settingsRepositoryProvider).report(widget.user.id, _reason!, block: _block);
      if (_block) {
        ref.invalidate(discoverControllerProvider);
        ref.invalidate(matchesProvider);
        ref.invalidate(conversationsProvider);
        ref.invalidate(blockedCountProvider);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(_block ? l.blockedToast : l.reportedToast)));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, failureMessage(context, e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final reasons = {
      'fake': l.reasonFake,
      'photos': l.reasonPhotos,
      'harassment': l.reasonHarassment,
      'scam': l.reasonScam,
      'underage': l.reasonUnderage,
      'not_serious': l.reasonNotSerious,
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.reportTitle(widget.user.name), style: context.type.h3),
              const SizedBox(height: 12),
              TileGroup(children: [
                for (final e in reasons.entries)
                  InkWell(
                    onTap: () => setState(() => _reason = e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(_reason == e.key ? Icons.radio_button_checked : Icons.radio_button_off, color: _reason == e.key ? OlfaColors.primary : OlfaColors.textDisabled),
                          const SizedBox(width: 12),
                          Expanded(child: Text(e.value, style: context.type.bodyMedium)),
                        ],
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              OlfaCheck(value: _block, onChanged: (v) => setState(() => _block = v), label: l.alsoBlock),
              const SizedBox(height: 14),
              PrimaryButton(label: l.submitReport, loading: _busy, onPressed: _reason == null ? null : _submit),
              const SizedBox(height: 6),
              SecondaryButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}
