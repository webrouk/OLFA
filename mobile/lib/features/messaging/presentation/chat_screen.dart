import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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

/// 19 — Private chat: realtime, paginated, optimistic, keyboard-aware.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // reverse: true → offset 0 is the newest message.
      final far = _scroll.offset > 400;
      if (far != _showJump) setState(() => _showJump = far);
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        ref.read(chatControllerProvider(widget.conversationId).notifier).loadOlder();
      }
    });
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: motion(context, const Duration(milliseconds: 250)), curve: Curves.easeOut);
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider(widget.conversationId).notifier).send(text);
    _jumpToLatest();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final conv = ref.watch(conversationProvider(widget.conversationId)).valueOrNull;
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
                onTap: conv.peer == null ? null : () => context.push(Routes.profile(conv.peer!.id)),
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
                        if (conv.peer?.photosReviewed ?? false) ...[const SizedBox(width: 6), VerifiedBadge(size: 16, semanticLabel: l.photosReviewed)],
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
          if (conv != null && !conv.isConsultation)
            OlfaIconButton(icon: Icons.more_horiz_rounded, tooltip: l.conversationMenu, onPressed: () => showConversationMenu(context, ref, conv)),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (!online) OfflineBar(text: l.offlineChat),
          if (conv != null && conv.expiringSoon && conv.expiresAt != null)
            _ExpiryBanner(days: conv.expiresAt!.difference(DateTime.now()).inDays.clamp(0, 99).toInt()),
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
                        return Column(children: [
                          if (newDay) _SystemPill(text: DateFormat.yMMMd(Localizations.localeOf(context).languageCode).format(m.sentAt)),
                          _Bubble(
                            message: m,
                            onRetry: m.status == MessageStatus.failed
                                ? () => ref.read(chatControllerProvider(widget.conversationId).notifier).send(m.body, retryClientId: m.clientId)
                                : null,
                          ),
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
          if (conv != null && conv.isUnmatched) _UnmatchedPanel(conversation: conv) else _composer(context, l),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context, AppLocalizations l) {
    return DecoratedBox(
            decoration: const BoxDecoration(color: OlfaColors.white, border: Border(top: BorderSide(color: OlfaColors.gray))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  // Attachments are disabled by policy for now (AppSettings.chat.attachments).
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: l.messageHint,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        border: OutlineInputBorder(borderRadius: OlfaRadius.all(24), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: OlfaRadius.all(24), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: OlfaRadius.all(24), borderSide: const BorderSide(color: OlfaColors.primary, width: 1.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // arrow_forward mirrors automatically in RTL.
                  OlfaIconButton(
                    icon: Icons.arrow_forward_rounded,
                    tooltip: l.send,
                    style: OlfaIconStyle.filled,
                    circle: true,
                    size: 48,
                    onPressed: _input.text.trim().isEmpty ? null : _send,
                  ),
                ]),
              ),
            ),
          );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.onRetry});
  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final me = message.fromMe;
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    final fg = me ? OlfaColors.white : OlfaColors.black;
    const r = Radius.circular(20);
    const tail = Radius.circular(6);
    final statusIcon = switch (message.status) {
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
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                decoration: BoxDecoration(
                  color: me ? OlfaColors.primary : OlfaColors.gray,
                  borderRadius: BorderRadiusDirectional.only(topStart: r, topEnd: r, bottomStart: me ? r : tail, bottomEnd: me ? tail : r),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, child: Text(message.body, style: context.type.bodyMedium.copyWith(color: fg))),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(DateFormat.Hm().format(message.sentAt), style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.75), fontFamily: 'Montserrat')),
                    if (me) ...[
                      const SizedBox(width: 4),
                      Semantics(
                        label: message.status.name,
                        child: Icon(statusIcon, size: 14, color: message.status == MessageStatus.read ? OlfaColors.white : fg.withValues(alpha: 0.7)),
                      ),
                    ],
                  ]),
                ]),
              ),
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
