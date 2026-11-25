import '../../../shared/models/models.dart';

abstract interface class MessagingRepository {
  /// All sections in one call; rows past the plan's limit come back locked.
  Future<ConversationIndex> index();
  Future<Conversation> conversation(String id);
  /// Newest page first (oldest → newest inside). [beforeSeq]: older page when scrolling up.
  /// [afterSeq]: catch-up after a reconnect or a gap (everything after that position).
  /// [before] is the time cursor for sources without positions (preview data).
  Future<MessagePage> page(String conversationId, {int? beforeSeq, int? afterSeq, DateTime? before});

  /// "Received up to N" for the sender's ticks (best-effort, never throws).
  void markDelivered(String conversationId, int upToSeq);

  /// Idempotent on [clientId]: retrying never duplicates a message.
  Future<ChatMessage> send(String conversationId, String clientId, String body, {OutgoingMedia? media});

  /// Marks the conversation read up to now (opening it, or a message arriving
  /// while it is open). Best-effort: never throws.
  Future<void> markRead(String conversationId);

  /// "Typing…" for the other person (best-effort, never throws).
  void setTyping(String conversationId, bool on);

  /// Names and message text from one field; only unlocked conversations.
  Future<ChatSearchResult> search(String query);

  /// Voice notes left in this conversation; remaining == null means unlimited.
  Future<({int limit, int? remaining})> voiceQuota(String conversationId);

  Future<void> archive(String conversationId);
  Future<void> restore(String conversationId);

  /// Moves the chat to Unmatched for both people immediately.
  Future<void> unmatch(String conversationId);

  /// One request per conversation, ever.
  Future<void> requestRematch(String conversationId);
  Future<void> respondRematch(String conversationId, {required bool accept});

  /// In-chat compatibility questions (match chats only).
  Future<CompatState> compat(String conversationId);
  Future<CompatState> startCompat(String conversationId);

  /// Saves answers (questionId → optionKey). When both people have answered
  /// everything, the server adds the result card to the chat.
  Future<CompatState> answerCompat(String conversationId, Map<String, String> answers);

  /// Realtime events (WebSocket in production).
  Stream<ChatEvent> events();
}
