import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:olfa/core/localization/generated/app_localizations.dart';
import 'package:olfa/core/theme/olfa_theme.dart';

const kDevices = <String, Size>{
  'small-android-360x740': Size(360, 740),
  'iphone-15-393x852': Size(393, 852),
  'ipad-mini-744x1133': Size(744, 1133),
};

/// Wraps a widget in MaterialApp + localisation for widget tests.
Widget host(Widget child, {Locale locale = const Locale('ar'), Size size = const Size(393, 852)}) {
  return MediaQuery(
    data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 54, bottom: 34)),
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
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
