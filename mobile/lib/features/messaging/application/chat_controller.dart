import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../shared/models/models.dart';
import '../data/messaging_repository_impl.dart';
import '../data/outbox.dart';
import '../domain/thread_order.dart';
import '../domain/messaging_repository.dart';

class ChatState {
  const ChatState({this.messages = const [], this.hasMore = true, this.loadingMore = false, this.peerTyping = false, this.deletesAt, this.retentionDays = 30});
  final List<ChatMessage> messages; // oldest → newest
  final bool hasMore;
  final bool loadingMore;
  final bool peerTyping;

  /// Ended consultation chats: deleted for both on this date (any new message moves it).
  final DateTime? deletesAt;
  final int retentionDays;

  ChatState copyWith({List<ChatMessage>? messages, bool? hasMore, bool? loadingMore, bool? peerTyping, DateTime? deletesAt}) => ChatState(
        messages: messages ?? this.messages,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        peerTyping: peerTyping ?? this.peerTyping,
        deletesAt: deletesAt ?? this.deletesAt,
        retentionDays: retentionDays,
      );
}

/// RFC 4122 v4 UUID — the server's idempotency key for messages.
String newClientId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// One open conversation. Auto-disposed when the chat screen closes, so every
/// open re-reads the server, marks the thread read and stops "typing…".
///
/// Ordering: the thread is kept sorted by the server position of each message
/// (`seq`), with messages still on the phone after them ([mergeThread]); the same
/// message never shows twice. Sync: a jump in positions (a missed event) or a
/// reconnect fetches exactly what is missing (`afterSeq`). Sending goes through the
/// persistent [Outbox], so offline messages wait on the phone and go out by themselves.
class ChatController extends AutoDisposeFamilyAsyncNotifier<ChatState, String> {
  StreamSubscription<dynamic>? _sub;
  StreamSubscription<OutboxResult>? _outSub;
  Timer? _readDebounce;
  Timer? _peerTypingOff;
  bool _catchingUp = false;
  int? _peerRead;
  int? _peerDelivered;

  /// Captured in [build]: `ref` can't be used from dispose callbacks.
  late MessagingRepository _repo;
  late Outbox _outbox;

  void _set(List<ChatMessage> messages, {bool? hasMore, bool? loadingMore, bool? peerTyping}) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    // a new message (either side) restarts an ended consultation chat's 30 days
    final grew = messages.length > cur.messages.length && cur.deletesAt != null;
    state = AsyncData(cur.copyWith(
      messages: applyPeerPositions(messages, deliveredUpTo: _peerDelivered, readUpTo: _peerRead),
      hasMore: hasMore,
      loadingMore: loadingMore,
      peerTyping: peerTyping,
      deletesAt: grew ? DateTime.now().add(Duration(days: cur.retentionDays)) : null,
    ));
  }

  @override
  Future<ChatState> build(String conversationId) async {
    final repo = _repo = ref.watch(messagingRepositoryProvider);
    final outbox = _outbox = ref.watch(outboxProvider);
    _sub = repo.events().where((e) => e.conversationId == conversationId || e.reconnected).listen(_onEvent);
    _outSub = outbox.results.where((r) => r.entry.conversationId == conversationId).listen(_onOutbox);
    // this thread is on screen: its new messages are read, not "unread" in the list
    final open = ref.read(openConversationProvider.notifier);
    Future.microtask(() => open.state = conversationId);
    ref.onDispose(() {
      _sub?.cancel();
      _outSub?.cancel();
      _readDebounce?.cancel();
      _peerTypingOff?.cancel();
      _stopTyping();
      Future.microtask(() {
        if (open.mounted && open.state == conversationId) open.state = null;
      });
    });
    final page = await repo.page(conversationId);
    _peerDelivered = page.peerDeliveredSeq;
    _peerRead = page.peerReadSeq;
    unawaited(repo.markRead(conversationId)); // opening the thread reads it
    await outbox.ready;
    final waiting = [
      for (final e in outbox.pendingFor(conversationId)) e.toBubble(status: e.failedCode != null ? MessageStatus.failed : MessageStatus.queued),
    ];
    return ChatState(
      messages: applyPeerPositions(mergeThread(page.items, waiting), deliveredUpTo: _peerDelivered, readUpTo: _peerRead),
      hasMore: page.hasMore,
      deletesAt: page.retentionExpiresAt,
      retentionDays: page.retentionDays,
    );
  }

  void _onEvent(ChatEvent e) {
    final s = state.valueOrNull;
    if (s == null) return;
    if (e.reconnected) {
      unawaited(_catchUp());
      return;
    }
    if (e.typing != null) {
      _peerTypingOff?.cancel();
      // If the "stopped typing" event is lost, the indicator still clears.
      if (e.typing!) _peerTypingOff = Timer(const Duration(seconds: 8), () => _setPeerTyping(false));
      _setPeerTyping(e.typing!);
    }
    if (e.readUpTo != null || e.deliveredUpTo != null) {
      if (e.readUpTo != null) _peerRead = e.readUpTo! > (_peerRead ?? 0) ? e.readUpTo : _peerRead;
      if (e.deliveredUpTo != null) _peerDelivered = e.deliveredUpTo! > (_peerDelivered ?? 0) ? e.deliveredUpTo : _peerDelivered;
      _set(s.messages);
    }
    if (e.readClientId != null) {
      // older servers: "read" without a position = everything I sent so far
      _set([
        for (final m in s.messages)
          (m.fromMe && !m.isPending && (e.readClientId == '*' || m.clientId == e.readClientId)) ? m.copyWith(status: MessageStatus.read) : m,
      ]);
    }
    final msg = e.message;
    if (msg != null) {
      final last = lastSeqOf(s.messages);
      // a jump means an event was missed: fetch exactly what is missing first
      if (msg.seq != null && last > 0 && msg.seq! > last + 1) {
        unawaited(_catchUp());
      }
      _peerTypingOff?.cancel();
      _set(mergeThread(s.messages, [msg]), peerTyping: msg.fromMe ? s.peerTyping : false);
      // A message arriving while the chat is open is read straight away.
      if (!msg.fromMe) _scheduleRead();
    }
  }

  void _onOutbox(OutboxResult r) {
    final s = state.valueOrNull;
    if (s == null) return;
    if (r.saved != null) {
      _set(mergeThread(s.messages, [r.saved!]));
      if (r.saved!.kind == MessageKind.voice) ref.invalidate(voiceQuotaProvider(arg));
    } else if (r.removed) {
      _set(s.messages.where((m) => m.clientId != r.entry.clientId).toList());
    } else if (r.queued) {
      _set([for (final m in s.messages) m.clientId == r.entry.clientId && m.isPending ? m.copyWith(status: MessageStatus.queued) : m]);
    } else if (r.failure != null) {
      _set([for (final m in s.messages) m.clientId == r.entry.clientId ? m.copyWith(status: MessageStatus.failed) : m]);
    }
  }

  /// Fetches everything after the last known position (after a reconnect or a gap).
  Future<void> _catchUp() async {
    if (_catchingUp) return;
    _catchingUp = true;
    try {
      var after = lastSeqOf(state.valueOrNull?.messages ?? const []);
      while (true) {
        final p = await _repo.page(arg, afterSeq: after);
        if (p.peerDeliveredSeq != null) _peerDelivered = p.peerDeliveredSeq;
        if (p.peerReadSeq != null) _peerRead = p.peerReadSeq;
        final cur = state.valueOrNull;
        if (cur == null) return;
        _set(mergeThread(cur.messages, p.items));
        final next = lastSeqOf(p.items);
        if (!p.hasMore || next <= after) break;
        after = next;
      }
      if ((state.valueOrNull?.messages ?? const []).any((m) => !m.fromMe)) _scheduleRead();
    } on Failure {
      // offline again: the next reconnect retries
    } finally {
      _catchingUp = false;
    }
  }

  void _setPeerTyping(bool on) {
    final s = state.valueOrNull;
    if (s != null && s.peerTyping != on) state = AsyncData(s.copyWith(peerTyping: on));
  }

  void _scheduleRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 600), () => _repo.markRead(arg));
  }

  /// Older messages when scrolling up (pages of 30, never the whole history).
  Future<void> loadOlder() async {
    final s = state.valueOrNull;
    if (s == null || !s.hasMore || s.loadingMore || s.messages.isEmpty) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final first = s.messages.firstWhere((m) => m.seq != null, orElse: () => s.messages.first);
      final page = await _repo.page(arg, beforeSeq: first.seq, before: first.seq == null ? first.sentAt : null);
      final cur = state.valueOrNull!;
      _set(mergeThread(page.items, cur.messages), hasMore: page.hasMore, loadingMore: false);
    } on Failure {
      state = AsyncData(state.valueOrNull!.copyWith(loadingMore: false));
    }
  }

  /// Keeps memory flat in long threads: once the person is back at the newest
  /// messages, only the latest [keep] stay loaded (older pages load again on scroll).
  void trimToRecent({int keep = 150, int above = 300}) {
    final s = state.valueOrNull;
    if (s == null || s.loadingMore || s.messages.length <= above) return;
    state = AsyncData(s.copyWith(messages: s.messages.sublist(s.messages.length - keep), hasMore: true));
  }

  Timer? _typingOff;
  bool _typing = false;

  /// Called on every keystroke: tells the other person "typing…" and stops
  /// after 3 s without input (or when the field is cleared / sent).
  void onInput(String text) {
    final repo = _repo;
    if (text.trim().isEmpty) return _stopTyping();
    if (!_typing) {
      _typing = true;
      repo.setTyping(arg, true);
    }
    _typingOff?.cancel();
    _typingOff = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingOff?.cancel();
    if (_typing) _repo.setTyping(arg, false);
    _typing = false;
  }

  /// Optimistic send through the persistent outbox (idempotency key = clientId).
  /// Offline → the bubble shows "waiting for network" and goes out by itself.
  /// Returns the failure (e.g. voice-note quota) so the screen can explain it;
  /// a [NetworkFailure] only means "queued".
  Future<Failure?> send(String body, {String? retryClientId, OutgoingMedia? media}) async {
    if (retryClientId != null) {
      final s = state.valueOrNull;
      if (s != null) _set([for (final m in s.messages) m.clientId == retryClientId ? m.copyWith(status: MessageStatus.sending) : m]);
      await _outbox.retry(retryClientId);
      return null;
    }
    final text = body.trim();
    final s = state.valueOrNull;
    if (s == null || (text.isEmpty && media == null)) return null;
    _stopTyping();
    final entry = OutboxEntry(
      clientId: newClientId(),
      conversationId: arg,
      body: text,
      createdAt: DateTime.now(),
      photos: media == null || media.isVoice ? const [] : [for (final f in media.files) (path: f.path, width: f.width, height: f.height)],
      voice: media?.voice == null ? null : (path: media!.voice!.path, durationMs: media.voice!.durationMs, waveform: media.voice!.waveform),
    );
    _set(mergeThread(s.messages, [entry.toBubble(status: ref.read(connectionProvider) ? MessageStatus.sending : MessageStatus.queued)]));
    // Leaving the chat mid-send must not drop the result: the outbox keeps it either way.
    final keep = ref.keepAlive();
    try {
      await _outbox.send(entry);
      return null;
    } on NetworkFailure catch (e) {
      return e; // queued: sent automatically when the connection returns
    } on Failure catch (e) {
      return e;
    } finally {
      keep.close();
    }
  }

  /// Removes a message that is still on the phone (failed or waiting).
  Future<void> discard(String clientId) => _outbox.discard(clientId);
}

final chatControllerProvider = AsyncNotifierProvider.autoDispose.family<ChatController, ChatState, String>(ChatController.new);

/// Voice notes left in a conversation (Free 10 · Plus 30 · Premium unlimited).
final voiceQuotaProvider = FutureProvider.autoDispose.family<({int limit, int? remaining}), String>(
  (ref, id) => ref.watch(messagingRepositoryProvider).voiceQuota(id),
);

/// Instant search results for the Messages page (debounced by the field).
final chatSearchProvider = FutureProvider.autoDispose.family<ChatSearchResult, String>((ref, q) async {
  if (q.trim().length < 2) return ChatSearchResult.empty;
  return ref.watch(messagingRepositoryProvider).search(q.trim());
});


/// The compatibility questionnaire of one chat. Stays in step with the other
/// person through realtime events; answering never reloads the conversation.
class CompatController extends AutoDisposeFamilyAsyncNotifier<CompatState, String> {
  late MessagingRepository _repo;

  @override
  Future<CompatState> build(String conversationId) async {
    _repo = ref.watch(messagingRepositoryProvider);
    final sub = _repo.events().where((e) => e.conversationId == conversationId && (e.compatChangedFlag || e.message?.kind == MessageKind.compat)).listen((_) => _refresh());
    ref.onDispose(sub.cancel);
    return _repo.compat(conversationId);
  }

  Future<void> _refresh() async {
    try {
      state = AsyncData(await _repo.compat(arg));
    } catch (_) {
      // keep what is shown; the next event or open retries
    }
  }

  Future<void> start() async {
    state = AsyncData(await _repo.startCompat(arg));
  }

  /// Optimistic: the choice shows at once; reverted if the server refuses it.
  Future<void> answer(String questionId, String optionKey) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    final wasNew = cur.questions.any((q) => q.id == questionId && q.answer == null);
    state = AsyncData(CompatState(
      status: cur.status,
      enabled: cur.enabled,
      myAnswered: cur.myAnswered + (wasNew ? 1 : 0),
      myTotal: cur.myTotal,
      peerStarted: cur.peerStarted,
      peerCompleted: cur.peerCompleted,
      result: cur.result,
      questions: [for (final q in cur.questions) q.id == questionId ? q.answered(optionKey) : q],
    ));
    try {
      state = AsyncData(await _repo.answerCompat(arg, {questionId: optionKey}));
    } catch (_) {
      state = AsyncData(cur);
      rethrow;
    }
  }
}

final compatControllerProvider = AsyncNotifierProvider.autoDispose.family<CompatController, CompatState, String>(CompatController.new);
