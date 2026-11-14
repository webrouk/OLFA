import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/network/api_client.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/api_errors.dart';
import '../../../core/security/secure_store.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/messaging_repository.dart';

/// REST for history and sending (idempotent), Socket.IO `/chat` for realtime
/// events (new messages, typing, read receipts).
class ApiMessagingRepository implements MessagingRepository {
  ApiMessagingRepository(this._api, this._store, this._onConnection);
  final ApiClient _api;
  final SecureStore _store;
  final void Function(bool online) _onConnection;
  final _events = StreamController<ChatEvent>.broadcast();
  io.Socket? _socket;
  String? _myId;

  Future<String> _me() async => _myId ??= ((await _api.dio.get<Map<String, dynamic>>('/me')).data!['id'] as String);

  Future<void> _connect() async {
    if (_socket != null) return;
    final token = await _store.readAccessToken();
    final s = io.io('$apiBaseUrl/chat', io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token}).enableReconnection().build());
    _socket = s;
    s.onConnect((_) => _onConnection(true));
    s.onDisconnect((_) => _onConnection(false));
    s.on('message:new', (data) async {
      final m = Map<String, dynamic>.from(data as Map);
      final convId = m['conversationId'] as String;
      _events.add(ChatEvent.newMessage(ApiMappers.message(Map<String, dynamic>.from(m['message'] as Map), convId, await _me())));
    });
    s.on('typing', (data) {
      final m = Map<String, dynamic>.from(data as Map);
      _events.add(ChatEvent.typingChanged(m['conversationId'] as String, m['on'] == true));
    });
    s.on('message:read', (data) {
      final m = Map<String, dynamic>.from(data as Map);
      // Read receipts apply to all my messages in the conversation up to `at`.
      _events.add(ChatEvent.readReceipt(m['conversationId'] as String, '*'));
    });
    s.on('conversation:moved', (data) {
      final m = Map<String, dynamic>.from(data as Map);
      _events.add(ChatEvent.moved(m['conversationId'] as String, fromApiEnum(ConversationSection.values, m['section'], ConversationSection.inbox)));
    });
  }

  @override
  Future<ConversationIndex> index() => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/conversations');
        final ent = await _api.dio.get<Map<String, dynamic>>('/me/entitlements');
        final limit = ((ent.data!['features'] as Map?)?['visibleConversations'] as num?)?.toInt() ?? 5;
        final visible = <Conversation>[], locked = <LockedConversation>[];
        for (final x in r.data!) {
          final j = Map<String, dynamic>.from(x as Map);
          final section = fromApiEnum(ConversationSection.values, j['section'], ConversationSection.inbox);
          if (j['locked'] == true) {
            locked.add(LockedConversation(id: j['id'] as String, section: section));
          } else if (j['peer'] != null || j['consultation'] != null) {
            visible.add(ApiMappers.conversation(j));
          }
        }
        return ConversationIndex(visible: visible, locked: locked, visibleLimit: limit);
      });

  @override
  Future<Conversation> conversation(String id) async {
    final ix = await index();
    if (ix.locked.any((c) => c.id == id)) throw const EntitlementRequiredFailure('visibleConversations');
    return ix.visible.firstWhere((c) => c.id == id, orElse: () => throw const ServerFailure('not_found'));
  }

  Future<void> _post(String path, [Object? body]) => guard(() => _api.dio.post<void>(path, data: body));

  @override
  Future<void> archive(String conversationId) => _post('/conversations/$conversationId/archive');
  @override
  Future<void> restore(String conversationId) => _post('/conversations/$conversationId/restore');
  @override
  Future<void> unmatch(String conversationId) => _post('/conversations/$conversationId/unmatch');
  @override
  Future<void> requestRematch(String conversationId) => _post('/conversations/$conversationId/rematch');
  @override
  Future<void> respondRematch(String conversationId, {required bool accept}) => _post('/conversations/$conversationId/rematch/respond', {'accept': accept});

  @override
  Future<({List<ChatMessage> items, bool hasMore})> page(String conversationId, {DateTime? before}) => guard(() async {
        unawaited(_connect());
        final me = await _me();
        final r = await _api.dio.get<Map<String, dynamic>>('/conversations/$conversationId/messages', queryParameters: {
          if (before != null) 'before': before.toUtc().toIso8601String(),
        });
        final items = (r.data!['items'] as List).map((j) => ApiMappers.message(Map<String, dynamic>.from(j as Map), conversationId, me)).toList();
        // Opening the thread marks it read.
        unawaited(_api.dio.post<void>('/conversations/$conversationId/read').catchError((_) => null));
        return (items: items, hasMore: r.data!['hasMore'] as bool);
      });

  @override
  Future<ChatMessage> send(String conversationId, String clientId, String body) => guard(() async {
        final r = await _api.dio.post<Map<String, dynamic>>('/conversations/$conversationId/messages', data: {'clientMessageId': clientId, 'body': body});
        final j = Map<String, dynamic>.from(r.data!)..putIfAbsent('receipts', () => const []);
        return ApiMappers.message(j, conversationId, await _me());
      }, quota: 'messages');

  @override
  Stream<ChatEvent> events() {
    unawaited(_connect());
    return _events.stream;
  }

  void sendTyping(String conversationId, bool on) => _socket?.emit('typing', {'conversationId': conversationId, 'on': on});

  void dispose() {
    _socket?.dispose();
    _events.close();
  }
}

class DemoMessagingRepository implements MessagingRepository {
  DemoMessagingRepository(this._b);
  final DemoBackend _b;

  @override
  Future<ConversationIndex> index() => _b.conversationIndex();
  @override
  Future<Conversation> conversation(String id) => _b.conversation(id);
  @override
  Future<void> archive(String conversationId) => _b.setFolder(conversationId, ConversationSection.archive);
  @override
  Future<void> restore(String conversationId) => _b.setFolder(conversationId, ConversationSection.inbox);
  @override
  Future<void> unmatch(String conversationId) => _b.unmatch(conversationId);
  @override
  Future<void> requestRematch(String conversationId) => _b.requestRematch(conversationId);
  @override
  Future<void> respondRematch(String conversationId, {required bool accept}) => _b.respondRematch(conversationId, accept);
  @override
  Future<({List<ChatMessage> items, bool hasMore})> page(String conversationId, {DateTime? before}) => _b.messages(conversationId, before: before);
  @override
  Future<ChatMessage> send(String conversationId, String clientId, String body) => _b.send(conversationId, clientId, body);
  @override
  Stream<ChatEvent> events() => _b.events;
}

/// Realtime connection state (drives the offline banner). In demo mode it can
/// be toggled from Privacy & Security to preview the offline UI.
class ConnectionController extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool online) {
    if (!useApi) ref.read(demoBackendProvider).online = online;
    state = online;
  }
}

final connectionProvider = NotifierProvider<ConnectionController, bool>(ConnectionController.new);

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  if (!useApi) return DemoMessagingRepository(ref.watch(demoBackendProvider));
  final repo = ApiMessagingRepository(ref.watch(apiClientProvider), ref.watch(secureStoreProvider), (on) => ref.read(connectionProvider.notifier).set(on));
  ref.onDispose(repo.dispose);
  return repo;
});

/// Re-fetched whenever a conversation moves between sections (socket event).
final conversationIndexProvider = FutureProvider<ConversationIndex>((ref) {
  final repo = ref.watch(messagingRepositoryProvider);
  final sub = repo.events().where((e) => e.movedTo != null).listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return repo.index();
});

final conversationProvider = FutureProvider.family<Conversation, String>((ref, id) {
  final repo = ref.watch(messagingRepositoryProvider);
  final sub = repo.events().where((e) => e.conversationId == id && e.movedTo != null).listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return repo.conversation(id);
});

/// Archive / restore / unmatch / re-match, refreshing the lists afterwards.
class ConversationActions {
  ConversationActions(this._ref);
  final Ref _ref;
  MessagingRepository get _repo => _ref.read(messagingRepositoryProvider);

  Future<void> _run(String id, Future<void> Function() op) async {
    await op();
    _ref
      ..invalidate(conversationIndexProvider)
      ..invalidate(conversationProvider(id));
  }

  Future<void> archive(String id) => _run(id, () => _repo.archive(id));
  Future<void> restore(String id) => _run(id, () => _repo.restore(id));
  Future<void> unmatch(String id) => _run(id, () => _repo.unmatch(id));
  Future<void> requestRematch(String id) => _run(id, () => _repo.requestRematch(id));
  Future<void> respondRematch(String id, {required bool accept}) => _run(id, () => _repo.respondRematch(id, accept: accept));
}

final conversationActionsProvider = Provider<ConversationActions>(ConversationActions.new);
