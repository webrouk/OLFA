import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/errors/failure.dart';
import 'package:olfa/features/messaging/data/outbox.dart';
import 'package:olfa/features/messaging/domain/messaging_repository.dart';
import 'package:olfa/shared/models/models.dart';

/// A server that can be "offline", records what it stored and keeps it idempotent.
class FakeServer implements MessagingRepository {
  bool online = true;
  final stored = <String, ChatMessage>{}; // clientId → message
  int seq = 0;

  @override
  Future<ChatMessage> send(String conversationId, String clientId, String body, {OutgoingMedia? media}) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (!online) throw const NetworkFailure();
    return stored[clientId] ??= ChatMessage(
      id: 's$clientId', clientId: clientId, conversationId: conversationId, fromMe: true, body: body, sentAt: DateTime.now(), status: MessageStatus.sent, seq: ++seq,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

OutboxEntry entry(String id, {String conv = 'c'}) => OutboxEntry(clientId: id, conversationId: conv, body: 'msg $id', createdAt: DateTime.now());

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('outbox'));
  tearDown(() async => dir.delete(recursive: true));

  test('online: sent at once, removed from the queue', () async {
    final server = FakeServer();
    final box = Outbox(() => server, directory: () async => dir);
    final saved = await box.send(entry('1'));
    expect(saved.seq, 1);
    expect(box.pendingFor('c'), isEmpty);
  });

  test('offline: kept on disk, survives a restart, then sent in order exactly once', () async {
    final server = FakeServer()..online = false;
    final box = Outbox(() => server, directory: () async => dir);
    for (final id in ['a', 'b', 'c']) {
      await expectLater(box.send(entry(id)), throwsA(isA<NetworkFailure>()));
    }
    expect(box.pendingFor('c').map((e) => e.clientId), ['a', 'b', 'c']);

    // the app is closed and opened again: the queue is still there
    final again = Outbox(() => server, directory: () async => dir);
    await again.ready;
    expect(again.pendingFor('c').map((e) => e.clientId), ['a', 'b', 'c']);

    server.online = true;
    await again.flushAll();
    await again.flushAll(); // a second trigger (reconnect + resume) must not duplicate
    expect(again.pendingFor('c'), isEmpty);
    expect(server.stored.keys, ['a', 'b', 'c']);
    expect([for (final id in ['a', 'b', 'c']) server.stored[id]!.seq], [1, 2, 3]);
  });

  test('a refused message is kept as failed and can be discarded', () async {
    final server = _Refusing();
    final box = Outbox(() => server, directory: () async => dir);
    await expectLater(box.send(entry('x')), throwsA(isA<ServerFailure>()));
    expect(box.pendingFor('c').single.failedCode, 'conversation_closed');
    await box.discard('x');
    expect(box.pendingFor('c'), isEmpty);
  });
}

class _Refusing extends FakeServer {
  @override
  Future<ChatMessage> send(String conversationId, String clientId, String body, {OutgoingMedia? media}) async => throw const ServerFailure('conversation_closed');
}
