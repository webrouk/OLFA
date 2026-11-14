import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../data/notifications_repository.dart';

/// 20 — Notifications, grouped Today / Earlier.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static IconData _icon(NotificationKind k) => switch (k) {
        NotificationKind.match => Icons.people_alt_outlined,
        NotificationKind.like => Icons.favorite_border_rounded,
        NotificationKind.verification => Icons.verified_user_outlined,
        NotificationKind.message => Icons.chat_bubble_outline_rounded,
        NotificationKind.reminder => Icons.person_outline_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.screenNotifications),
        actions: [
          OlfaIconButton(
            icon: Icons.done_all_rounded,
            tooltip: l.markAllRead,
            onPressed: () async {
              await ref.read(notificationsRepositoryProvider).markAllRead();
              ref.invalidate(notificationsProvider);
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AsyncView<List<AppNotification>>(
        value: ref.watch(notificationsProvider),
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (list) {
          if (list.isEmpty) return EmptyState(icon: Icons.notifications_none_rounded, title: l.noNotificationsTitle, body: l.noNotificationsBody);
          final today = list.where((n) => DateUtils.isSameDay(n.createdAt, DateTime.now())).toList();
          final earlier = list.where((n) => !DateUtils.isSameDay(n.createdAt, DateTime.now())).toList();
          Widget tile(AppNotification n) => Container(
                color: n.read ? null : OlfaColors.primaryTint(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: n.read ? OlfaColors.gray : OlfaColors.white, shape: BoxShape.circle),
                    child: Icon(_icon(n.kind), size: 20, color: n.read ? OlfaColors.black : OlfaColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.title, style: t.bodyMedium.copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w600)),
                      Text(shortTime(context, n.createdAt), style: t.caption),
                    ]),
                  ),
                  if (!n.read) Container(width: 9, height: 9, decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle)),
                ]),
              );
          return RefreshIndicator(
            color: OlfaColors.primary,
            onRefresh: () => ref.refresh(notificationsProvider.future),
            child: ListView(
              children: [
                if (today.isNotEmpty) ...[Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SectionLabel(l.today, top: 4)), ...today.map(tile)],
                if (earlier.isNotEmpty) ...[Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SectionLabel(l.earlier)), ...earlier.map(tile)],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}
