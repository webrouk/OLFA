import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/network/api_client.dart';
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
  }

  @override
  Future<List<Conversation>> conversations() => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/conversations');
        return r.data!.where((x) => (x as Map)['peer'] != null).map((x) {
          final j = Map<String, dynamic>.from(x as Map);
          final last = j['lastMessage'] as Map?;
          return Conversation(
            id: j['id'] as String,
            peer: ApiMappers.profile(Map<String, dynamic>.from(j['peer'] as Map)),
            lastMessage: last?['body'] as String?,
            lastAt: j['lastMessageAt'] == null ? null : DateTime.parse(j['lastMessageAt'] as String).toLocal(),
            unread: (j['unread'] as num).toInt(),
          );
        }).toList();
      });

  @override
  Future<Conversation> conversation(String id) async {
    final all = await conversations();
    return all.firstWhere((c) => c.id == id);
  }

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
  Future<List<Conversation>> conversations() => _b.conversations();
  @override
  Future<Conversation> conversation(String id) => _b.conversation(id);
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

final conversationsProvider = FutureProvider<List<Conversation>>((ref) => ref.watch(messagingRepositoryProvider).conversations());

final conversationProvider = FutureProvider.family<Conversation, String>((ref, id) => ref.watch(messagingRepositoryProvider).conversation(id));
