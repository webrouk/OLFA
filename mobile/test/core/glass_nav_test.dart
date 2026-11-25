import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/localization/generated/app_localizations.dart';
import 'package:olfa/core/widgets/olfa_widgets.dart';

import '../helpers.dart';

final pillFinder = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_GlassPill');

void main() {
  Widget bar(int index, Locale locale, {ValueChanged<int>? onTap, Map<int, int> badges = const {}}) => host(
        Align(
          alignment: Alignment.bottomCenter,
          child: Builder(
            builder: (c) => FloatingNavBar(
              items: OlfaNavItems.member(AppLocalizations.of(c)),
              index: index,
              badges: badges,
              layout: OlfaNavItems.memberLayout,
              onTap: onTap ?? (_) {},
            ),
          ),
        ),
        locale: locale,
      );

  Rect capsule(WidgetTester t) => t.getRect(find.byType(BackdropFilter).first);
  Rect roundButton(WidgetTester t) => t.getRect(find.byType(BackdropFilter).last);

  testWidgets('two panes of glass: the capsule and the round button both blur what is behind', (tester) async {
    await tester.pumpWidget(bar(2, const Locale('ar')));
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter).first).filter, isA<ImageFilter>());
    final r = roundButton(tester);
    expect(r.width, r.height, reason: 'the round button is a circle');
  });

  testWidgets('Arabic: round button far left; capsule reads Menu, Chat, Explore, Marriage from left to right', (tester) async {
    await tester.pumpWidget(bar(2, const Locale('ar')));
    expect(roundButton(tester).right, lessThan(capsule(tester).left));
    final xs = ['القائمة', 'دردشة', 'استكشاف', 'الزواج'].map((s) => tester.getCenter(find.text(s)).dx).toList();
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]));
    }
  });

  testWidgets('English mirrors it: round button far right', (tester) async {
    await tester.pumpWidget(bar(2, const Locale('en')));
    expect(roundButton(tester).left, greaterThan(capsule(tester).right));
  });

  testWidgets('each item opens its own tab (router index)', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(bar(2, const Locale('ar'), onTap: (i) => tapped = i));
    for (final (label, tab) in [('القائمة', 4), ('دردشة', 3), ('استكشاف', 0), ('الزواج', 2)]) {
      await tester.tap(find.text(label));
      expect(tapped, tab, reason: label);
    }
    await tester.tapAt(roundButton(tester).center);
    expect(tapped, 1, reason: 'round button = likes');
  });

  testWidgets('badges keep their tabs and never block the tap', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(bar(2, const Locale('ar'), badges: const {1: 2, 3: 5}, onTap: (i) => tapped = i));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.text('5')));
    expect(tapped, 3);
    await tester.tapAt(tester.getCenter(find.text('2')));
    expect(tapped, 1);
  });

  testWidgets('the marker glides to the new tab and fades out when the round button is active', (tester) async {
    await tester.pumpWidget(bar(2, const Locale('ar')));
    await tester.pumpAndSettle();
    final atMarriage = tester.getRect(pillFinder.first);
    expect(atMarriage.center.dx, closeTo(tester.getCenter(find.text('الزواج')).dx, 2));
    await tester.pumpWidget(bar(4, const Locale('ar')));
    await tester.pumpAndSettle();
    expect(tester.getRect(pillFinder.first).center.dx, closeTo(tester.getCenter(find.text('القائمة')).dx, 2));
    await tester.pumpWidget(bar(1, const Locale('ar')));
    await tester.pumpAndSettle();
    final fades = tester.widgetList<AnimatedOpacity>(find.ancestor(of: pillFinder, matching: find.byType(AnimatedOpacity))).map((o) => o.opacity).toList();
    expect(fades, containsAll(<double>[0, 1]), reason: 'capsule marker hidden, round button filled');
  });

  testWidgets('drag along the capsule scrubs; the tab under the finger opens on release', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(bar(2, const Locale('ar'), onTap: (i) => tapped = i));
    final r = capsule(tester);
    // Arabic: from the right end (Marriage) to the left end (Menu)
    await tester.dragFrom(Offset(r.right - 30, r.center.dy), Offset(-(r.width - 60), 0));
    await tester.pumpAndSettle();
    expect(tapped, 4);
  });
}
