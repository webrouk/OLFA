import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/sound/sound_service.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/services/demo_backend.dart';
import '../../account/account_type.dart';
import '../../authentication/data/auth_repository_impl.dart';
import '../data/settings_repository.dart';
import '../../../shared/components/labels.dart';

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
            OlfaListTile(
              icon: Icons.language_rounded,
              title: l.language,
              subtitle: ref.read(localeProvider.notifier).choice == LanguageChoice.system
                  ? '${l.languageSystem} · ${kNativeLanguageNames[lang] ?? 'English'}'
                  : (kNativeLanguageNames[lang] ?? 'English'),
              onTap: () => context.push(Routes.languageSettings),
            ),
            // members only: an account run by a family member on the owner's behalf
            if (!(ref.watch(accountTypeProvider)?.isProfessional ?? false))
              OlfaListTile(icon: Icons.family_restroom_rounded, title: l.accountManagement, onTap: () => context.push(Routes.accountManagement)),
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
            Consumer(builder: (context, ref, _) {
              final on = ref.watch(soundsEnabledProvider);
              return OlfaListTile(
                icon: Icons.music_note_outlined,
                title: l.inAppSounds,
                subtitle: l.inAppSoundsSub,
                onTap: () => ref.read(soundsEnabledProvider.notifier).set(!on),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: l.previewSound, icon: const Icon(Icons.play_circle_outline_rounded), onPressed: () => ref.read(soundServiceProvider).play(OlfaSound.notification)),
                  Switch(value: on, onChanged: (v) => ref.read(soundsEnabledProvider.notifier).set(v)),
                ]),
              );
            }),
          ]),
          SectionLabel(l.about),
          TileGroup(children: [
            OlfaListTile(icon: Icons.description_outlined, title: l.terms, onTap: () => context.push(Routes.terms)),
            OlfaListTile(icon: Icons.shield_outlined, title: l.privacyPolicy, onTap: () => context.push(Routes.privacyPolicy)),
            OlfaListTile(icon: Icons.info_outline_rounded, title: l.version, trailing: Text('0.3.0 (3)', textDirection: TextDirection.ltr, style: context.type.caption)),
          ]),
          const SizedBox(height: 16),
          TileGroup(children: [
            OlfaListTile(
              icon: Icons.logout_rounded,
              title: l.signOut,
              showChevron: false,
              onTap: () async {
                final ok = await showConfirmation(context, title: l.signOutConfirm, body: l.signOutBody, confirmLabel: l.signOut, icon: Icons.logout_rounded);
                if (!ok) return;
                await ref.read(authRepositoryProvider).logout(); // revokes this device's session
                if (context.mounted) context.go(Routes.splash);
              },
            ),
            OlfaListTile(icon: Icons.pause_circle_outline_rounded, title: l.freezeAccount, subtitle: l.freezeAccountSub, showChevron: false, onTap: () => _freeze(context, ref)),
            OlfaListTile(icon: Icons.delete_outline_rounded, title: l.deleteAccount, danger: true, showChevron: false, onTap: () => _delete(context, ref)),
          ]),
        ],
      ),
    );
  }

  Future<void> _freeze(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const _FreezeSheet());
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(settingsRepositoryProvider).freeze();
      if (context.mounted) {
        showToast(context, l.frozenDone);
        context.go(Routes.frozen);
      }
    } catch (e) {
      if (context.mounted) showToast(context, failureMessage(context, e));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // Offer a break first: everything stays, including the subscription.
    final choice = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const _FreezeSheet(beforeDelete: true));
    if (!context.mounted || choice == null) return;
    if (choice == 'freeze') {
      try {
        await ref.read(settingsRepositoryProvider).freeze();
        if (context.mounted) context.go(Routes.frozen);
      } catch (e) {
        if (context.mounted) showToast(context, failureMessage(context, e));
      }
      return;
    }
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

/// "Take a break instead": freeze keeps data, matches, chats and subscription.
class _FreezeSheet extends StatelessWidget {
  const _FreezeSheet({this.beforeDelete = false});
  final bool beforeDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    Widget point(IconData i, String s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, size: 19, color: OlfaColors.primary), const SizedBox(width: 10), Expanded(child: Text(s, style: t.bodyMedium))]),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(18)),
            child: const Icon(Icons.pause_circle_outline_rounded, color: OlfaColors.primary, size: 28),
          ),
          const SizedBox(height: 14),
          Text(beforeDelete ? l.freezeInsteadTitle : l.freezeAccount, style: t.h2),
          const SizedBox(height: 8),
          Text(l.freezeIntro, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
          const SizedBox(height: 16),
          point(Icons.visibility_off_outlined, l.freezePointHidden),
          point(Icons.inventory_2_outlined, l.freezePointData),
          point(Icons.workspace_premium_outlined, l.freezePointSubscription),
          point(Icons.login_rounded, l.freezePointReturn),
          const SizedBox(height: 8),
          PrimaryButton(label: l.freezeConfirm, icon: Icons.pause_rounded, onPressed: () => Navigator.of(context).pop(beforeDelete ? 'freeze' : true)),
          const SizedBox(height: 8),
          if (beforeDelete)
            SecondaryButton(label: l.continueToDelete, onPressed: () => Navigator.of(context).pop('delete'))
          else
            SecondaryButton(label: l.cancel, onPressed: () => Navigator.of(context).pop(false)),
        ]),
      ),
    );
  }
}

/// Shown while the account is frozen (also after signing in to a frozen account).
class FrozenAccountScreen extends ConsumerStatefulWidget {
  const FrozenAccountScreen({super.key});
  @override
  ConsumerState<FrozenAccountScreen> createState() => _FrozenAccountScreenState();
}

class _FrozenAccountScreenState extends ConsumerState<FrozenAccountScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(36)),
              child: const Icon(Icons.pause_circle_outline_rounded, size: 52, color: OlfaColors.primary),
            ),
            const SizedBox(height: 22),
            Text(l.frozenTitle, style: context.type.h1, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(l.frozenBody, style: context.type.bodyMedium.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center),
            const Spacer(),
            PrimaryButton(
              label: l.reactivate,
              loading: _busy,
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await ref.read(settingsRepositoryProvider).unfreeze();
                        if (context.mounted) context.go(Routes.discover);
                      } catch (e) {
                        if (context.mounted) showToast(context, failureMessage(context, e));
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
            ),
            const SizedBox(height: 8),
            SecondaryButton(label: l.screenSettings, onPressed: () => context.push(Routes.settings)),
          ]),
        ),
      ),
    );
  }
}

/// Language: follow the device (default, matches iOS per-app language and
/// Android 13+ app languages) or choose Arabic / English / French inside the
/// app. A device in any other language gets English.
class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    ref.watch(localeProvider);
    final choice = ref.read(localeProvider.notifier).choice;
    Widget opt(LanguageChoice c, String title, String? sub) => OlfaListTile(
          icon: c == LanguageChoice.system ? Icons.phone_iphone_rounded : Icons.translate_rounded,
          title: title,
          subtitle: sub,
          showChevron: false,
          trailing: Icon(choice == c ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: choice == c ? OlfaColors.primary : OlfaColors.textDisabled),
          onTap: () => ref.read(localeProvider.notifier).choose(c),
        );
    return Scaffold(
      appBar: AppBar(title: Text(l.language)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
        TileGroup(children: [
          opt(LanguageChoice.system, l.languageSystem, l.languageSystemSub),
          for (final c in const [LanguageChoice.ar, LanguageChoice.en, LanguageChoice.fr])
            opt(c, kNativeLanguageNames[c.name]!, languageNameIn(langOf(context), c.name)),
        ]),
        const SizedBox(height: 12),
        Text(l.languageNote, style: context.type.caption),
      ]),
    );
  }
}
