import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/localization/locale_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../core/security/secure_store.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';

enum TicketStatus { open, pendingUser, resolved, closed }

class TicketFile {
  const TicketFile({required this.id, required this.fileName, required this.mime, required this.bytes, this.url, this.localBytes});
  final String id;
  final String fileName;
  final String mime;
  final int bytes;
  final String? url; // signed, short-lived
  final Uint8List? localBytes; // just picked (preview before upload)
  bool get isImage => mime.startsWith('image/');
}

class TicketMessage {
  const TicketMessage({required this.id, required this.fromStaff, required this.body, required this.createdAt, this.files = const [], this.sending = false, this.failed = false});
  final String id;
  final bool fromStaff;
  final String body;
  final DateTime createdAt;
  final List<TicketFile> files;
  final bool sending;
  final bool failed;
}

class SupportTicket {
  const SupportTicket({required this.id, required this.category, required this.subject, required this.status, required this.lastMessageAt, this.unread = 0, this.lastBody, this.lastFromStaff = false, this.messages = const []});
  final String id;
  final String category;
  final String subject;
  final TicketStatus status;
  final DateTime lastMessageAt;
  final int unread;
  final String? lastBody;
  final bool lastFromStaff;
  final List<TicketMessage> messages;
}

/// A file picked for a support message (image already compressed on the phone, or a PDF).
class PickedFile {
  const PickedFile({required this.name, required this.mime, required this.bytes});
  final String name;
  final String mime;
  final Uint8List bytes;
}

const kTicketFileMax = 10 * 1024 * 1024;
const kTicketFilesPerMessage = 3;

abstract interface class SupportRepository {
  Future<List<FaqEntry>> faq();
  Future<List<SupportTicket>> tickets();
  Future<SupportTicket> thread(String id);
  Future<SupportTicket> create({required String category, required String subject, required String body, List<PickedFile> files});
  Future<TicketMessage> reply(String ticketId, {required String body, List<PickedFile> files});
  Future<void> close(String ticketId);
  Future<int> unread();

  /// Staff replies as they arrive (socket); the thread also refreshes periodically.
  Stream<String> replies();
}

TicketStatus _status(Object? s) => switch (s) {
      'PENDING_USER' => TicketStatus.pendingUser,
      'RESOLVED' => TicketStatus.resolved,
      'CLOSED' => TicketStatus.closed,
      _ => TicketStatus.open,
    };

class ApiSupportRepository implements SupportRepository {
  ApiSupportRepository(this._api, this._store, this._lang);
  final ApiClient _api;
  final SecureStore _store;
  final String _lang;
  final _replies = StreamController<String>.broadcast();
  io.Socket? _socket;

  Dio get _dio => _api.dio;

  TicketMessage _msg(Map<String, dynamic> m) => TicketMessage(
        id: m['id'] as String,
        fromStaff: m['authorType'] == 'ADMIN',
        body: (m['body'] as String?) ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String).toLocal(),
        files: [
          for (final a in (m['attachments'] as List? ?? const []))
            TicketFile(id: a['id'] as String, fileName: a['fileName'] as String, mime: a['mime'] as String, bytes: (a['bytes'] as num).toInt(), url: a['url'] as String?),
        ],
      );

  SupportTicket _ticket(Map<String, dynamic> t) {
    final last = t['last'] as Map?;
    return SupportTicket(
      id: t['id'] as String,
      category: (t['category'] as String).toLowerCase(),
      subject: t['subject'] as String,
      status: _status(t['status']),
      lastMessageAt: DateTime.parse((t['lastMessageAt'] ?? t['createdAt']) as String).toLocal(),
      unread: (t['unread'] as num?)?.toInt() ?? 0,
      lastBody: last?['body'] as String?,
      lastFromStaff: last?['authorType'] == 'ADMIN',
      messages: [for (final m in (t['messages'] as List? ?? const [])) _msg(Map<String, dynamic>.from(m as Map))],
    );
  }

  Future<List<String>> _upload(List<PickedFile> files) async {
    final ids = <String>[];
    for (final f in files) {
      final r = await _dio.post<Map<String, dynamic>>('/support/attachments', data: {'fileName': f.name, 'mime': f.mime, 'bytes': f.bytes.length});
      final up = Map<String, dynamic>.from(r.data!['upload'] as Map);
      await Dio().post<void>(up['url'] as String,
          data: FormData.fromMap({...Map<String, dynamic>.from(up['fields'] as Map), 'file': MultipartFile.fromBytes(f.bytes, filename: f.name, contentType: DioMediaType.parse(f.mime))}));
      ids.add(r.data!['id'] as String);
    }
    return ids;
  }

  @override
  Future<List<FaqEntry>> faq() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/support/faq', queryParameters: {'lang': _lang}, options: Options(extra: {'auth': false}));
        return [
          for (final x in r.data!)
            FaqEntry(id: x['id'] as String, category: (x['category'] as String).toLowerCase(), question: x['question'] as String, answer: x['answer'] as String),
        ];
      });

  @override
  Future<List<SupportTicket>> tickets() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/support/tickets');
        return [for (final t in r.data!) _ticket(Map<String, dynamic>.from(t as Map))];
      });

  @override
  Future<SupportTicket> thread(String id) => guard(() async {
        unawaited(_connect());
        final r = await _dio.get<Map<String, dynamic>>('/support/tickets/$id');
        return _ticket(r.data!);
      });

  @override
  Future<SupportTicket> create({required String category, required String subject, required String body, List<PickedFile> files = const []}) => guard(() async {
        final ids = await _upload(files);
        final r = await _dio.post<Map<String, dynamic>>('/support/tickets', data: {'category': category.toUpperCase(), 'subject': subject, 'body': body, 'attachmentIds': ids});
        return _ticket(r.data!);
      });

  @override
  Future<TicketMessage> reply(String ticketId, {required String body, List<PickedFile> files = const []}) => guard(() async {
        final ids = await _upload(files);
        final r = await _dio.post<Map<String, dynamic>>('/support/tickets/$ticketId/messages', data: {'body': body, 'attachmentIds': ids});
        return _msg(r.data!);
      });

  @override
  Future<void> close(String ticketId) => guard(() => _dio.post<void>('/support/tickets/$ticketId/close'));

  @override
  Future<int> unread() => guard(() async => ((await _dio.get<Map<String, dynamic>>('/support/unread')).data!['unread'] as num).toInt());

  @override
  Stream<String> replies() => _replies.stream;

  Future<void> _connect() async {
    if (_socket != null) return;
    final token = await _store.readAccessToken();
    if (token == null || _socket != null) return;
    final s = io.io('$apiBaseUrl/chat', io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token}).enableReconnection().build());
    _socket = s;
    s.on('support:message', (data) {
      final m = data is Map ? data['ticketId'] : null;
      if (m is String) _replies.add(m);
    });
  }
}

/// Preview only: keeps tickets in memory and sends a sample staff reply a few
/// seconds later, so the in-page thread can be tried without a server.
class DemoSupportRepository implements SupportRepository {
  DemoSupportRepository(this._b);
  final DemoBackend _b;
  final _tickets = <SupportTicket>[];
  final _replies = StreamController<String>.broadcast();
  int _seq = 1042;

  Future<T> _delay<T>(T Function() f, [int ms = 450]) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    return f();
  }

  List<TicketFile> _files(List<PickedFile> files) => [
        for (final f in files) TicketFile(id: 'f${_seq++}', fileName: f.name, mime: f.mime, bytes: f.bytes.length, localBytes: f.bytes),
      ];

  void _replace(SupportTicket t) {
    final i = _tickets.indexWhere((x) => x.id == t.id);
    if (i >= 0) _tickets[i] = t;
  }

  void _staffReply(String id) {
    Timer(const Duration(seconds: 4), () {
      final t = _tickets.where((x) => x.id == id).firstOrNull;
      if (t == null || t.status == TicketStatus.closed) return;
      final ar = _b.lang == 'ar', fr = _b.lang == 'fr';
      final m = TicketMessage(
        id: 'm${_seq++}',
        fromStaff: true,
        body: ar
            ? 'مرحباً، شكراً لتواصلك مع دعم ألفة. استلمنا رسالتك وسيتابعها أحد أعضاء الفريق هنا في هذه الصفحة.'
            : fr
                ? 'Bonjour, merci d’avoir contacté le support OLFA. Nous avons bien reçu votre message ; un membre de l’équipe vous répondra ici.'
                : 'Hello, thanks for contacting OLFA support. We received your message and a team member will follow up right here.',
        createdAt: DateTime.now(),
      );
      _replace(SupportTicket(id: t.id, category: t.category, subject: t.subject, status: TicketStatus.pendingUser, lastMessageAt: m.createdAt, unread: t.unread + 1, lastBody: m.body, lastFromStaff: true, messages: [...t.messages, m]));
      _replies.add(id);
    });
  }

  @override
  Future<List<FaqEntry>> faq() => _b.faq();

  @override
  Future<List<SupportTicket>> tickets() => _delay(() => [..._tickets]..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt)));

  @override
  Future<SupportTicket> thread(String id) => _delay(() {
        final t = _tickets.firstWhere((x) => x.id == id);
        final read = SupportTicket(id: t.id, category: t.category, subject: t.subject, status: t.status, lastMessageAt: t.lastMessageAt, lastBody: t.lastBody, lastFromStaff: t.lastFromStaff, messages: t.messages);
        _replace(read);
        return read;
      }, 250);

  @override
  Future<SupportTicket> create({required String category, required String subject, required String body, List<PickedFile> files = const []}) => _delay(() {
        final now = DateTime.now();
        final t = SupportTicket(
          id: '#${_seq++}',
          category: category,
          subject: subject,
          status: TicketStatus.open,
          lastMessageAt: now,
          lastBody: body,
          messages: [TicketMessage(id: 'm${_seq++}', fromStaff: false, body: body, createdAt: now, files: _files(files))],
        );
        _tickets.add(t);
        _staffReply(t.id);
        return t;
      }, 700);

  @override
  Future<TicketMessage> reply(String ticketId, {required String body, List<PickedFile> files = const []}) => _delay(() {
        final t = _tickets.firstWhere((x) => x.id == ticketId);
        final m = TicketMessage(id: 'm${_seq++}', fromStaff: false, body: body, createdAt: DateTime.now(), files: _files(files));
        _replace(SupportTicket(id: t.id, category: t.category, subject: t.subject, status: TicketStatus.open, lastMessageAt: m.createdAt, lastBody: body, messages: [...t.messages, m]));
        _staffReply(ticketId);
        return m;
      }, 600);

  @override
  Future<void> close(String ticketId) => _delay(() {
        final t = _tickets.firstWhere((x) => x.id == ticketId);
        _replace(SupportTicket(id: t.id, category: t.category, subject: t.subject, status: TicketStatus.closed, lastMessageAt: t.lastMessageAt, lastBody: t.lastBody, lastFromStaff: t.lastFromStaff, messages: t.messages));
      });

  @override
  Future<int> unread() async => _tickets.fold<int>(0, (n, t) => n + t.unread);

  @override
  Stream<String> replies() => _replies.stream;
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) => useApi
    ? ApiSupportRepository(ref.watch(apiClientProvider), ref.watch(secureStoreProvider), ref.watch(localeProvider).languageCode)
    : DemoSupportRepository(ref.watch(demoBackendProvider)));

final faqProvider = FutureProvider<List<FaqEntry>>((ref) => ref.watch(supportRepositoryProvider).faq());
final ticketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) {
  final sub = ref.watch(supportRepositoryProvider).replies().listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return ref.watch(supportRepositoryProvider).tickets();
});
