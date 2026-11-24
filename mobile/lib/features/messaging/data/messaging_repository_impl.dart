import 'package:dio/dio.dart';
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
    if (token == null || _socket != null) return; // not signed in yet: connect on the next call
    final s = io.io('$apiBaseUrl/chat', io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token}).enableReconnection().build());
    _socket = s;
    s.onConnect((_) => _onConnection(true));
    s.onDisconnect((_) => _onConnection(false));
    s.on('message:new', (data) async {
      try {
        final m = Map<String, dynamic>.from(data as Map);
        final convId = m['conversationId'] as String;
        final j = Map<String, dynamic>.from(m['message'] as Map)..putIfAbsent('receipts', () => const []);
        _events.add(ChatEvent.newMessage(ApiMappers.message(j, convId, await _me())));
      } catch (_) {
        // malformed event or /me unavailable: the next page load catches up
      }
    });
    s.on('typing', (data) {
      final m = Map<String, dynamic>.from(data as Map);
      _events.add(ChatEvent.typingChanged(m['conversationId'] as String, m['on'] == true));
    });
    s.on('message:read', (data) async {
      try {
        final m = Map<String, dynamic>.from(data as Map);
        final convId = m['conversationId'] as String;
        // The server also sends my own reads to my devices: those clear my unread
        // badges and must never mark my sent messages as "read".
        if (m['readerId'] == await _me()) {
          _events.add(ChatEvent.readByMeEvent(convId));
        } else {
          _events.add(ChatEvent.readReceipt(convId, '*')); // all my messages up to `at`
        }
      } catch (_) {}
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
        return (items: items, hasMore: r.data!['hasMore'] as bool);
      });

  @override
  Future<ChatMessage> send(String conversationId, String clientId, String body, {OutgoingMedia? media}) => guard(() async {
        final ids = <String>[];
        if (media != null) {
          // 1) ask for a private upload slot per file  2) upload straight to storage  3) send with the ids
          final parts = media.isVoice
              ? [(kind: 'VOICE', mime: 'audio/mp4', bytes: media.voice!.bytes, w: null, h: null, dur: media.voice!.durationMs, wave: media.voice!.waveform)]
              : [for (final f in media.files) (kind: 'IMAGE', mime: 'image/jpeg', bytes: f.bytes, w: f.width, h: f.height, dur: null, wave: const <int>[])];
          for (final p in parts) {
            final slot = await _api.dio.post<Map<String, dynamic>>('/conversations/$conversationId/attachments', data: {
              'kind': p.kind,
              'mime': p.mime,
              'bytes': p.bytes.length,
              if (p.w != null) 'width': p.w,
              if (p.h != null) 'height': p.h,
              if (p.dur != null) 'durationMs': p.dur,
              if (p.wave.isNotEmpty) 'waveform': p.wave,
            });
            final up = Map<String, dynamic>.from(slot.data!['upload'] as Map);
            await Dio().post<void>(up['url'] as String,
                data: FormData.fromMap({
                  ...Map<String, dynamic>.from(up['fields'] as Map),
                  'file': MultipartFile.fromBytes(p.bytes, filename: p.kind == 'VOICE' ? 'voice.m4a' : 'photo.jpg', contentType: DioMediaType.parse(p.mime)),
                }));
            ids.add(slot.data!['id'] as String);
          }
        }
        final r = await _api.dio.post<Map<String, dynamic>>('/conversations/$conversationId/messages', data: {
          'clientMessageId': clientId,
          if (body.trim().isNotEmpty) 'body': body,
          if (ids.isNotEmpty) 'attachmentIds': ids,
        });
        final j = Map<String, dynamic>.from(r.data!)..putIfAbsent('receipts', () => const []);
        return ApiMappers.message(j, conversationId, await _me());
      }, quota: media?.isVoice ?? false ? 'voice' : 'messages');

  @override
  Future<ChatSearchResult> search(String query) => guard(() async {
        final r = await _api.dio.get<Map<String, dynamic>>('/conversations/search', queryParameters: {'q': query});
        final me = await _me();
        return ChatSearchResult(
          conversationIds: (r.data!['conversations'] as List).cast<String>(),
          messages: (r.data!['messages'] as List).map((x) {
            final m = Map<String, dynamic>.from(x as Map);
            return ChatMessage(
              id: m['id'] as String,
              clientId: m['id'] as String,
              conversationId: m['conversationId'] as String,
              fromMe: m['fromMe'] == true || m['senderId'] == me,
              body: m['body'] as String,
              sentAt: DateTime.parse(m['createdAt'] as String).toLocal(),
              status: MessageStatus.delivered,
            );
          }).toList(),
        );
      });

  @override
  Future<({int limit, int? remaining})> voiceQuota(String conversationId) => guard(() async {
        final r = await _api.dio.get<Map<String, dynamic>>('/conversations/$conversationId/voice-quota');
        return (limit: (r.data!['limit'] as num).toInt(), remaining: (r.data!['remaining'] as num?)?.toInt());
      });

  @override
  Future<void> markRead(String conversationId) async {
    try {
      await _api.dio.post<void>('/conversations/$conversationId/read');
    } catch (_) {
      // best-effort: the next open marks it read
    }
  }

  @override
  void setTyping(String conversationId, bool on) => sendTyping(conversationId, on);

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
  Future<ChatMessage> send(String conversationId, String clientId, String body, {OutgoingMedia? media}) => _b.send(conversationId, clientId, body, media: media);
  @override
  Future<void> markRead(String conversationId) => _b.markRead(conversationId);
  @override
  void setTyping(String conversationId, bool on) {} // the demo peer types on its own
  @override
  Future<ChatSearchResult> search(String query) => _b.searchChats(query);
  @override
  Future<({int limit, int? remaining})> voiceQuota(String conversationId) => _b.voiceQuota(conversationId);
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
/// Kept fresh by realtime events: a new message (preview, order, unread),
/// my own reads (badges) and section moves. Bursts are coalesced.
final conversationIndexProvider = FutureProvider<ConversationIndex>((ref) {
  final repo = ref.watch(messagingRepositoryProvider);
  Timer? debounce;
  final sub = repo.events().where((e) => e.movedTo != null || e.message != null || e.readByMe).listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), ref.invalidateSelf);
  });
  ref.onDispose(() {
    debounce?.cancel();
    sub.cancel();
  });
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
