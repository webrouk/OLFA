import '../../../shared/models/models.dart';

abstract interface class MessagingRepository {
  Future<List<Conversation>> conversations();
  Future<Conversation> conversation(String id);
  Future<({List<ChatMessage> items, bool hasMore})> page(String conversationId, {DateTime? before});

  /// Idempotent on [clientId]: retrying never duplicates a message.
  Future<ChatMessage> send(String conversationId, String clientId, String body);

  /// Realtime events (WebSocket in production).
  Stream<ChatEvent> events();
}
