import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/localization/generated/app_localizations.dart';
import 'package:olfa/core/widgets/olfa_widgets.dart';

import '../helpers.dart';

void main() {
  Widget bar(int index, Locale locale) => host(
        Align(alignment: Alignment.bottomCenter, child: Builder(builder: (c) => FloatingNavBar(items: OlfaNavItems.member(AppLocalizations.of(c)), index: index, onTap: (_) {}))),
        locale: locale,
      );

  testWidgets('glass: the bar blurs what is behind it', (tester) async {
    await tester.pumpWidget(bar(0, const Locale('en')));
    final f = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(f.filter, isA<ImageFilter>());
  });

  testWidgets('the glass pill sits under the active tab and follows the reading direction', (tester) async {
    for (final (locale, firstOnLeft) in [(const Locale('en'), true), (const Locale('ar'), false)]) {
      await tester.pumpWidget(bar(0, locale));
      await tester.pumpAndSettle();
      final pill = tester.getRect(find.byType(AnimatedPositioned));
      final barRect = tester.getRect(find.byType(BackdropFilter));
      expect(firstOnLeft ? pill.left < barRect.center.dx : pill.right > barRect.center.dx, isTrue, reason: '$locale');
      // moving to the last tab slides the pill to the other end
      await tester.pumpWidget(bar(4, locale));
      await tester.pumpAndSettle();
      final moved = tester.getRect(find.byType(AnimatedPositioned));
      expect(firstOnLeft ? moved.left > barRect.center.dx : moved.right < barRect.center.dx, isTrue, reason: '$locale');
    }
  });
}
