import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/services/demo_backend.dart';
import '../data/settings_repository.dart';

/// Notification preferences kept locally for the UI phase (synced in Phase 3).
class NotificationPrefs extends Notifier<({bool matches, bool likes})> {
  @override
  ({bool matches, bool likes}) build() => (matches: true, likes: true);
  void set({bool? matches, bool? likes}) => state = (matches: matches ?? state.matches, likes: likes ?? state.likes);
}

final notificationPrefsProvider = NotifierProvider<NotificationPrefs, ({bool matches, bool likes})>(NotificationPrefs.new);

/// 26 — Settings & account deletion.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final lang = ref.watch(localeProvider).languageCode;
    final np = ref.watch(notificationPrefsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.screenSettings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          SectionLabel(l.general, top: 4),
          TileGroup(children: [
            OlfaListTile(icon: Icons.language_rounded, title: l.language, subtitle: lang == 'ar' ? 'العربية' : 'English', onTap: () => ref.read(localeProvider.notifier).toggle()),
          ]),
          SectionLabel(l.pushNotifications),
          TileGroup(children: [
            OlfaListTile(
              icon: Icons.chat_bubble_outline_rounded,
              title: l.notifMatchesMessages,
              onTap: () => ref.read(notificationPrefsProvider.notifier).set(matches: !np.matches),
              trailing: Switch(value: np.matches, onChanged: (v) => ref.read(notificationPrefsProvider.notifier).set(matches: v)),
            ),
            OlfaListTile(
              icon: Icons.favorite_border_rounded,
              title: l.notifLikes,
              onTap: () => ref.read(notificationPrefsProvider.notifier).set(likes: !np.likes),
              trailing: Switch(value: np.likes, onChanged: (v) => ref.read(notificationPrefsProvider.notifier).set(likes: v)),
            ),
          ]),
          SectionLabel(l.about),
          TileGroup(children: [
            OlfaListTile(icon: Icons.description_outlined, title: l.terms, onTap: () => showToast(context, l.legalLinkNote)),
            OlfaListTile(icon: Icons.shield_outlined, title: l.privacyPolicy, onTap: () => showToast(context, l.legalLinkNote)),
            OlfaListTile(icon: Icons.info_outline_rounded, title: l.version, trailing: Text('0.2.0 (2)', textDirection: TextDirection.ltr, style: context.type.caption)),
          ]),
          const SizedBox(height: 16),
          TileGroup(children: [
            OlfaListTile(
              icon: Icons.logout_rounded,
              title: l.signOut,
              showChevron: false,
              onTap: () async {
                final ok = await showConfirmation(context, title: l.signOutConfirm, body: l.signOutBody, confirmLabel: l.signOut, icon: Icons.logout_rounded);
                if (ok && context.mounted) context.go(Routes.splash);
              },
            ),
            OlfaListTile(icon: Icons.delete_outline_rounded, title: l.deleteAccount, danger: true, showChevron: false, onTap: () => _delete(context, ref)),
          ]),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final reason = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _DeleteSheet(),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(settingsRepositoryProvider).requestDeletion(reason.isEmpty ? null : reason);
      if (!context.mounted) return;
      final l = AppLocalizations.of(context);
      ref.invalidate(demoBackendProvider);
      showToast(context, l.deletionScheduled);
      context.go(Routes.splash);
    } catch (e) {
      if (context.mounted) showToast(context, failureMessage(context, e));
    }
  }
}

class _DeleteSheet extends StatefulWidget {
  const _DeleteSheet();
  @override
  State<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends State<_DeleteSheet> {
  String? _why;
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final reasons = {'found': l.leaveFound, 'no_fit': l.leaveNoFit, 'break': l.leaveBreak, 'other': l.leaveOther};
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(18)),
              child: const Icon(Icons.delete_outline_rounded, color: OlfaColors.primary, size: 26),
            ),
            const SizedBox(height: 14),
            Text(l.deleteAccount, style: t.h2),
            const SizedBox(height: 8),
            Text(l.deleteBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
            const SizedBox(height: 16),
            Text(l.leaveReason, style: t.inputLabel),
            const SizedBox(height: 8),
            ChoiceWrap<String>(options: reasons.keys.toList(), label: (k) => reasons[k]!, isSelected: (k) => _why == k, onTap: (k) => setState(() => _why = k)),
            const SizedBox(height: 14),
            OlfaCheck(value: _understood, onChanged: (v) => setState(() => _understood = v), label: l.deleteUnderstand),
            const SizedBox(height: 16),
            PrimaryButton(label: l.deletePermanently, onPressed: _understood ? () => Navigator.of(context).pop(_why ?? '') : null),
            const SizedBox(height: 8),
            SecondaryButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
