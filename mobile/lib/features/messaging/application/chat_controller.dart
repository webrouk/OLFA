import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../shared/models/models.dart';
import '../data/messaging_repository_impl.dart';

class ChatState {
  const ChatState({this.messages = const [], this.hasMore = true, this.loadingMore = false, this.peerTyping = false});
  final List<ChatMessage> messages; // oldest → newest
  final bool hasMore;
  final bool loadingMore;
  final bool peerTyping;

  ChatState copyWith({List<ChatMessage>? messages, bool? hasMore, bool? loadingMore, bool? peerTyping}) => ChatState(
        messages: messages ?? this.messages,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        peerTyping: peerTyping ?? this.peerTyping,
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

class ChatController extends FamilyAsyncNotifier<ChatState, String> {
  StreamSubscription<dynamic>? _sub;

  @override
  Future<ChatState> build(String conversationId) async {
    final repo = ref.watch(messagingRepositoryProvider);
    _sub = repo.events().where((e) => e.conversationId == conversationId).listen((e) {
      final s = state.valueOrNull;
      if (s == null) return;
      if (e.typing != null) state = AsyncData(s.copyWith(peerTyping: e.typing));
      if (e.readClientId != null) {
        state = AsyncData(s.copyWith(
          messages: [
            for (final m in s.messages)
              (m.fromMe && (e.readClientId == '*' || m.clientId == e.readClientId)) ? m.copyWith(status: MessageStatus.read) : m,
          ],
        ));
      }
      final msg = e.message;
      if (msg != null && !s.messages.any((m) => m.clientId == msg.clientId)) {
        state = AsyncData(s.copyWith(messages: [...s.messages, msg], peerTyping: false));
      }
    });
    ref.onDispose(() {
      _sub?.cancel();
      _stopTyping();
    });
    final page = await repo.page(conversationId);
    return ChatState(messages: page.items, hasMore: page.hasMore);
  }

  Future<void> loadOlder() async {
    final s = state.valueOrNull;
    if (s == null || !s.hasMore || s.loadingMore || s.messages.isEmpty) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final page = await ref.read(messagingRepositoryProvider).page(arg, before: s.messages.first.sentAt);
      final cur = state.valueOrNull!;
      state = AsyncData(cur.copyWith(messages: [...page.items, ...cur.messages], hasMore: page.hasMore, loadingMore: false));
    } on Failure {
      state = AsyncData(state.valueOrNull!.copyWith(loadingMore: false));
    }
  }

  /// Media of failed messages, kept so "retry" can resend the same files.
  final _pendingMedia = <String, OutgoingMedia>{};
  Timer? _typingOff;
  bool _typing = false;

  /// Called on every keystroke: tells the other person "typing…" and stops
  /// after 3 s without input (or when the field is cleared / sent).
  void onInput(String text) {
    final repo = ref.read(messagingRepositoryProvider);
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
    if (_typing) ref.read(messagingRepositoryProvider).setTyping(arg, false);
    _typing = false;
  }

  /// Optimistic send with an idempotency key; failed messages can be retried.
  /// Returns the failure (e.g. voice-note quota) so the screen can explain it.
  Future<Failure?> send(String body, {String? retryClientId, OutgoingMedia? media}) async {
    final text = body.trim();
    final s = state.valueOrNull;
    final m = media ?? (retryClientId == null ? null : _pendingMedia[retryClientId]);
    if (s == null || (text.isEmpty && m == null)) return null;
    _stopTyping();
    final clientId = retryClientId ?? newClientId();
    final pending = ChatMessage(
      id: 'local-$clientId',
      clientId: clientId,
      conversationId: arg,
      fromMe: true,
      body: text,
      sentAt: DateTime.now(),
      status: MessageStatus.sending,
      kind: m == null ? MessageKind.text : (m.isVoice ? MessageKind.voice : MessageKind.image),
      attachments: m == null
          ? const []
          : m.isVoice
              ? [ChatAttachment(kind: MessageKind.voice, localPath: m.voice!.path, durationMs: m.voice!.durationMs, waveform: m.voice!.waveform)]
              : [for (final f in m.files) ChatAttachment(kind: MessageKind.image, localPath: f.path, width: f.width, height: f.height)],
    );
    final without = s.messages.where((x) => x.clientId != clientId).toList();
    state = AsyncData(s.copyWith(messages: [...without, pending]));
    try {
      final saved = await ref.read(messagingRepositoryProvider).send(arg, clientId, text, media: m);
      _pendingMedia.remove(clientId);
      // keep the local file preview until the signed URL is used
      _replace(clientId, saved.attachments.isEmpty || saved.attachments.first.url != null ? saved : saved.copyWith(attachments: pending.attachments));
      if (m?.isVoice ?? false) ref.invalidate(voiceQuotaProvider(arg));
      return null;
    } on Failure catch (e) {
      if (m != null) _pendingMedia[clientId] = m;
      // A quota refusal is not retryable: drop the bubble and let the screen explain.
      if (e is QuotaExceededFailure) {
        final cur = state.valueOrNull;
        if (cur != null) state = AsyncData(cur.copyWith(messages: cur.messages.where((x) => x.clientId != clientId).toList()));
      } else {
        _replace(clientId, pending.copyWith(status: MessageStatus.failed));
      }
      return e;
    }
  }

  void _replace(String clientId, ChatMessage m) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncData(cur.copyWith(messages: [for (final x in cur.messages) x.clientId == clientId ? m : x]));
  }
}

final chatControllerProvider = AsyncNotifierProvider.family<ChatController, ChatState, String>(ChatController.new);

/// Voice notes left in a conversation (Free 10 · Plus 30 · Premium unlimited).
final voiceQuotaProvider = FutureProvider.autoDispose.family<({int limit, int? remaining}), String>(
  (ref, id) => ref.watch(messagingRepositoryProvider).voiceQuota(id),
);

/// Instant search results for the Messages page (debounced by the field).
final chatSearchProvider = FutureProvider.autoDispose.family<ChatSearchResult, String>((ref, q) async {
  if (q.trim().length < 2) return ChatSearchResult.empty;
  return ref.watch(messagingRepositoryProvider).search(q.trim());
});
