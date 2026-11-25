import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/text_fold.dart';
import '../../consultations/presentation/consult_labels.dart';
import '../data/messaging_repository_impl.dart';
import 'conversations_screen.dart' show ConversationTile, OfflineBar;

/// Which consultation chats a counselor (or client) sees in one tab.
List<Conversation> consultChatsIn(ConversationIndex ix, ConsultChatState tab, {String query = '', ConsultationStatus? status}) {
  final q = foldForSearch(query.trim());
  return ix
      .section(ConversationSection.consultation)
      .where((c) => c.consultState == tab)
      .where((c) => status == null || c.counselor?.status == status)
      .where((c) => q.isEmpty || foldForSearch('${c.title} ${c.lastMessage ?? ''}').contains(q))
      .toList();
}

/// Counselor messages: search, Active · Ended · Archive, a session-status filter.
/// Ended chats show how long they remain before they are deleted for both sides.
class CounselorInboxScreen extends ConsumerStatefulWidget {
  const CounselorInboxScreen({super.key});
  @override
  ConsumerState<CounselorInboxScreen> createState() => _CounselorInboxScreenState();
}

class _CounselorInboxScreenState extends ConsumerState<CounselorInboxScreen> {
  final _search = TextEditingController();
  ConsultChatState _tab = ConsultChatState.active;
  ConsultationStatus? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final online = ref.watch(connectionProvider);
    final ix = ref.watch(conversationIndexProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.screenConversations), automaticallyImplyLeading: false),
      body: Column(children: [
        if (!online) OfflineBar(text: l.offlineBanner),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l.consultSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(tooltip: l.clear, icon: const Icon(Icons.close_rounded), onPressed: () => setState(_search.clear)),
            ),
          ),
        ),
        Expanded(
          child: AsyncView<ConversationIndex>(
            value: ix,
            onRetry: () => ref.invalidate(conversationIndexProvider),
            data: (ix) {
              int count(ConsultChatState s) => consultChatsIn(ix, s).length;
              final inTab = consultChatsIn(ix, _tab, query: _search.text);
              final statuses = {for (final c in inTab) if (c.counselor?.status != null) c.counselor!.status!}.toList()..sort((a, b) => a.index.compareTo(b.index));
              final rows = _status == null ? inTab : inTab.where((c) => c.counselor?.status == _status).toList();
              return RefreshIndicator(
                color: OlfaColors.primary,
                onRefresh: () => ref.refresh(conversationIndexProvider.future),
                child: CustomScrollView(slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: _Tabs(
                        value: _tab,
                        labels: {
                          ConsultChatState.active: (l.consultActive, count(ConsultChatState.active)),
                          ConsultChatState.ended: (l.consultEnded, count(ConsultChatState.ended)),
                          ConsultChatState.archived: (l.consultArchived, count(ConsultChatState.archived)),
                        },
                        onChanged: (t) => setState(() {
                          _tab = t;
                          _status = null;
                        }),
                      ),
                    ),
                  ),
                  if (statuses.length > 1)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                            OlfaChoice(label: l.all, selected: _status == null, small: true, onTap: () => setState(() => _status = null)),
                            for (final s in statuses) ...[
                              const SizedBox(width: 8),
                              OlfaChoice(label: statusStyle(l, s).$1, selected: _status == s, small: true, onTap: () => setState(() => _status = _status == s ? null : s)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (_tab != ConsultChatState.active)
                    SliverToBoxAdapter(
                      child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: InfoBanner(icon: Icons.schedule_rounded, text: l.consultRetentionNote)),
                    ),
                  if (rows.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _search.text.trim().isNotEmpty
                          ? EmptyState(icon: Icons.search_off_rounded, title: l.noResults, body: '')
                          : switch (_tab) {
                              ConsultChatState.active => EmptyState(icon: Icons.forum_outlined, title: l.consultEmptyActive, body: l.consultEmptyActiveBody),
                              ConsultChatState.ended => EmptyState(icon: Icons.history_rounded, title: l.consultEmptyEnded, body: l.consultEmptyEndedBody),
                              ConsultChatState.archived => EmptyState(icon: Icons.inventory_2_outlined, title: l.consultEmptyArchive, body: l.consultEmptyArchiveBody),
                            },
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.only(bottom: OlfaSize.navBarClearance(context)),
                      // lazy: only the rows on screen are built
                      sliver: SliverList.builder(itemCount: rows.length, itemBuilder: (_, i) => ConversationTile(key: ValueKey(rows[i].id), conversation: rows[i])),
                    ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Three equal tabs with counts (Active · Ended · Archive).
class _Tabs extends StatelessWidget {
  const _Tabs({required this.value, required this.labels, required this.onChanged});
  final ConsultChatState value;
  final Map<ConsultChatState, (String, int)> labels;
  final ValueChanged<ConsultChatState> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(22)),
      child: Row(children: [
        for (final e in labels.entries)
          Expanded(
            child: Semantics(
              selected: e.key == value,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: e.key == value ? OlfaColors.white : null, borderRadius: OlfaRadius.all(19)),
                  child: Text(
                    e.value.$2 > 0 ? '${e.value.$1} · ${e.value.$2}' : e.value.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall.copyWith(fontWeight: e.key == value ? FontWeight.w700 : FontWeight.w500, color: e.key == value ? OlfaColors.primary : OlfaColors.black),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
