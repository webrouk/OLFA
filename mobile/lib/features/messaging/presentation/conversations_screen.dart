import 'dart:async';

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
import '../../settings/presentation/report_sheet.dart';
import '../application/chat_controller.dart';
import '../data/messaging_repository_impl.dart';
import '../../../shared/components/verification_ticks.dart';

/// 18 — Messages: search, Archive and Unmatched shortcuts, the plan's
/// visible-conversation meter, consultation chats, expiry chips and the
/// locked rows past the plan's limit.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});
  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _search = TextEditingController();
  String _q = ''; // debounced query sent to the server
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    setState(() {}); // local name filter updates on every keystroke
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _q = v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final online = ref.watch(connectionProvider);
    final ix = ref.watch(conversationIndexProvider);
    final counts = ix.valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.screenConversations), automaticallyImplyLeading: false),
      body: Column(
        children: [
          if (!online) OfflineBar(text: l.offlineBanner),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 14, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l.searchNamesMessages,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l.clear,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              _onSearch('');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _HeaderShortcut(
                icon: Icons.inventory_2_outlined,
                label: l.screenArchive,
                count: counts?.count(ConversationSection.archive) ?? 0,
                onTap: () => context.push(Routes.archive),
              ),
              _HeaderShortcut(
                icon: Icons.link_off_rounded,
                label: l.screenUnmatched,
                count: counts?.count(ConversationSection.unmatched) ?? 0,
                onTap: () => context.push(Routes.unmatched),
              ),
            ]),
          ),
          Expanded(
            child: AsyncView<ConversationIndex>(
              value: ix,
              onRetry: () => ref.invalidate(conversationIndexProvider),
              data: (ix) {
                final consult = ix.section(ConversationSection.consultation);
                final inbox = ix.section(ConversationSection.inbox);
                final locked = ix.lockedIn(ConversationSection.inbox);
                final typed = _search.text.trim();
                if (typed.length >= 2) return _SearchResults(query: _q.isEmpty ? typed : _q, index: ix);
                final shown = [...consult, ...inbox];
                if (consult.isEmpty && inbox.isEmpty && locked.isEmpty) {
                  return EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: l.noChatsTitle,
                    body: l.noChatsBody,
                    action: PrimaryButton(label: l.screenMatches, expand: false, onPressed: () => context.go(Routes.matches)),
                  );
                }
                return RefreshIndicator(
                  color: OlfaColors.primary,
                  onRefresh: () => ref.refresh(conversationIndexProvider.future),
                  child: ListView(
                    padding: EdgeInsets.only(bottom: OlfaSize.navBarClearance(context)),
                    children: [
                      _PlanMeter(index: ix),
                      for (final c in shown) ConversationTile(conversation: c),
                      if (locked.isNotEmpty) ...[
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SectionLabel(l.lockedConversationsTitle)),
                        for (final _ in locked.take(4)) const LockedConversationTile(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                          child: InfoBanner(
                            accent: true,
                            icon: Icons.workspace_premium_outlined,
                            text: '${l.lockedConversationsCount(locked.length)}. ${l.lockedLimitBody(ix.visibleLimit)}',
                            trailing: TextButton(onPressed: () => context.push(Routes.plans), child: Text(l.upgrade)),
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
                        child: Text(l.retentionNote, textAlign: TextAlign.center, style: context.type.caption),
                      ),
                    ],
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

/// Archive — inbox + archive share the plan's limit.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return _SectionScreen(
      title: l.screenArchive,
      note: l.archiveNote,
      icon: Icons.inventory_2_outlined,
      section: ConversationSection.archive,
      emptyTitle: l.archiveEmpty,
      emptyBody: l.archiveEmptyBody,
    );
  }
}

/// Unmatched — unlimited; deleted a month after the unmatch.
class UnmatchedScreen extends ConsumerWidget {
  const UnmatchedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return _SectionScreen(
      title: l.screenUnmatched,
      note: l.unmatchedNote,
      icon: Icons.link_off_rounded,
      section: ConversationSection.unmatched,
      emptyTitle: l.unmatchedEmpty,
      emptyBody: l.unmatchedEmptyBody,
    );
  }
}

class _SectionScreen extends ConsumerWidget {
  const _SectionScreen({required this.title, required this.note, required this.icon, required this.section, required this.emptyTitle, required this.emptyBody});
  final String title, note, emptyTitle, emptyBody;
  final IconData icon;
  final ConversationSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncView<ConversationIndex>(
        value: ref.watch(conversationIndexProvider),
        onRetry: () => ref.invalidate(conversationIndexProvider),
        data: (ix) {
          final rows = ix.section(section);
          final locked = ix.lockedIn(section);
          if (rows.isEmpty && locked.isEmpty) return EmptyState(icon: icon, title: emptyTitle, body: emptyBody);
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 10), child: InfoBanner(icon: icon, text: note)),
              for (final c in rows) ConversationTile(conversation: c),
              for (final _ in locked) const LockedConversationTile(),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderShortcut extends StatelessWidget {
  const _HeaderShortcut({required this.icon, required this.label, required this.count, required this.onTap});
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: count > 0 ? '$label, $count' : label,
      button: true,
      excludeSemantics: true,
      child: Stack(clipBehavior: Clip.none, children: [
        OlfaIconButton(icon: icon, tooltip: label, style: OlfaIconStyle.soft, size: 48, onPressed: onTap),
        if (count > 0)
          PositionedDirectional(
            top: -3,
            end: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(color: OlfaColors.primary, borderRadius: OlfaRadius.all(10), border: Border.all(color: OlfaColors.white, width: 2)),
              child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(color: OlfaColors.white, fontSize: 10.5, fontWeight: FontWeight.w700, fontFamily: 'Montserrat')),
            ),
          ),
      ]),
    );
  }
}

/// "3/5 conversations on your plan" with a thin meter.
class _PlanMeter extends ConsumerWidget {
  const _PlanMeter({required this.index});
  final ConversationIndex index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final total = index.count(ConversationSection.inbox) + index.count(ConversationSection.archive);
    final unlimited = index.visibleLimit < 0;
    final used = unlimited ? total : total.clamp(0, index.visibleLimit);
    final ratio = unlimited ? 1.0 : (index.visibleLimit == 0 ? 1.0 : (total / index.visibleLimit).clamp(0.0, 1.0).toDouble());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: OlfaColors.white, border: Border.all(color: OlfaColors.gray), borderRadius: OlfaRadius.all(14)),
        child: Row(children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: OlfaColors.primary),
          const SizedBox(width: 8),
          Text(l.conversationsOnPlan('$used', unlimited ? '∞' : '${index.visibleLimit}'), style: context.type.bodySmall.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: OlfaRadius.all(4),
              child: LinearProgressIndicator(value: ratio, minHeight: 5, color: OlfaColors.primary, backgroundColor: OlfaColors.gray),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One conversation row; long-press opens archive / restore / unmatch.
class ConversationTile extends ConsumerWidget {
  const ConversationTile({super.key, required this.conversation});
  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final c = conversation;
    final unread = c.unread > 0 && !c.isUnmatched;
    final days = c.expiresAt == null ? null : c.expiresAt!.difference(DateTime.now()).inDays.clamp(0, 99).toInt();
    final subtitle = switch (c.section) {
      ConversationSection.unmatched => switch (c.rematch?.status) {
          RematchStatus.pending => c.rematch!.byMe ? l.rematchWaiting(c.title) : l.rematchIncoming(c.title),
          RematchStatus.declined => l.rematchDeclined,
          _ => (c.unmatchedByMe ?? false) ? l.unmatchedByYou : l.unmatchedByThem(c.title),
        },
      _ => switch (c.lastMessageKind) {
          MessageKind.voice => '🎙 ${l.voiceMessageShort}',
          MessageKind.image when (c.lastMessage ?? '').isEmpty => '📷 ${l.photoMessageShort}',
          _ => c.lastMessage ?? (c.isConsultation ? l.consultationChatNote : l.saySalam),
        },
    };
    return InkWell(
      onTap: () => context.push(Routes.chatWith(c.id)),
      onLongPress: c.isConsultation ? null : () => showConversationMenu(context, ref, c),
      child: Opacity(
        opacity: c.isUnmatched ? 0.78 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(children: [
            if (c.peer != null)
              OlfaAvatar(size: 56, url: c.peer!.mainPhoto?.thumbUrl, online: c.peer!.online && !c.isUnmatched)
            else
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: OlfaColors.primaryTint(), shape: BoxShape.circle),
                child: const Icon(Icons.support_agent_rounded, color: OlfaColors.primary),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(c.title, overflow: TextOverflow.ellipsis, style: t.bodyMedium.copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w500))),
                  if (c.peer != null) ...[const SizedBox(width: 6), VerificationTicks(profile: c.peer!, size: 15)],
                  if (c.isConsultation) ...[const SizedBox(width: 6), OlfaTag(l.consultationTag, style: OlfaTagStyle.accent)],
                  const Spacer(),
                  if (c.lastAt != null) Text(shortTime(context, c.lastAt!), style: t.caption),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall.copyWith(color: unread ? OlfaColors.black : OlfaColors.textMuted, fontWeight: unread ? FontWeight.w500 : FontWeight.w400),
                    ),
                  ),
                  if (c.expiringSoon && days != null) ...[
                    const SizedBox(width: 8),
                    OlfaTag(l.expiresShort(days), style: OlfaTagStyle.accent, icon: Icons.schedule_rounded),
                  ],
                  if (c.isUnmatched && c.rematch?.status == RematchStatus.pending) ...[
                    const SizedBox(width: 8),
                    OlfaTag(l.rematchPendingTag, style: OlfaTagStyle.accent),
                  ],
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
      ),
    );
  }
}

/// A row past the plan's limit: no name, photo or preview reach the device.
class LockedConversationTile extends StatelessWidget {
  const LockedConversationTile({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return InkWell(
      onTap: () => context.push(Routes.plans),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: OlfaColors.gray, shape: BoxShape.circle),
            child: Icon(Icons.lock_outline_rounded, color: OlfaColors.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.hiddenConversation, style: context.type.bodyMedium.copyWith(fontWeight: FontWeight.w500, color: OlfaColors.textMuted)),
              const SizedBox(height: 6),
              Container(height: 10, width: 140, decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(5))),
            ]),
          ),
          const Icon(Icons.workspace_premium_outlined, color: OlfaColors.primary, size: 20),
        ]),
      ),
    );
  }
}

/// Archive / restore / unmatch / report for a match conversation.
Future<void> showConversationMenu(BuildContext context, WidgetRef ref, Conversation c) async {
  final l = AppLocalizations.of(context);
  final actions = ref.read(conversationActionsProvider);
  final messenger = ScaffoldMessenger.of(context);
  Future<void> run(Future<void> Function() op, String done) async {
    try {
      await op();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
    } on Failure catch (e) {
      if (context.mounted) showToast(context, failureMessage(context, e));
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 12), child: Text(c.title, style: sheet.type.h3)),
          TileGroup(children: [
            if (c.section == ConversationSection.inbox)
              OlfaListTile(
                icon: Icons.inventory_2_outlined,
                title: l.archiveAction,
                showChevron: false,
                onTap: () {
                  Navigator.of(sheet).pop();
                  run(() => actions.archive(c.id), l.archived);
                },
              ),
            if (c.section == ConversationSection.archive)
              OlfaListTile(
                icon: Icons.unarchive_outlined,
                title: l.restoreAction,
                showChevron: false,
                onTap: () {
                  Navigator.of(sheet).pop();
                  run(() => actions.restore(c.id), l.restored);
                },
              ),
            if (!c.isUnmatched)
              OlfaListTile(
                icon: Icons.link_off_rounded,
                title: l.unmatchAction,
                danger: true,
                showChevron: false,
                onTap: () async {
                  Navigator.of(sheet).pop();
                  final ok = await showConfirmation(context, title: l.unmatchConfirmTitle(c.title), body: l.unmatchConfirmBody, confirmLabel: l.unmatchAction, icon: Icons.link_off_rounded, destructive: true);
                  if (ok) await run(() => actions.unmatch(c.id), l.unmatchedDone);
                },
              ),
            if (c.peer != null)
              OlfaListTile(
                icon: Icons.flag_outlined,
                title: l.reportAction,
                showChevron: false,
                onTap: () {
                  Navigator.of(sheet).pop();
                  showReportSheet(context, ref, c.peer!);
                },
              ),
          ]),
        ]),
      ),
    ),
  );
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

/// Instant results while typing: conversations whose name matches (searched
/// locally and on the server) and messages whose text matches (server, all
/// unlocked conversations, including archived ones).
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.index});
  final String query;
  final ConversationIndex index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final res = ref.watch(chatSearchProvider(query));
    final q = query.toLowerCase();
    final byId = {for (final c in index.visible) c.id: c};
    final serverNames = res.valueOrNull?.conversationIds ?? const <String>[];
    final names = <Conversation>[
      ...index.visible.where((c) => c.title.toLowerCase().contains(q)),
      ...serverNames.map((id) => byId[id]).whereType<Conversation>().where((c) => !c.title.toLowerCase().contains(q)),
    ];
    final messages = res.valueOrNull?.messages ?? const <ChatMessage>[];
    return ListView(
      padding: EdgeInsets.only(bottom: OlfaSize.navBarClearance(context)),
      children: [
        if (res.isLoading) const LinearProgressIndicator(minHeight: 2, color: OlfaColors.primary, backgroundColor: OlfaColors.gray),
        if (names.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SectionLabel(l.searchPeople, top: 8)),
          for (final c in names) ConversationTile(conversation: c),
        ],
        if (messages.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SectionLabel(l.searchMessages)),
          for (final m in messages)
            InkWell(
              onTap: () => context.push(Routes.chatWith(m.conversationId)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: OlfaColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(byId[m.conversationId]?.title ?? '', style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                        Text(shortTime(context, m.sentAt), style: t.caption),
                      ]),
                      const SizedBox(height: 2),
                      _Highlighted(text: (m.fromMe ? '${l.you}: ' : '') + m.body, query: query),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
        if (!res.isLoading && names.isEmpty && messages.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Text(l.noResultsFor(query), textAlign: TextAlign.center, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted))),
      ],
    );
  }
}

/// The matching part of a message preview in bold burgundy.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query});
  final String text;
  final String query;
  @override
  Widget build(BuildContext context) {
    final base = context.type.bodySmall.copyWith(color: OlfaColors.textMuted);
    final i = text.toLowerCase().indexOf(query.toLowerCase());
    if (i < 0 || query.isEmpty) return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: base);
    // keep the match visible in long messages
    final start = i > 40 ? i - 30 : 0;
    final pre = (start > 0 ? '…' : '') + text.substring(start, i);
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: pre),
        TextSpan(text: text.substring(i, i + query.length), style: const TextStyle(color: OlfaColors.primary, fontWeight: FontWeight.w700)),
        TextSpan(text: text.substring(i + query.length)),
      ]),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
