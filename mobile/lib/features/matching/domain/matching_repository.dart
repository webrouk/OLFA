import '../../../shared/models/models.dart';

abstract interface class MatchingRepository {
  Future<List<MatchItem>> matches();

  /// Spends one daily "conversation starter" credit unless the conversation
  /// already exists. Returns the conversation id.
  Future<String> startConversation(String matchId);

  /// Count is always returned; identities only when the plan allows it.
  Future<({int count, List<UserProfile> profiles})> likesReceived();
}
