import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/bidi_text.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../settings/presentation/report_sheet.dart';
import '../application/chat_controller.dart';
import '../data/messaging_repository_impl.dart';
import '../../../core/errors/failure.dart';
import 'conversations_screen.dart' show OfflineBar, showConversationMenu;
import '../../../shared/components/verification_ticks.dart';
import 'chat_widgets.dart';
import 'compat_widgets.dart';
import 'package:flutter/services.dart';

import '../../../core/routing/navigation.dart';

/// 19 — Private chat: realtime, paginated, optimistic, keyboard-aware.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // reverse: true → offset 0 is the newest message.
      final far = _scroll.offset > 400;
      if (far != _showJump) setState(() => _showJump = far);
      // back at the newest messages: drop pages scrolled through long ago (memory stays flat)
      if (_scroll.offset < 80) ref.read(chatControllerProvider(widget.conversationId).notifier).trimToRecent();
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        ref.read(chatControllerProvider(widget.conversationId).notifier).loadOlder();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: motion(context, const Duration(milliseconds: 250)), curve: Curves.easeOut);
  }

  /// Long-press a message: copy, or report a message from the other person.
  Future<void> _messageMenu(ChatMessage m, Conversation? conv) async {
    final l = AppLocalizations.of(context);
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TileGroup(children: [
            if (m.body.isNotEmpty)
              OlfaListTile(
                icon: Icons.copy_rounded,
                title: l.copy,
                showChevron: false,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.body));
                  Navigator.of(sheet).pop();
                  showToast(context, l.copied);
                },
              ),
            // still on this phone (waiting / failed): it can be removed before it is sent
            if (m.fromMe && (m.status == MessageStatus.queued || m.status == MessageStatus.failed))
              OlfaListTile(
                icon: Icons.delete_outline_rounded,
                title: l.deleteUnsent,
                danger: true,
                showChevron: false,
                onTap: () {
                  Navigator.of(sheet).pop();
                  ref.read(chatControllerProvider(widget.conversationId).notifier).discard(m.clientId);
                },
              ),
            if (!m.fromMe && conv?.peer != null)
              OlfaListTile(
                icon: Icons.flag_outlined,
                title: l.reportMessage,
                danger: true,
                showChevron: false,
                onTap: () {
                  Navigator.of(sheet).pop();
                  showReportSheet(context, ref, conv!.peer!, message: m);
                },
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    // The row the member tapped already has the name, photo and state: show them
    // at once; the full conversation replaces it when it arrives.
    final conv = ref.watch(conversationProvider(widget.conversationId)).valueOrNull ??
        ref.watch(conversationIndexProvider.select((v) => v.valueOrNull?.visible.where((c) => c.id == widget.conversationId).firstOrNull));
    final chat = ref.watch(chatControllerProvider(widget.conversationId));
    final online = ref.watch(connectionProvider);
    final typing = chat.valueOrNull?.peerTyping ?? false;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        shape: const Border(bottom: BorderSide(color: OlfaColors.gray)),
        title: conv == null
            ? const OlfaSkeleton(width: 120, height: 14)
            : InkWell(
                onTap: conv.peer == null ? null : () => context.pushOnce(Routes.profile(conv.peer!.id), extra: conv.peer),
                child: Row(children: [
                  if (conv.peer != null)
                    OlfaAvatar(size: 40, url: conv.peer!.mainPhoto?.thumbUrl, online: conv.peer!.online && conv.canWrite)
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: OlfaColors.primaryTint(), shape: BoxShape.circle),
                      child: const Icon(Icons.support_agent_rounded, color: OlfaColors.primary, size: 20),
                    ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(conv.title, overflow: TextOverflow.ellipsis, style: t.bodyLarge.copyWith(fontWeight: FontWeight.w700))),
                        if (conv.peer != null) ...[const SizedBox(width: 6), VerificationMark(profile: conv.peer!, size: 15)],
                      ]),
                      Text(
                        conv.isUnmatched
                            ? l.screenUnmatched
                            : typing
                                ? l.typing
                                : conv.isConsultation
                                    ? l.consultationTag
                                    : ((conv.peer?.online ?? false) ? l.onlineNow : l.matchedRecently),
                        style: t.caption.copyWith(color: typing ? OlfaColors.primary : null),
                      ),
                    ]),
                  ),
                ]),
              ),
        actions: [
          if (conv != null && conv.isConsultation && conv.peer != null)
            OlfaIconButton(icon: Icons.more_horiz_rounded, tooltip: l.reportOrBlock, onPressed: () => showReportSheet(context, ref, conv.peer!)),
          if (conv != null && !conv.isConsultation && conv.canWrite) _CompatAction(conversationId: widget.conversationId, peerName: conv.title),
          if (conv != null && !conv.isConsultation)
            OlfaIconButton(icon: Icons.more_horiz_rounded, tooltip: l.conversationMenu, onPressed: () => showConversationMenu(context, ref, conv)),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (!online) OfflineBar(text: l.offlineChat),
          if (conv != null && !conv.isConsultation && conv.expiringSoon && conv.expiresAt != null)
            _ExpiryBanner(days: daysUntil(conv.expiresAt!).clamp(0, 99).toInt()),
          // ended consultation: when the chat is deleted for both (a new message moves the date)
          if (conv != null && conv.isConsultation && chat.valueOrNull?.deletesAt != null)
            _RetentionBanner(at: chat.valueOrNull!.deletesAt!, retentionDays: chat.valueOrNull!.retentionDays),
          if (conv != null && !conv.isConsultation && conv.canWrite) CompatStrip(conversationId: widget.conversationId, peerName: conv.title),
          Expanded(
            child: Stack(
              children: [
                chat.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator(color: OlfaColors.primary)),
                  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(chatControllerProvider(widget.conversationId))),
                  data: (s) {
                    final items = s.messages.reversed.toList();
                    return ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: items.length + (typing ? 1 : 0) + 1,
                      itemBuilder: (context, i) {
                        if (typing && i == 0) return const _TypingBubble();
                        final idx = i - (typing ? 1 : 0);
                        if (idx == items.length) {
                          return s.loadingMore
                              ? const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: OlfaColors.primary))))
                              : (s.hasMore ? const SizedBox(height: 24) : _SystemPill(text: (conv?.isConsultation ?? false) ? l.consultationChatNote : l.matchedSayHello));
                        }
                        final m = items[idx];
                        final older = idx + 1 < items.length ? items[idx + 1] : null;
                        final newDay = older == null || !DateUtils.isSameDay(older.sentAt, m.sentAt);
                        // the compatibility result: its own card in the middle, not a bubble
                        if (m.kind == MessageKind.compat) {
                          return Column(key: ValueKey(m.clientId), children: [
                            if (newDay) _SystemPill(text: DateFormat.yMMMd(Localizations.localeOf(context).languageCode).format(m.sentAt)),
                            if (m.compat != null) CompatResultCard(result: m.compat!),
                          ]);
                        }
                        return Column(
                          key: ValueKey(m.clientId), // stable rows: no re-layout jumps when messages arrive
                          children: [
                          if (newDay) _SystemPill(text: DateFormat.yMMMd(Localizations.localeOf(context).languageCode).format(m.sentAt)),
                          _Bubble(
                            message: m,
                            onLongPress: () => _messageMenu(m, conv),
                            onRetry: m.status == MessageStatus.failed
                                ? () => ref.read(chatControllerProvider(widget.conversationId).notifier).send(m.body, retryClientId: m.clientId)
                                : null,
                          ),
                          if (m.containsPhone)
                            Align(alignment: m.fromMe ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart, child: PhoneSafetyNote(mine: m.fromMe)),
                        ]);
                      },
                    );
                  },
                ),
                if (_showJump)
                  PositionedDirectional(
                    bottom: 12,
                    end: 12,
                    child: OlfaIconButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: l.jumpToLatest, style: OlfaIconStyle.elevated, circle: true, onPressed: _jumpToLatest),
                  ),
              ],
            ),
          ),
          // Unmatched: messaging stops; one re-match request per conversation.
          if (conv != null && conv.isUnmatched) _UnmatchedPanel(conversation: conv) else ChatComposer(conversationId: widget.conversationId, peerName: conv?.title, onSent: _jumpToLatest),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.onRetry, this.onLongPress});
  final ChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final me = message.fromMe;
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    final fg = me ? OlfaColors.white : OlfaColors.black;
    const r = Radius.circular(20);
    const tail = Radius.circular(6);
    final statusIcon = switch (message.status) {
      MessageStatus.queued => Icons.cloud_off_rounded, // waiting for the connection, sent by itself
      MessageStatus.sending => Icons.schedule_rounded,
      MessageStatus.sent => Icons.check_rounded,
      MessageStatus.delivered => Icons.done_all_rounded,
      MessageStatus.read => Icons.done_all_rounded,
      MessageStatus.failed => Icons.error_outline_rounded,
    };
    return Align(
      alignment: me ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: onLongPress,
              child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Container(
                padding: message.kind == MessageKind.image ? const EdgeInsets.fromLTRB(4, 4, 4, 6) : const EdgeInsets.fromLTRB(14, 10, 14, 6),
                decoration: BoxDecoration(
                  color: me ? OlfaColors.primary : OlfaColors.gray,
                  borderRadius: BorderRadiusDirectional.only(topStart: r, topEnd: r, bottomStart: me ? r : tail, bottomEnd: me ? tail : r),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  if (message.kind == MessageKind.image && message.attachments.isNotEmpty) PhotoGrid(items: message.attachments, maxWidth: maxW - 8),
                  if (message.kind == MessageKind.voice && message.attachments.isNotEmpty) VoiceBubble(attachment: message.attachments.first, mine: me),
                  if (message.body.isNotEmpty)
                    Padding(
                      padding: message.kind == MessageKind.image ? const EdgeInsets.fromLTRB(10, 6, 10, 0) : EdgeInsets.zero,
                      child: Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, child: Text(isolateNumbers(message.body), style: context.type.bodyMedium.copyWith(color: fg))),
                    ),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(DateFormat.Hm().format(message.sentAt), style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.75), fontFamily: 'Montserrat')),
                    if (me) ...[
                      const SizedBox(width: 4),
                      Semantics(
                        label: switch (message.status) {
                          MessageStatus.queued => l.msgQueued,
                          MessageStatus.sending => l.sending,
                          MessageStatus.sent => l.msgSent,
                          MessageStatus.delivered => l.msgDelivered,
                          MessageStatus.read => l.msgRead,
                          MessageStatus.failed => l.notSentRetry,
                        },
                        child: Icon(statusIcon, size: 14, color: message.status == MessageStatus.read ? OlfaColors.white : fg.withValues(alpha: 0.7)),
                      ),
                    ],
                  ]),
                ]),
              ),
            ),
            ),
            if (me && message.status == MessageStatus.queued)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(l.msgQueuedNote, style: context.type.caption),
              ),
            if (onRetry != null)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(l.notSentRetry),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
          ],
        ),
      ),
    );
  }
}

class _SystemPill extends StatelessWidget {
  const _SystemPill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(12)),
          child: Text(text, style: context.type.caption),
        ),
      );
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(20)),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = ((_c.value * 3) - i).clamp(0.0, 1.0).toDouble();
              final double o = reduceMotion(context) ? 0.6 : 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0).toDouble();
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: OlfaColors.black.withValues(alpha: o * 0.5), shape: BoxShape.circle),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// App-bar entry to the compatibility questions; a dot when the other person
/// finished and I haven't.
class _CompatAction extends ConsumerWidget {
  const _CompatAction({required this.conversationId, required this.peerName});
  final String conversationId;
  final String peerName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(compatControllerProvider(conversationId)).valueOrNull;
    if (s != null && !s.enabled) return const SizedBox.shrink();
    final nudge = s != null && s.peerCompleted && !s.iCompleted && s.status != CompatStatus.result;
    return Stack(clipBehavior: Clip.none, children: [
      OlfaIconButton(icon: Icons.join_inner_rounded, tooltip: l.compatShort, onPressed: () => showCompatSheet(context, conversationId: conversationId, peerName: peerName)),
      if (nudge)
        PositionedDirectional(
          top: 10,
          end: 10,
          child: Container(width: 9, height: 9, decoration: BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle, border: Border.all(color: OlfaColors.white, width: 1.5))),
        ),
    ]);
  }
}

/// Ended consultation: the date it is deleted for both people, and that a new
/// message restarts the count.
class _RetentionBanner extends StatelessWidget {
  const _RetentionBanner({required this.at, required this.retentionDays});
  final DateTime at;
  final int retentionDays;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final days = daysUntil(at);
    final date = DateFormat.yMMMd(Localizations.localeOf(context).languageCode).format(at);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: days <= 3 ? OlfaColors.primaryTint() : OlfaColors.gray.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.auto_delete_outlined, size: 18, color: days <= 3 ? OlfaColors.primary : OlfaColors.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(l.consultDeletesBanner(days, date, retentionDays), style: context.type.bodySmall)),
        ]),
      ),
    );
  }
}

class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner({required this.days});
  final int days;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: OlfaColors.primaryTint(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          const Icon(Icons.schedule_rounded, size: 17, color: OlfaColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(AppLocalizations.of(context).expiresInDays(days), style: context.type.bodySmall)),
        ]),
      );
}

/// Replaces the composer after an unmatch.
class _UnmatchedPanel extends ConsumerStatefulWidget {
  const _UnmatchedPanel({required this.conversation});
  final Conversation conversation;
  @override
  ConsumerState<_UnmatchedPanel> createState() => _UnmatchedPanelState();
}

class _UnmatchedPanelState extends ConsumerState<_UnmatchedPanel> {
  bool _busy = false;

  Future<void> _do(Future<void> Function() op, String done) async {
    setState(() => _busy = true);
    try {
      await op();
      if (mounted) showToast(context, done);
    } on Failure catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.conversation;
    final actions = ref.read(conversationActionsProvider);
    final rm = c.rematch;
    final text = switch (rm?.status) {
      RematchStatus.pending => rm!.byMe ? l.rematchWaiting(c.title) : l.rematchIncoming(c.title),
      RematchStatus.declined || RematchStatus.accepted => rm!.status == RematchStatus.declined ? l.rematchDeclined : l.rematchAlreadyUsed,
      null => l.chatClosedUnmatched,
    };
    return DecoratedBox(
      decoration: const BoxDecoration(color: OlfaColors.white, border: Border(top: BorderSide(color: OlfaColors.gray))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.link_off_rounded, size: 19, color: OlfaColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: context.type.bodySmall)),
            ]),
            const SizedBox(height: 10),
            if (c.canRequestRematch) ...[
              PrimaryButton(label: l.rematchRequest, loading: _busy, onPressed: _busy ? null : () => _do(() => actions.requestRematch(c.id), l.rematchSent)),
              const SizedBox(height: 4),
              Text(l.rematchRequestBody, textAlign: TextAlign.center, style: context.type.caption),
            ] else if (c.canAnswerRematch)
              Row(children: [
                Expanded(child: SecondaryButton(label: l.rematchDecline, onPressed: _busy ? null : () => _do(() => actions.respondRematch(c.id, accept: false), l.rematchDeclined))),
                const SizedBox(width: 10),
                Expanded(child: PrimaryButton(label: l.rematchAccept, loading: _busy, onPressed: _busy ? null : () => _do(() => actions.respondRematch(c.id, accept: true), l.rematchAccepted))),
              ])
            else
              Center(child: OlfaTag(rm?.status == RematchStatus.pending ? l.rematchPendingTag : l.rematchUsedTag, icon: Icons.hourglass_empty_rounded)),
          ]),
        ),
      ),
    );
  }
}
