import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/messaging_repository.dart';

class DemoMessagingRepository implements MessagingRepository {
  DemoMessagingRepository(this._b);
  final DemoBackend _b;

  @override
  Future<List<Conversation>> conversations() => _b.conversations();

  @override
  Future<Conversation> conversation(String id) => _b.conversation(id);

  @override
  Future<({List<ChatMessage> items, bool hasMore})> page(String conversationId, {DateTime? before}) =>
      _b.messages(conversationId, before: before);

  @override
  Future<ChatMessage> send(String conversationId, String clientId, String body) => _b.send(conversationId, clientId, body);

  @override
  Stream<ChatEvent> events() => _b.events;
}

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) => DemoMessagingRepository(ref.watch(demoBackendProvider)));

final conversationsProvider = FutureProvider<List<Conversation>>((ref) => ref.watch(messagingRepositoryProvider).conversations());

final conversationProvider = FutureProvider.family<Conversation, String>((ref, id) => ref.watch(messagingRepositoryProvider).conversation(id));

/// Connection state of the realtime channel. Demo: toggled from Privacy &
/// Security ("Simulate offline") so the offline UI can be reviewed.
class ConnectionController extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool online) {
    ref.read(demoBackendProvider).online = online;
    state = online;
  }
}

final connectionProvider = NotifierProvider<ConnectionController, bool>(ConnectionController.new);
