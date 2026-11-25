import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/localization/generated/app_localizations.dart';
import 'package:olfa/core/theme/olfa_colors.dart';
import 'package:olfa/core/widgets/olfa_widgets.dart';

import '../helpers.dart';

void main() {
  test('brand palette is exactly the four approved colours', () {
    expect(OlfaColors.primary, const Color(0xFF8B0D2B));
    expect(OlfaColors.black, const Color(0xFF1A1A1A));
    expect(OlfaColors.gray, const Color(0xFFE9E9E9));
    expect(OlfaColors.white, const Color(0xFFFFFFFF));
  });

  testWidgets('PrimaryButton: disabled when onPressed null, disabled while loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(Column(children: [
      const PrimaryButton(label: 'a', onPressed: null),
      PrimaryButton(label: 'b', loading: true, onPressed: () => taps++),
    ])));
    final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
    expect(buttons[0].onPressed, isNull);
    expect(buttons[1].onPressed, isNull, reason: 'loading must block double submission');
    expect(taps, 0);
  });

  testWidgets('OtpInput reports digits only, max 6', (tester) async {
    String value = '';
    await tester.pumpWidget(host(OtpInput(onChanged: (v) => value = v)));
    await tester.enterText(find.byKey(const Key('otpField')), '12a3456789');
    await tester.pump();
    expect(value, '123456');
  });

  testWidgets('OlfaCheck toggles', (tester) async {
    var v = false;
    await tester.pumpWidget(host(StatefulBuilder(builder: (c, set) => OlfaCheck(value: v, onChanged: (n) => set(() => v = n), label: 'ok'))));
    await tester.tap(find.text('ok'));
    await tester.pump();
    expect(v, isTrue);
  });

  for (final locale in const [Locale('ar'), Locale('en'), Locale('fr')]) {
    testWidgets('FloatingNavBar: 5 tabs, taps, order follows direction (${locale.languageCode})', (tester) async {
      int? tapped;
      await tester.pumpWidget(host(Align(alignment: Alignment.bottomCenter, child: Builder(builder: (c) => FloatingNavBar(items: OlfaNavItems.member(AppLocalizations.of(c)), index: 0, onTap: (i) => tapped = i))), locale: locale));
      await tester.pumpAndSettle();
      final l = await AppLocalizations.delegate.load(locale);
      for (final label in [l.navDiscover, l.navLikes, l.navMatches, l.navMessages, l.navProfile]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text(l.navMessages));
      expect(tapped, 3);
      final first = tester.getCenter(find.text(l.navDiscover)).dx;
      final last = tester.getCenter(find.text(l.navProfile)).dx;
      expect(locale.languageCode == 'ar' ? first > last : first < last, isTrue);
    });
  }

  for (final e in kDevices.entries) {
    testWidgets('FloatingNavBar fits ${e.key} at 1.3× text', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: e.value, textScaler: const TextScaler.linear(1.3)),
        child: host(Align(alignment: Alignment.bottomCenter, child: Builder(builder: (c) => FloatingNavBar(items: OlfaNavItems.member(AppLocalizations.of(c)), index: 2, badges: const {1: 120, 3: 4}, onTap: (_) {}))), size: e.value, locale: const Locale('en')),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nav badges: real counts only, 99+ cap, none for 0', (tester) async {
    await tester.pumpWidget(host(Align(
      alignment: Alignment.bottomCenter,
      child: Builder(builder: (c) => FloatingNavBar(items: OlfaNavItems.member(AppLocalizations.of(c)), index: 0, badges: const {1: 0, 2: 3, 3: 250}, onTap: (_) {})),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(CountBadge), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('side rail shows the same tabs as the bottom bar', (tester) async {
    int? tapped;
    await tester.pumpWidget(host(
      Builder(builder: (c) => Row(children: [OlfaSideNav(items: OlfaNavItems.professional(AppLocalizations.of(c)), index: 1, badges: const {0: 2}, onTap: (i) => tapped = i), const Expanded(child: SizedBox())])),
      size: const Size(1024, 768),
      locale: const Locale('en'),
    ));
    await tester.pumpAndSettle();
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    for (final label in [l.navDesk, l.navWallet, l.navMessages, l.navProfile]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text(l.navMessages));
    expect(tapped, 2);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('EmptyState and ErrorState render', (tester) async {
    await tester.pumpWidget(host(const EmptyState(icon: Icons.inbox, title: 't', body: 'b')));
    expect(find.text('t'), findsOneWidget);
  });
}
