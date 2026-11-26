import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/failure.dart';
import '../../../shared/models/models.dart';
import '../domain/messaging_repository.dart';
import 'messaging_repository_impl.dart';

/// A message written on this phone and not yet accepted by the server.
/// Saved to disk, so it survives losing the connection and closing the app.
@immutable
class OutboxEntry {
  const OutboxEntry({
    required this.clientId,
    required this.conversationId,
    required this.body,
    required this.createdAt,
    this.photos = const [],
    this.voice,
    this.failedCode,
  });

  /// Idempotency key: however many times it is sent, the server stores it once.
  final String clientId;
  final String conversationId;
  final String body;
  final DateTime createdAt;
  final List<({String path, int width, int height})> photos;
  final ({String path, int durationMs, List<int> waveform})? voice;

  /// Set when the server refused it for a reason a retry won't fix by itself
  /// (the person can retry or delete). Null = waiting / sending.
  final String? failedCode;

  OutboxEntry copyWith({String? failedCode, bool clearFailure = false, List<({String path, int width, int height})>? photos, ({String path, int durationMs, List<int> waveform})? voice}) => OutboxEntry(
        clientId: clientId,
        conversationId: conversationId,
        body: body,
        createdAt: createdAt,
        photos: photos ?? this.photos,
        voice: voice ?? this.voice,
        failedCode: clearFailure ? null : (failedCode ?? this.failedCode),
      );

  Map<String, Object?> toJson() => {
        'clientId': clientId,
        'conversationId': conversationId,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'photos': [for (final p in photos) {'path': p.path, 'width': p.width, 'height': p.height}],
        if (voice != null) 'voice': {'path': voice!.path, 'durationMs': voice!.durationMs, 'waveform': voice!.waveform},
        if (failedCode != null) 'failedCode': failedCode,
      };

  static OutboxEntry fromJson(Map<String, dynamic> j) {
    final v = j['voice'] as Map?;
    return OutboxEntry(
      clientId: j['clientId'] as String,
      conversationId: j['conversationId'] as String,
      body: j['body'] as String? ?? '',
      createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      photos: [
        for (final p in (j['photos'] as List? ?? const []))
          (path: p['path'] as String, width: (p['width'] as num).toInt(), height: (p['height'] as num).toInt()),
      ],
      voice: v == null ? null : (path: v['path'] as String, durationMs: (v['durationMs'] as num).toInt(), waveform: [for (final x in (v['waveform'] as List? ?? const [])) (x as num).toInt()]),
      failedCode: j['failedCode'] as String?,
    );
  }

  MessageKind get kind => voice != null ? MessageKind.voice : (photos.isNotEmpty ? MessageKind.image : MessageKind.text);

  /// The bubble shown while it waits (local files as previews).
  ChatMessage toBubble({required MessageStatus status}) => ChatMessage(
        id: 'local-$clientId',
        clientId: clientId,
        conversationId: conversationId,
        fromMe: true,
        body: body,
        sentAt: createdAt,
        status: status,
        kind: kind,
        attachments: voice != null
            ? [ChatAttachment(kind: MessageKind.voice, localPath: voice!.path, durationMs: voice!.durationMs, waveform: voice!.waveform)]
            : [for (final p in photos) ChatAttachment(kind: MessageKind.image, localPath: p.path, width: p.width, height: p.height)],
      );
}

/// What happened to a queued message.
class OutboxResult {
  const OutboxResult(this.entry, {this.saved, this.failure, this.queued = false, this.removed = false});
  final OutboxEntry entry;
  final ChatMessage? saved; // accepted by the server (has its position)
  final Failure? failure; // refused; [removed] when it can never be sent (quota)
  final bool queued; // offline: kept, sent automatically later
  final bool removed;
}

/// Where the queue lives on the phone (tests point it at a temp folder).
typedef OutboxDirectory = Future<Directory> Function();

/// Offline message queue.
///
/// - Every message is written to disk *before* it is sent (write-ahead), so nothing is
///   lost when the network drops or the app is closed mid-send.
/// - Messages of one conversation are sent one at a time, in the order they were
///   written; the server gives each its position, so the order is the same for both people.
/// - Retries reuse the same idempotency key: a message is never stored twice.
/// - Sending resumes by itself: when the realtime connection returns, when the app
///   comes back to the foreground, at start-up, and on a back-off timer (3 s → 60 s).
class Outbox {
  Outbox(this._repo, {OutboxDirectory? directory}) : _dirOf = directory ?? getApplicationSupportDirectory;

  final MessagingRepository Function() _repo;
  final OutboxDirectory _dirOf;
  final _entries = <OutboxEntry>[];
  final _results = StreamController<OutboxResult>.broadcast();
  final _locks = <String, Future<void>>{};
  Timer? _retry;
  int _backoff = 0;
  late final Future<void> ready = _load();
  Directory? _dir;

  Stream<OutboxResult> get results => _results.stream;

  /// Messages of this conversation still on the phone, in writing order.
  List<OutboxEntry> pendingFor(String conversationId) => [for (final e in _entries) if (e.conversationId == conversationId) e];
  bool get isEmpty => _entries.isEmpty;

  Future<File> get _file async => File('${(await _folder()).path}/chat_outbox.json');

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final d = Directory('${(await _dirOf()).path}/outbox');
    if (!d.existsSync()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<void> _load() async {
    try {
      final f = await _file;
      if (!f.existsSync()) return;
      final list = jsonDecode(await f.readAsString()) as List;
      _entries
        ..clear()
        ..addAll([for (final x in list) OutboxEntry.fromJson(Map<String, dynamic>.from(x as Map))]);
    } catch (e) {
      debugPrint('outbox: could not read the saved queue ($e)');
    }
  }

  Future<void> _save() async {
    final f = await _file;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final e in _entries) e.toJson()]), flush: true);
    await tmp.rename(f.path); // atomic replace: never a half-written queue
  }

  /// Copies picked / recorded files next to the queue (temporary files can be cleaned by the OS).
  Future<OutboxEntry> _keepFiles(OutboxEntry e) async {
    final dir = await _folder();
    Future<String> keep(String path) async {
      final src = File(path);
      if (!src.existsSync() || path.startsWith(dir.path)) return path;
      final dst = '${dir.path}/${e.clientId}_${src.uri.pathSegments.last}';
      await src.copy(dst);
      return dst;
    }

    return e.copyWith(
      photos: [for (final p in e.photos) (path: await keep(p.path), width: p.width, height: p.height)],
      voice: e.voice == null ? null : (path: await keep(e.voice!.path), durationMs: e.voice!.durationMs, waveform: e.voice!.waveform),
    );
  }

  Future<void> _deleteFiles(OutboxEntry e) async {
    final dir = await _folder();
    for (final p in [...e.photos.map((x) => x.path), if (e.voice != null) e.voice!.path]) {
      if (p.startsWith(dir.path)) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }
  }

  /// Queues and sends. Completes with the server copy, or throws: [NetworkFailure]
  /// means "kept, will be sent automatically"; other failures are final for this try.
  Future<ChatMessage> send(OutboxEntry entry) async {
    await ready;
    final e = await _keepFiles(entry);
    _entries
      ..removeWhere((x) => x.clientId == e.clientId)
      ..add(e);
    await _save();
    final done = Completer<ChatMessage>();
    late final StreamSubscription<OutboxResult> sub;
    sub = results.where((r) => r.entry.clientId == e.clientId).listen((r) {
      if (r.saved != null) {
        done.complete(r.saved);
      } else if (r.queued) {
        done.completeError(const NetworkFailure());
      } else {
        done.completeError(r.failure ?? const ServerFailure());
      }
      sub.cancel();
    });
    unawaited(_drain(e.conversationId));
    return done.future;
  }

  /// "Retry" on a failed bubble.
  Future<void> retry(String clientId) async {
    await ready;
    final i = _entries.indexWhere((e) => e.clientId == clientId);
    if (i < 0) return;
    _entries[i] = _entries[i].copyWith(clearFailure: true);
    await _save();
    await _drain(_entries[i].conversationId);
  }

  /// "Delete" on a failed / waiting bubble.
  Future<void> discard(String clientId) async {
    await ready;
    final i = _entries.indexWhere((e) => e.clientId == clientId);
    if (i < 0) return;
    final e = _entries.removeAt(i);
    await _save();
    await _deleteFiles(e);
    _results.add(OutboxResult(e, removed: true));
  }

  /// Sends everything that is waiting (connection back, app resumed, timer, start-up).
  Future<void> flushAll() async {
    await ready;
    final convs = {for (final e in _entries) if (e.failedCode == null) e.conversationId};
    await Future.wait(convs.map(_drain));
  }

  /// One sender per conversation: queued messages go out strictly in order.
  Future<void> _drain(String conversationId) {
    final next = (_locks[conversationId] ?? Future<void>.value()).then((_) => _drainNow(conversationId));
    _locks[conversationId] = next.catchError((Object _) {});
    return next;
  }

  Future<void> _drainNow(String conversationId) async {
    while (true) {
      final e = _entries.where((x) => x.conversationId == conversationId && x.failedCode == null).firstOrNull;
      if (e == null) return;
      try {
        final saved = await _repo().send(conversationId, e.clientId, e.body, media: await _media(e));
        _entries.removeWhere((x) => x.clientId == e.clientId);
        await _save();
        await _deleteFiles(e);
        _backoff = 0;
        _results.add(OutboxResult(e, saved: saved));
      } on UnauthorizedFailure {
        // signed out / session refreshing: keep everything, try again later
        _scheduleRetry();
        return;
      } on NetworkFailure {
        // keep everything from here on, in order; try again later
        for (final w in pendingFor(conversationId).where((x) => x.failedCode == null)) {
          _results.add(OutboxResult(w, queued: true));
        }
        _scheduleRetry();
        return;
      } on QuotaExceededFailure catch (f) {
        // can never be sent as-is: the composer gives the text back
        _entries.removeWhere((x) => x.clientId == e.clientId);
        await _save();
        await _deleteFiles(e);
        _results.add(OutboxResult(e, failure: f, removed: true));
      } on Failure catch (f) {
        final i = _entries.indexWhere((x) => x.clientId == e.clientId);
        if (i >= 0) _entries[i] = e.copyWith(failedCode: f.code);
        await _save();
        _results.add(OutboxResult(e, failure: f));
      } catch (err) {
        // file missing or unexpected error: mark failed, never loop forever
        final i = _entries.indexWhere((x) => x.clientId == e.clientId);
        if (i >= 0) _entries[i] = e.copyWith(failedCode: 'local');
        await _save();
        _results.add(OutboxResult(e, failure: const ServerFailure('local')));
      }
    }
  }

  Future<OutgoingMedia?> _media(OutboxEntry e) async {
    if (e.voice != null) {
      final v = e.voice!;
      return OutgoingMedia.voice(VoiceClip(path: v.path, bytes: await File(v.path).readAsBytes(), durationMs: v.durationMs, waveform: v.waveform));
    }
    if (e.photos.isEmpty) return null;
    return OutgoingMedia.photos([
      for (final p in e.photos) PreparedPhoto(path: p.path, bytes: await File(p.path).readAsBytes(), width: p.width, height: p.height),
    ]);
  }

  void _scheduleRetry() {
    _retry?.cancel();
    const steps = [3, 6, 12, 30, 60];
    final s = steps[_backoff.clamp(0, steps.length - 1)];
    _backoff++;
    _retry = Timer(Duration(seconds: s), () => unawaited(flushAll()));
  }

  void dispose() {
    _retry?.cancel();
    _results.close();
  }
}

/// One queue for the app; resumes sending when the connection or the app comes back.
final outboxProvider = Provider<Outbox>((ref) {
  final box = Outbox(() => ref.read(messagingRepositoryProvider));
  ref.listen<bool>(connectionProvider, (prev, online) {
    if (online && prev == false) unawaited(box.flushAll());
  });
  final life = AppLifecycleListener(onResume: () => unawaited(box.flushAll()));
  unawaited(box.ready.then((_) => box.flushAll()));
  ref.onDispose(() {
    life.dispose();
    box.dispose();
  });
  return box;
});
