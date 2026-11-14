import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../messaging/data/messaging_repository_impl.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../data/settings_repository.dart';

/// 24 — Privacy & security. Toggles update optimistically and roll back if
/// the server refuses (e.g. incognito without Premium).
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    final blocked = ref.watch(blockedCountProvider).valueOrNull ?? 0;
    final online = ref.watch(connectionProvider);

    Future<void> change(PrivacySettings next) async {
      final ok = await ref.read(privacyProvider.notifier).change(next);
      if (!ok && context.mounted) showToast(context, l.errorEntitlement);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.screenPrivacy)),
      body: AsyncView<PrivacySettings>(
        value: ref.watch(privacyProvider),
        onRetry: () => ref.invalidate(privacyProvider),
        data: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            SectionLabel(l.visibility, top: 4),
            TileGroup(children: [
              _SwitchTile(icon: Icons.place_outlined, title: l.showCity, value: s.showCity, onChanged: (v) => change(s.copyWith(showCity: v))),
              _SwitchTile(icon: Icons.blur_on_rounded, title: l.blurPhotos, subtitle: l.blurPhotosSub, value: s.blurPhotosUntilMatch, onChanged: (v) => change(s.copyWith(blurPhotosUntilMatch: v))),
              _SwitchTile(icon: Icons.circle_outlined, title: l.showOnline, value: s.showOnline, onChanged: (v) => change(s.copyWith(showOnline: v))),
              _SwitchTile(icon: Icons.done_all_rounded, title: l.readReceipts, value: s.readReceipts, onChanged: (v) => change(s.copyWith(readReceipts: v))),
              ent?.incognito ?? false
                  ? _SwitchTile(icon: Icons.visibility_off_outlined, title: l.incognito, subtitle: 'Premium', value: s.incognito, onChanged: (v) => change(s.copyWith(incognito: v)))
                  : OlfaListTile(
                      icon: Icons.visibility_off_outlined,
                      title: l.incognito,
                      subtitle: l.incognitoSub,
                      trailing: const OlfaTag('Premium', style: OlfaTagStyle.dark, icon: Icons.lock_outline_rounded),
                      onTap: () => context.push(Routes.plans),
                    ),
            ]),
            SectionLabel(l.security),
            TileGroup(children: [
              OlfaListTile(icon: Icons.block_rounded, title: l.blockedUsers, subtitle: l.blockedCount(blocked), onTap: () => showToast(context, l.blockedManageNote)),
              OlfaListTile(icon: Icons.phone_iphone_rounded, title: l.signedInDevices, subtitle: l.thisDevice, onTap: () => showToast(context, l.sessionsNote)),
              OlfaListTile(icon: Icons.download_rounded, title: l.downloadMyData, subtitle: l.downloadMyDataSub, onTap: () => showToast(context, l.dataExportRequested)),
            ]),
            SectionLabel(l.developerPreview),
            TileGroup(children: [
              // Demo-only: lets reviewers see offline UI states.
              _SwitchTile(icon: Icons.wifi_off_rounded, title: l.simulateOffline, value: !online, onChanged: (v) => ref.read(connectionProvider.notifier).set(!v)),
            ]),
          ],
        ),
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
