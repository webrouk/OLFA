import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/features/messaging/presentation/counselor_inbox_screen.dart';
import 'package:olfa/shared/models/models.dart';
import 'package:olfa/shared/services/demo_compat_bank.dart';
import 'package:olfa/shared/services/demo_compat_scoring.dart';

Conversation consult(String id, ConsultChatState st, {String name = 'Client', ConsultationStatus status = ConsultationStatus.completed, String? last}) => Conversation(
      id: id,
      section: ConversationSection.consultation,
      counselor: CounselorChatInfo(consultationId: 'k$id', name: name, status: status, counselorSide: true),
      consultState: st,
      lastMessage: last,
    );

void main() {
  test('days left before a deletion date (never negative, partial days round up)', () {
    final now = DateTime(2026, 11, 25, 12);
    expect(daysUntil(now.add(const Duration(days: 30)), now: now), 30);
    expect(daysUntil(now.add(const Duration(hours: 5)), now: now), 1);
    expect(daysUntil(now.subtract(const Duration(hours: 1)), now: now), 0);
  });

  test('a new message in an ended consultation chat restarts its 30 days', () {
    final at = DateTime(2026, 11, 25);
    final c = Conversation(id: 'c', section: ConversationSection.consultation, expiresAt: DateTime(2026, 11, 28));
    final after = c.withMessage(preview: 'hi', kind: MessageKind.text, fromMe: true, at: at, countUnread: false);
    expect(after.expiresAt, at.add(const Duration(days: 30)));
    // member chats keep their own rule
    final m = Conversation(id: 'm', expiresAt: DateTime(2026, 12, 1));
    expect(m.withMessage(preview: 'hi', kind: MessageKind.text, fromMe: true, at: at, countUnread: false).expiresAt, DateTime(2026, 12, 1));
  });

  test('counselor inbox: tabs, search (folded) and status filter', () {
    final ix = ConversationIndex(visible: [
      consult('1', ConsultChatState.active, name: 'أحمد', status: ConsultationStatus.confirmed),
      consult('2', ConsultChatState.ended, name: 'Sara', last: 'Thank you'),
      consult('3', ConsultChatState.ended, name: 'Omar', status: ConsultationStatus.refunded),
      consult('4', ConsultChatState.archived, name: 'Laila'),
      const Conversation(id: 'match'),
    ], locked: const [], visibleLimit: -1);
    expect(consultChatsIn(ix, ConsultChatState.active).map((c) => c.id), ['1']);
    expect(consultChatsIn(ix, ConsultChatState.ended).map((c) => c.id), ['2', '3']);
    expect(consultChatsIn(ix, ConsultChatState.archived).map((c) => c.id), ['4']);
    expect(consultChatsIn(ix, ConsultChatState.active, query: 'احمد').map((c) => c.id), ['1']); // أ/ا folded
    expect(consultChatsIn(ix, ConsultChatState.ended, query: 'thank').map((c) => c.id), ['2']);
    expect(consultChatsIn(ix, ConsultChatState.ended, status: ConsultationStatus.refunded).map((c) => c.id), ['3']);
  });

  test('demo compatibility scoring matches the server rules', () {
    final men = demoQuestionsFor(Gender.male), women = demoQuestionsFor(Gender.female);
    expect(men.length, 15);
    expect(women.length, 15);
    // same value on every topic → 100
    final topicValue = {for (final q in demoCompatBank) q.topic: q.options.first.$1};
    Map<String, String> answer(List<DemoCompatQuestion> qs) => {for (final q in qs) q.id: 'o${topicValue[q.topic]}'};
    final same = scoreDemoCompat(answer(men), answer(women));
    expect(same.score, 100);
    expect(same.agreed, 15);
    expect(same.domains.length, CompatDomain.values.length);
    // opposite ends on every topic → 0, every topic worth talking about (top 3 listed)
    final far = scoreDemoCompat(
      {for (final q in men) q.id: 'o${q.options.first.$1}'},
      {for (final q in women) q.id: 'o${q.options.last.$1}'},
    );
    expect(far.score, 0);
    expect(far.talkAbout.length, 3);
  });
}
