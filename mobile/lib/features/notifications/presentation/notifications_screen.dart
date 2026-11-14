import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../data/notifications_repository.dart';

enum _Filter { all, unread, people, messages, consultations, account }

/// 20 — Notifications: filters, grouped by day, tap to open what it's about
/// (chat, likes, profile, consultation), swipe to remove, unread marker.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _Filter _filter = _Filter.all;
  final _hidden = <String>{}; // removed optimistically

  static (IconData, bool) _icon(NotificationKind k) => switch (k) {
        NotificationKind.match => (Icons.favorite_rounded, true),
        NotificationKind.like => (Icons.favorite_border_rounded, false),
        NotificationKind.compliment => (Icons.mark_chat_unread_outlined, true),
        NotificationKind.message => (Icons.chat_bubble_outline_rounded, false),
        NotificationKind.verification => (Icons.verified_outlined, false),
        NotificationKind.consultation => (Icons.support_agent_rounded, false),
        NotificationKind.rematch => (Icons.link_rounded, false),
        NotificationKind.chatExpiring => (Icons.schedule_rounded, false),
        NotificationKind.account => (Icons.workspace_premium_outlined, false),
        NotificationKind.reminder => (Icons.lightbulb_outline_rounded, false),
      };

  bool _matches(AppNotification n) => switch (_filter) {
        _Filter.all => true,
        _Filter.unread => !n.read,
        _Filter.people => const {NotificationKind.match, NotificationKind.like, NotificationKind.compliment, NotificationKind.rematch}.contains(n.kind),
        _Filter.messages => n.kind == NotificationKind.message || n.kind == NotificationKind.chatExpiring,
        _Filter.consultations => n.kind == NotificationKind.consultation,
        _Filter.account => n.kind == NotificationKind.verification || n.kind == NotificationKind.account || n.kind == NotificationKind.reminder,
      };

  /// Where a notification takes you.
  String? _target(AppNotification n) {
    final conv = n.data['conversationId'];
    return switch (n.kind) {
      NotificationKind.message || NotificationKind.chatExpiring || NotificationKind.rematch => conv != null ? Routes.chatWith(conv) : Routes.conversations,
      NotificationKind.match => conv != null ? Routes.chatWith(conv) : Routes.matches,
      NotificationKind.like || NotificationKind.compliment => Routes.likes,
      NotificationKind.consultation => conv != null ? Routes.chatWith(conv) : Routes.myConsultations,
      NotificationKind.verification => Routes.myProfile,
      NotificationKind.account => Routes.plans,
      NotificationKind.reminder => Routes.editProfile,
    };
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      ref.read(notificationsRepositoryProvider).markRead(n.id).catchError((_) {});
      ref.invalidate(notificationsProvider);
    }
    final to = _target(n);
    if (to != null) context.push(to);
  }

  Future<void> _remove(AppNotification n) async {
    setState(() => _hidden.add(n.id));
    try {
      await ref.read(notificationsRepositoryProvider).remove(n.id);
    } on Failure catch (e) {
      if (mounted) {
        setState(() => _hidden.remove(n.id));
        showToast(context, failureMessage(context, e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final unread = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.screenNotifications),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () async {
                await ref.read(notificationsRepositoryProvider).markAllRead();
                ref.invalidate(notificationsProvider);
              },
              child: Text(l.markAllRead),
            ),
          OlfaIconButton(icon: Icons.tune_rounded, tooltip: l.notificationSettings, onPressed: () => context.push(Routes.settings)),
          const SizedBox(width: 6),
        ],
      ),
      body: AsyncView<List<AppNotification>>(
        value: ref.watch(notificationsProvider),
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (all) {
          final list = all.where((n) => !_hidden.contains(n.id) && _matches(n)).toList();
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          String bucket(DateTime d) {
            final day = DateTime(d.year, d.month, d.day);
            final diff = today.difference(day).inDays;
            return diff <= 0 ? l.today : (diff == 1 ? l.yesterday : (diff < 7 ? l.thisWeek : l.earlier));
          }

          final groups = <String, List<AppNotification>>{};
          for (final n in list) {
            groups.putIfAbsent(bucket(n.createdAt), () => []).add(n);
          }
          return RefreshIndicator(
            color: OlfaColors.primary,
            onRefresh: () => ref.refresh(notificationsProvider.future),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      for (final f in _Filter.values)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: OlfaChoice(
                            label: switch (f) {
                              _Filter.all => l.all,
                              _Filter.unread => unread > 0 ? '${l.unread} · $unread' : l.unread,
                              _Filter.people => l.notifPeople,
                              _Filter.messages => l.notifMessages,
                              _Filter.consultations => l.consultationsShort,
                              _Filter.account => l.notifAccount,
                            },
                            selected: _filter == f,
                            onTap: () => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: _filter == _Filter.all ? l.noNotificationsTitle : l.noNotificationsHere,
                      body: _filter == _Filter.all ? l.noNotificationsBody : '',
                    ),
                  ),
                for (final g in groups.entries) ...[
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SectionLabel(g.key, top: 10)),
                  for (final n in g.value)
                    Dismissible(
                      key: ValueKey(n.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _remove(n),
                      background: Container(
                        alignment: AlignmentDirectional.centerEnd,
                        padding: const EdgeInsetsDirectional.only(end: 24),
                        color: OlfaColors.black,
                        child: const Icon(Icons.delete_outline_rounded, color: OlfaColors.white),
                      ),
                      child: _NotificationTile(n: n, icon: _icon(n.kind), onTap: () => _open(n)),
                    ),
                ],
                const SizedBox(height: 8),
                if (list.isNotEmpty) Center(child: Text(l.swipeToRemove, style: t.caption)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.icon, required this.onTap});
  final AppNotification n;
  final (IconData, bool) icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final strong = icon.$2; // match / compliment get the filled burgundy badge
    return Semantics(
      button: true,
      label: '${n.title}. ${n.body ?? ''}. ${shortTime(context, n.createdAt)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: n.read ? OlfaColors.white : OlfaColors.primaryTint(),
            borderRadius: OlfaRadius.all(16),
            border: Border.all(color: n.read ? OlfaColors.gray : OlfaColors.primary.withValues(alpha: 0.18)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: strong ? OlfaColors.primary : (n.read ? OlfaColors.gray : OlfaColors.white), shape: BoxShape.circle),
              child: Icon(icon.$1, size: 21, color: strong ? OlfaColors.white : (n.read ? OlfaColors.black : OlfaColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(n.title, style: t.bodyMedium.copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700))),
                  const SizedBox(width: 8),
                  Text(shortTime(context, n.createdAt), style: t.caption),
                ]),
                if (n.body != null && n.body!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(n.body!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall.copyWith(color: OlfaColors.textMuted)),
                ],
              ]),
            ),
            if (!n.read) ...[
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 6), child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle))),
            ],
          ]),
        ),
      ),
    );
  }
}
