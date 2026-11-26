import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/app/app.dart';
import 'package:olfa/core/localization/locale_provider.dart';
import 'package:olfa/core/routing/app_router.dart';
import 'package:olfa/core/routing/routes.dart';

import '../helpers.dart';

/// Opens every one of the 26 screens in Arabic, English and French on small, regular
/// and tablet sizes, and fails on any exception — including RenderFlex
/// overflows, which Flutter reports as errors in tests.
const routes = <String, String>{
  '01 splash': Routes.splash,
  '02 onboarding': Routes.onboarding,
  '03 language': Routes.language,
  '04 phone': Routes.phone,
  '05 otp': Routes.otp,
  '06 age': Routes.age,
  '07 gender': Routes.gender,
  '08 info': Routes.profileInfo,
  '09 preferences': Routes.preferences,
  '10 photos': Routes.photos,
  '11 verification': Routes.verification,
  '12 discover': Routes.discover,
  '13 profile details': '/discover/profile/d1',
  '14 search': Routes.search,
  '15 likes': Routes.likes,
  '16 matches': Routes.matches,
  '17 my profile': Routes.myProfile,
  '18 conversations': Routes.conversations,
  '19 chat': '/messages/c-d1',
  '20 notifications': Routes.notifications,
  '21 edit profile': Routes.editProfile,
  '22 plans': Routes.plans,
  '23 payments': Routes.payments,
  '24 privacy': Routes.privacy,
  '25 help': Routes.help,
  '26 settings': Routes.settings,
};

void main() {
  for (final lang in const ['ar', 'en', 'fr']) {
    for (final device in kDevices.entries) {
      testWidgets('all 26 screens render without errors — $lang · ${device.key}', (tester) async {
        tester.view.physicalSize = device.value * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(localeProvider.notifier).set(Locale(lang));

        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const OlfaApp()));
        await tester.pump(const Duration(seconds: 2)); // splash timer

        for (final r in routes.entries) {
          container.read(routerProvider).go(r.value);
          await tester.pump();
          await tester.pump(const Duration(seconds: 2)); // demo latency
          final err = tester.takeException();
          expect(err, isNull, reason: '${r.key} threw: $err');
        }
      });
    }
  }
}
