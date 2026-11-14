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

String newClientId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
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
          messages: [for (final m in s.messages) m.clientId == e.readClientId ? m.copyWith(status: MessageStatus.read) : m],
        ));
      }
      final msg = e.message;
      if (msg != null && !s.messages.any((m) => m.clientId == msg.clientId)) {
        state = AsyncData(s.copyWith(messages: [...s.messages, msg], peerTyping: false));
      }
    });
    ref.onDispose(() => _sub?.cancel());
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

  /// Optimistic send with an idempotency key; failed messages can be retried.
  Future<void> send(String body, {String? retryClientId}) async {
    final text = body.trim();
    final s = state.valueOrNull;
    if (s == null || text.isEmpty) return;
    final clientId = retryClientId ?? newClientId();
    final pending = ChatMessage(
      id: 'local-$clientId',
      clientId: clientId,
      conversationId: arg,
      fromMe: true,
      body: text,
      sentAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    final without = s.messages.where((m) => m.clientId != clientId).toList();
    state = AsyncData(s.copyWith(messages: [...without, pending]));
    try {
      final saved = await ref.read(messagingRepositoryProvider).send(arg, clientId, text);
      _replace(clientId, saved);
    } on Failure {
      _replace(clientId, pending.copyWith(status: MessageStatus.failed));
    }
  }

  void _replace(String clientId, ChatMessage m) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncData(cur.copyWith(messages: [for (final x in cur.messages) x.clientId == clientId ? m : x]));
  }
}

final chatControllerProvider = AsyncNotifierProvider.family<ChatController, ChatState, String>(ChatController.new);
