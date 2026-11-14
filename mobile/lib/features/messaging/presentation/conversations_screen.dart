import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../data/messaging_repository_impl.dart';

/// 18 — Conversations list with local search.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});
  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final online = ref.watch(connectionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.screenConversations), automaticallyImplyLeading: false),
      body: Column(
        children: [
          if (!online) OfflineBar(text: l.offlineBanner),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(hintText: l.searchConversations, prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: AsyncView<List<Conversation>>(
              value: ref.watch(conversationsProvider),
              onRetry: () => ref.invalidate(conversationsProvider),
              data: (all) {
                final list = _q.isEmpty ? all : all.where((c) => c.peer.name.contains(_q)).toList();
                if (all.isEmpty) {
                  return EmptyState(icon: Icons.chat_bubble_outline_rounded, title: l.noChatsTitle, body: l.noChatsBody, action: PrimaryButton(label: l.screenMatches, expand: false, onPressed: () => context.go(Routes.matches)));
                }
                return RefreshIndicator(
                  color: OlfaColors.primary,
                  onRefresh: () => ref.refresh(conversationsProvider.future),
                  child: ListView.builder(
                    padding: EdgeInsets.only(bottom: OlfaSize.navBarClearance(context)),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final c = list[i];
                      final unread = c.unread > 0;
                      return InkWell(
                        onTap: () => context.push(Routes.chatWith(c.id)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: Row(children: [
                            OlfaAvatar(size: 56, url: c.peer.mainPhoto?.thumbUrl, online: c.peer.online),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(child: Text(c.peer.name, overflow: TextOverflow.ellipsis, style: t.bodyMedium.copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w500))),
                                  if (c.peer.photosReviewed) ...[const SizedBox(width: 6), const VerifiedBadge(size: 16)],
                                  const Spacer(),
                                  if (c.lastAt != null) Text(shortTime(context, c.lastAt!), style: t.caption),
                                ]),
                                const SizedBox(height: 2),
                                Row(children: [
                                  Expanded(
                                    child: Text(
                                      c.lastMessage ?? l.saySalam,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.bodySmall.copyWith(color: unread ? OlfaColors.black : OlfaColors.textMuted, fontWeight: unread ? FontWeight.w500 : FontWeight.w400),
                                    ),
                                  ),
                                  if (unread)
                                    Container(
                                      margin: const EdgeInsetsDirectional.only(start: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(color: OlfaColors.primary, borderRadius: OlfaRadius.all(10)),
                                      child: Text('${c.unread}', style: const TextStyle(color: OlfaColors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                    ),
                                ]),
                              ]),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class OfflineBar extends StatelessWidget {
  const OfflineBar({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: OlfaColors.black,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: OlfaColors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.type.bodySmall.copyWith(color: OlfaColors.white))),
        ]),
      );
}
