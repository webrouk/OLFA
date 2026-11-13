import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/localization/generated/app_localizations.dart';
import 'package:olfa/core/theme/olfa_colors.dart';
import 'package:olfa/core/theme/olfa_theme.dart';
import 'package:olfa/core/widgets/floating_nav_bar.dart';
import 'package:olfa/core/widgets/olfa_logo.dart';
import 'package:olfa/core/widgets/olfa_widgets.dart';

Widget host(Widget child, {Locale locale = const Locale('ar'), Size size = const Size(393, 852)}) {
  return MediaQuery(
    data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 54, bottom: 34)),
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: OlfaTheme.light(locale),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  test('brand palette is exactly the four approved colours', () {
    expect(OlfaColors.primary, const Color(0xFF8B0D2B));
    expect(OlfaColors.black, const Color(0xFF1A1A1A));
    expect(OlfaColors.gray, const Color(0xFFE9E9E9));
    expect(OlfaColors.white, const Color(0xFFFFFFFF));
  });

  testWidgets('OlfaButton is disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(host(const OlfaButton(label: 'x', onPressed: null)));
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('OlfaCheck toggles', (tester) async {
    var v = false;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (c, set) => OlfaCheck(value: v, onChanged: (n) => set(() => v = n), label: 'ok'),
    )));
    await tester.tap(find.text('ok'));
    await tester.pump();
    expect(v, isTrue);
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('FloatingNavBar renders 5 tabs and reports taps (${locale.languageCode})', (tester) async {
      int? tapped;
      await tester.pumpWidget(host(
        Align(alignment: Alignment.bottomCenter, child: FloatingNavBar(index: 0, onTap: (i) => tapped = i)),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      final l = await AppLocalizations.delegate.load(locale);
      for (final label in [l.navDiscover, l.navLikes, l.navMatches, l.navMessages, l.navProfile]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text(l.navMessages));
      expect(tapped, 3);

      // RTL puts the first tab on the right; LTR on the left.
      final first = tester.getCenter(find.text(l.navDiscover)).dx;
      final last = tester.getCenter(find.text(l.navProfile)).dx;
      expect(locale.languageCode == 'ar' ? first > last : first < last, isTrue);
    });
  }

  testWidgets('FloatingNavBar fits a small 360dp screen without overflow', (tester) async {
    await tester.pumpWidget(host(
      Align(alignment: Alignment.bottomCenter, child: FloatingNavBar(index: 2, onTap: (_) {})),
      size: const Size(360, 740),
      locale: const Locale('en'),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('OlfaLogo paints', (tester) async {
    await tester.pumpWidget(host(const Center(child: OlfaLogo(size: 96))));
    expect(find.byType(OlfaLogo), findsOneWidget);
  });
}
