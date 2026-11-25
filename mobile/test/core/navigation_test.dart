import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/routing/navigation.dart';
import 'package:olfa/core/theme/olfa_spacing.dart';
import 'package:olfa/core/widgets/olfa_widgets.dart';
import 'package:olfa/features/consultations/presentation/consult_labels.dart';

void main() {
  group('PushGuard', () {
    setUp(PushGuard.reset);
    final t0 = DateTime(2026, 11, 25, 12);

    test('a double tap opens the page once', () {
      expect(PushGuard.allow('/discover/profile/1', '/discover', t0), isTrue);
      expect(PushGuard.allow('/discover/profile/1', '/discover', t0.add(const Duration(milliseconds: 250))), isFalse);
    });
    test('the same page can be opened again later', () {
      expect(PushGuard.allow('/discover/profile/1', '/discover', t0), isTrue);
      expect(PushGuard.allow('/discover/profile/1', '/discover', t0.add(const Duration(seconds: 2))), isTrue);
    });
    test('another page opens straight away', () {
      expect(PushGuard.allow('/discover/profile/1', '/discover', t0), isTrue);
      expect(PushGuard.allow('/discover/profile/2', '/discover', t0.add(const Duration(milliseconds: 100))), isTrue);
    });
    test('the page already on screen is not pushed again', () {
      expect(PushGuard.allow('/messages/c1', '/messages/c1', t0), isFalse);
    });
  });

  test('badge text caps at 99+', () {
    expect(badgeText(7), '7');
    expect(badgeText(99), '99');
    expect(badgeText(100), '99+');
  });

  test('counselor initials skip titles and handle Arabic', () {
    expect(CounselorAvatar.initials('د. سارة الأحمد'), 'سا');
    expect(CounselorAvatar.initials('Dr. Omar Haddad'), 'OH');
    expect(CounselorAvatar.initials('Lina'), 'L');
    expect(CounselorAvatar.initials('  '), '');
  });

  testWidgets('nav clearance: bar inside the shell, safe area only elsewhere', (tester) async {
    late double inShell, onPushed, withRail;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(393, 852), padding: EdgeInsets.only(bottom: 34)),
      child: Directionality(textDirection: TextDirection.ltr, child: Column(children: [
        NavChrome(bottomBar: true, child: Builder(builder: (c) {
          inShell = OlfaSize.navBarClearance(c);
          return const SizedBox();
        })),
        NavChrome(bottomBar: false, child: Builder(builder: (c) {
          withRail = OlfaSize.navBarClearance(c);
          return const SizedBox();
        })),
        Builder(builder: (c) {
          onPushed = OlfaSize.navBarClearance(c);
          return const SizedBox();
        }),
      ])),
    ));
    expect(inShell, OlfaSize.navBarHeight + OlfaSize.navBarMargin + 12 + 34);
    expect(withRail, 34);
    expect(onPushed, 34);
  });

  testWidgets('re-tapping a tab scrolls it back to the top', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: TabRoot(tab: 3, child: Scaffold(body: ListView.builder(itemCount: 200, itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i'))))),
      ),
    ));
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsNothing);
    container.read(tabReselectProvider.notifier).state = (tab: 3, tick: 1);
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsOneWidget);
  });
}
