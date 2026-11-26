import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/features/messaging/domain/thread_order.dart';
import 'package:olfa/shared/models/models.dart';

ChatMessage m(String id, {int? seq, bool mine = false, MessageStatus status = MessageStatus.delivered, int at = 0}) => ChatMessage(
      id: id,
      clientId: id,
      conversationId: 'c',
      fromMe: mine,
      body: id,
      sentAt: DateTime(2026, 11, 25, 10).add(Duration(seconds: at)),
      status: status,
      seq: seq,
    );

void main() {
  test('server order wins over arrival order and clocks', () {
    // events arrive 3, 1, 2 and the phone clock is off: the thread is still 1, 2, 3
    final t = mergeThread([m('c', seq: 3, at: 1)], [m('a', seq: 1, at: 9), m('b', seq: 2, at: 5)]);
    expect(t.map((x) => x.seq), [1, 2, 3]);
  });

  test('no duplicates: the server copy replaces the local bubble', () {
    final local = m('x', mine: true, status: MessageStatus.sending, at: 50);
    final t = mergeThread([m('a', seq: 1), local], [m('x', seq: 2, mine: true, status: MessageStatus.sent)]);
    expect(t.length, 2);
    expect(t.last.seq, 2);
    expect(t.last.status, MessageStatus.sent);
    // the same event twice (socket + send response) changes nothing
    expect(mergeThread(t, [m('x', seq: 2, mine: true, status: MessageStatus.sent)]).length, 2);
  });

  test('messages still on the phone stay after confirmed ones, in writing order', () {
    final t = mergeThread(
      [m('q2', mine: true, status: MessageStatus.queued, at: 20), m('q1', mine: true, status: MessageStatus.queued, at: 10)],
      [m('a', seq: 7, at: 30)],
    );
    expect(t.map((x) => x.id), ['a', 'q1', 'q2']);
  });

  test('a status never goes backwards between server copies', () {
    final t = mergeThread([m('x', seq: 4, mine: true, status: MessageStatus.read)], [m('x', seq: 4, mine: true, status: MessageStatus.sent)]);
    expect(t.single.status, MessageStatus.read);
  });

  test('delivered / read positions update my ticks', () {
    final t = [m('a', seq: 1, mine: true, status: MessageStatus.sent), m('b', seq: 2, mine: true, status: MessageStatus.sent), m('c', seq: 3, mine: true, status: MessageStatus.sent)];
    final r = applyPeerPositions(t, deliveredUpTo: 3, readUpTo: 1).map((x) => x.status).toList();
    expect(r, [MessageStatus.read, MessageStatus.delivered, MessageStatus.delivered]);
    expect(lastSeqOf(t), 3);
  });

  test('latest message first in the conversation list', () {
    Conversation c(String id, int? min) => Conversation(id: id, lastAt: min == null ? null : DateTime(2026).add(Duration(minutes: min)));
    final list = [c('old', 1), c('none', null), c('new', 9), c('mid', 5)]..sort(byLatestActivity);
    expect(list.map((x) => x.id), ['new', 'mid', 'old', 'none']);
    final moved = c('old', 1).withMessage(preview: 'hi', kind: MessageKind.text, fromMe: false, at: DateTime(2026).add(const Duration(minutes: 20)), countUnread: true);
    final again = [moved, c('new', 9), c('mid', 5)]..sort(byLatestActivity);
    expect(again.first.id, 'old');
    expect(again.first.unread, 1);
  });
}
