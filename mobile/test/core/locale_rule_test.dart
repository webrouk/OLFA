import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/core/localization/locale_provider.dart';

void main() {
  test('opens in the phone language when it is Arabic, English or French', () {
    expect(resolveDeviceLocale(const [Locale('ar', 'EG')]), const Locale('ar'));
    expect(resolveDeviceLocale(const [Locale('fr', 'CA')]), const Locale('fr'));
    expect(resolveDeviceLocale(const [Locale('en', 'GB')]), const Locale('en'));
  });

  test('any other phone language opens in English', () {
    expect(resolveDeviceLocale(const [Locale('es', 'ES')]), const Locale('en'));
    expect(resolveDeviceLocale(const [Locale('tr')]), const Locale('en'));
    expect(resolveDeviceLocale(const []), const Locale('en'));
  });

  test('the first supported language in the phone list wins', () {
    expect(resolveDeviceLocale(const [Locale('de'), Locale('fr'), Locale('ar')]), const Locale('fr'));
    expect(resolveDeviceLocale(const [Locale('ur'), Locale('ar')]), const Locale('ar'));
  });
}
