import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../../../core/network/api_client.dart' show useApi;
import '../../messaging/data/messaging_repository_impl.dart';
import '../../profile/application/profile_controllers.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../data/settings_repository.dart';

/// 24 — Privacy & security. Every switch is stored and enforced by the
/// server: discovery visibility, incognito (Premium), blurred photos, and the
/// reciprocal online status and read receipts.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    final blocked = ref.watch(blockedCountProvider).valueOrNull ?? 0;
    final online = ref.watch(connectionProvider);

    Future<void> change(PrivacySettings next) async {
      final err = await ref.read(privacyProvider.notifier).change(next);
      // Profile views (my card, discovery) reflect the new state immediately.
      ref
        ..invalidate(myProfileProvider)
        ..invalidate(conversationIndexProvider);
      if (err != null && context.mounted) showToast(context, failureMessage(context, err));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.screenPrivacy)),
      body: AsyncView<PrivacySettings>(
        value: ref.watch(privacyProvider),
        onRetry: () => ref.invalidate(privacyProvider),
        data: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            const SizedBox(height: 4),
            VisibilityCard(settings: s),
            SectionLabel(l.visibility),
            TileGroup(children: [
              _SwitchTile(icon: Icons.travel_explore_rounded, title: l.showInDiscovery, subtitle: l.showInDiscoverySub, value: s.discoverable, onChanged: (v) => change(s.copyWith(discoverable: v))),
              ent?.incognito ?? false
                  ? _SwitchTile(icon: Icons.visibility_off_outlined, title: l.incognito, subtitle: l.incognitoSub, value: s.incognito, onChanged: (v) => change(s.copyWith(incognito: v)))
                  : OlfaListTile(
                      icon: Icons.visibility_off_outlined,
                      title: l.incognito,
                      subtitle: l.incognitoSub,
                      trailing: const OlfaTag('Premium', style: OlfaTagStyle.dark, icon: Icons.lock_outline_rounded),
                      onTap: () => context.push(Routes.plans),
                    ),
              _SwitchTile(icon: Icons.place_outlined, title: l.showCity, subtitle: l.showCitySub, value: s.showCity, onChanged: (v) => change(s.copyWith(showCity: v))),
              _SwitchTile(icon: Icons.blur_on_rounded, title: l.blurPhotos, subtitle: l.blurPhotosSub, value: s.blurPhotosUntilMatch, onChanged: (v) => change(s.copyWith(blurPhotosUntilMatch: v))),
            ]),
            SectionLabel(l.activity),
            TileGroup(children: [
              _SwitchTile(icon: Icons.circle_outlined, title: l.showOnline, subtitle: l.showOnlineSub, value: s.showOnline, onChanged: (v) => change(s.copyWith(showOnline: v))),
              _SwitchTile(icon: Icons.done_all_rounded, title: l.readReceipts, subtitle: l.readReceiptsSub, value: s.readReceipts, onChanged: (v) => change(s.copyWith(readReceipts: v))),
            ]),
            SectionLabel(l.security),
            TileGroup(children: [
              OlfaListTile(icon: Icons.block_rounded, title: l.blockedUsers, subtitle: l.blockedCount(blocked), onTap: () => context.push(Routes.blockedUsers)),
              OlfaListTile(icon: Icons.devices_rounded, title: l.signedInDevices, subtitle: l.signedInDevicesSub, onTap: () => context.push(Routes.devices)),
              OlfaListTile(
                icon: Icons.download_rounded,
                title: l.downloadMyData,
                subtitle: l.downloadMyDataSub,
                onTap: () async {
                  try {
                    final json = await ref.read(settingsRepositoryProvider).exportData();
                    await Clipboard.setData(ClipboardData(text: json));
                    if (context.mounted) showToast(context, l.dataCopied);
                  } on Failure catch (e) {
                    if (context.mounted) showToast(context, failureMessage(context, e));
                  }
                },
              ),
            ]),
            if (!useApi) ...[
              SectionLabel(l.developerPreview),
              TileGroup(children: [
                // Demo-only: lets reviewers see offline UI states.
                _SwitchTile(icon: Icons.wifi_off_rounded, title: l.simulateOffline, value: !online, onChanged: (v) => ref.read(connectionProvider.notifier).set(!v)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Who can see me" summary — the same card is shown on My profile.
class VisibilityCard extends StatelessWidget {
  const VisibilityCard({super.key, required this.settings, this.onTap});
  final PrivacySettings settings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (icon, title, body) = switch (settings.visibility) {
      ProfileVisibility.visible => (Icons.visibility_outlined, l.visibilityVisible, l.visibilityVisibleBody),
      ProfileVisibility.incognito => (Icons.visibility_off_outlined, l.visibilityIncognito, l.visibilityIncognitoBody),
      ProfileVisibility.hidden => (Icons.pause_circle_outline_rounded, l.visibilityHidden, l.visibilityHiddenBody),
    };
    final tags = [
      if (!settings.showOnline) l.onlineHiddenTag,
      if (!settings.readReceipts) l.receiptsOffTag,
      if (settings.blurPhotosUntilMatch) l.photosBlurredTag,
      if (!settings.showCity) l.cityHiddenTag,
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InfoBanner(
        accent: settings.visibility != ProfileVisibility.visible,
        icon: icon,
        text: '$title — $body${tags.isEmpty ? '' : '\n${tags.join(' · ')}'}',
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({required this.icon, required this.title, required this.value, required this.onChanged, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: OlfaListTile(
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: () => onChanged(!value),
          trailing: Switch(value: value, onChanged: onChanged),
        ),
      );
}

/// Signed-in devices: one session per device; sign out any other device.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Scaffold(
      appBar: AppBar(title: Text(l.signedInDevices)),
      body: AsyncView<List<DeviceSession>>(
        value: ref.watch(devicesProvider),
        onRetry: () => ref.invalidate(devicesProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            InfoBanner(text: l.devicesNote, icon: Icons.security_rounded),
            const SizedBox(height: 14),
            TileGroup(children: [
              for (final d in list)
                OlfaListTile(
                  icon: d.platform == 'ios' ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                  title: '${d.platform == 'ios' ? 'iPhone / iPad' : 'Android'}${d.appVersion == null ? '' : ' · ${d.appVersion}'}',
                  subtitle: d.current ? l.thisDevice : l.lastActive(DateFormat.yMMMd(langOf(context)).add_Hm().format(d.lastUsedAt)),
                  showChevron: false,
                  trailing: d.current
                      ? OlfaTag(l.thisDevice, style: OlfaTagStyle.accent)
                      : TextButton(
                          onPressed: () async {
                            final ok = await showConfirmation(context, title: l.signOutDevice, body: l.signOutDeviceBody, confirmLabel: l.signOutDevice, icon: Icons.logout_rounded);
                            if (!ok) return;
                            try {
                              await ref.read(settingsRepositoryProvider).signOutDevice(d.id);
                              ref.invalidate(devicesProvider);
                            } on Failure catch (e) {
                              if (context.mounted) showToast(context, failureMessage(context, e));
                            }
                          },
                          child: Text(l.signOutDevice),
                        ),
                ),
            ]),
            const SizedBox(height: 10),
            Text(l.devicesFootnote, style: t.caption),
          ],
        ),
      ),
    );
  }
}

/// Blocked members: they can't find, like or message you. Unblock any time.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.blockedUsers)),
      body: AsyncView<List<BlockedUser>>(
        value: ref.watch(blockedUsersProvider),
        onRetry: () => ref.invalidate(blockedUsersProvider),
        data: (list) => list.isEmpty
            ? EmptyState(icon: Icons.block_rounded, title: l.noBlocked, body: l.noBlockedBody)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  InfoBanner(text: l.blockedNote, icon: Icons.block_rounded),
                  const SizedBox(height: 14),
                  TileGroup(children: [
                    for (final b in list)
                      OlfaListTile(
                        icon: Icons.person_off_outlined,
                        title: b.name,
                        subtitle: l.blockedOn(DateFormat.yMMMd(langOf(context)).format(b.blockedAt)),
                        showChevron: false,
                        trailing: TextButton(
                          onPressed: () async {
                            final ok = await showConfirmation(context, title: l.unblockTitle(b.name), body: l.unblockBody, confirmLabel: l.unblock, icon: Icons.lock_open_rounded);
                            if (!ok) return;
                            try {
                              await ref.read(settingsRepositoryProvider).unblock(b.userId);
                              ref
                                ..invalidate(blockedUsersProvider)
                                ..invalidate(blockedCountProvider);
                            } on Failure catch (e) {
                              if (context.mounted) showToast(context, failureMessage(context, e));
                            }
                          },
                          child: Text(l.unblock),
                        ),
                      ),
                  ]),
                ],
              ),
      ),
    );
  }
}
