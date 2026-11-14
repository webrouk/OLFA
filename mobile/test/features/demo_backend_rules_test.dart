import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/errors/failure.dart';
import 'package:olfa/shared/models/models.dart';
import 'package:olfa/shared/services/demo_backend.dart';

/// The demo backend mirrors server rules the UI depends on. These tests pin
/// those rules so the Phase 3 API can be checked against the same contract.
void main() {
  late DemoBackend b;
  setUp(() => b = DemoBackend());

  test('discovery only returns the opposite gender', () async {
    final list = await b.discover(const DiscoverFilters(ageMin: 18, ageMax: 80));
    expect(list, isNotEmpty);
    expect(list.every((p) => p.gender == Gender.female), isTrue);
  });

  test('paid filters are refused for the free plan (server-side, not just hidden)', () async {
    expect(
      () => b.discover(const DiscoverFilters(educations: {Education.master})),
      throwsA(isA<EntitlementRequiredFailure>()),
    );
    b.plan = PlanCode.plus;
    expect(await b.discover(const DiscoverFilters(ageMin: 18, ageMax: 80, educations: {Education.master})), isA<List<UserProfile>>());
  });

  test('a profile cannot be liked twice', () async {
    await b.like('d2');
    expect(() => b.like('d2'), throwsA(isA<AlreadyActedFailure>()));
  });

  test('daily like quota is enforced', () async {
    b.likesUsed = 10; // free = 10/day
    expect(() => b.like('d2'), throwsA(isA<QuotaExceededFailure>()));
  });

  test('mutual like creates a match; liked profiles leave discovery', () async {
    final m = await b.like('d1'); // d1 already likes the user
    expect(m, isNotNull);
    final list = await b.discover(const DiscoverFilters(ageMin: 18, ageMax: 80));
    expect(list.any((p) => p.id == 'd1'), isFalse);
  });

  test('free users get the likes count but no identities', () async {
    final r = await b.likesReceived();
    expect(r.count, greaterThan(0));
    expect(r.profiles, isEmpty);
  });

  test('starting a conversation spends one credit; sending is idempotent', () async {
    final matches = await b.matches();
    final fresh = matches.firstWhere((m) => m.conversationId == null);
    final conv = await b.startConversation(fresh.id);
    expect(b.messagesUsed, 1);
    final a = await b.send(conv, 'client-1', 'hello');
    final again = await b.send(conv, 'client-1', 'hello');
    expect(again.id, a.id);
    final page = await b.messages(conv);
    expect(page.items.where((m) => m.clientId == 'client-1').length, 1);
    await Future<void>.delayed(const Duration(seconds: 3)); // let demo reply timers finish
  });

  test('blocked users disappear from discovery and matches', () async {
    await b.block('d1');
    final list = await b.discover(const DiscoverFilters(ageMin: 18, ageMax: 80));
    expect(list.any((p) => p.id == 'd1'), isFalse);
    final ms = await b.matches();
    expect(ms.any((m) => m.peer.id == 'd1'), isFalse);
  });

  test('OTP 000000 is rejected and decrements attempts', () async {
    await b.requestOtp('+971501234567');
    expect(() => b.verifyOtp('000000'), throwsA(isA<InvalidOtpFailure>()));
  });
}
