import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_logo.dart';
import '../../../core/widgets/olfa_widgets.dart';

/// 1 — Splash
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Phase 2: replace the delay with session restore (secure storage + /me).
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) context.go(Routes.onboarding);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: OlfaColors.primary,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const OlfaLogo(size: 104, variant: OlfaLogoVariant.symbolOnly),
            const SizedBox(height: 22),
            const OlfaWordmark(),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Text(l.tagline, style: context.type.bodySmall.copyWith(color: OlfaColors.white.withValues(alpha: 0.8))),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2 — Onboarding (3 slides)
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final slides = [
      (l.onboarding1Title, l.onboarding1Body, Icons.favorite_rounded),
      (l.onboarding2Title, l.onboarding2Body, Icons.people_rounded),
      (l.onboarding3Title, l.onboarding3Body, Icons.verified_user_rounded),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: () => context.go(Routes.language), child: Text(l.skip)),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _i = i),
                itemBuilder: (context, i) => LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    padding: OlfaSpace.page,
                    child: Column(
                      children: [
                        Container(
                          height: c.maxHeight * 0.48,
                          width: double.infinity,
                          decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(32)),
                          alignment: Alignment.center,
                          child: i == 0
                              ? const OlfaLogo(size: 124)
                              : Container(
                                  width: 124,
                                  height: 124,
                                  decoration: BoxDecoration(
                                    color: i == 1 ? OlfaColors.white : OlfaColors.black,
                                    borderRadius: OlfaRadius.all(30),
                                  ),
                                  child: Icon(slides[i].$3, size: 60, color: i == 1 ? OlfaColors.primary : OlfaColors.white),
                                ),
                        ),
                        const SizedBox(height: 30),
                        Text(slides[i].$1, style: t.h1, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(slides[i].$2, style: t.bodyLarge.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var j = 0; j < slides.length; j++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: j == _i ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: j == _i ? OlfaColors.primary : OlfaColors.gray,
                      borderRadius: OlfaRadius.all(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: OlfaButton(
                label: _i < slides.length - 1 ? l.next : l.getStarted,
                onPressed: () => _i < slides.length - 1
                    ? _page.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut)
                    : context.go(Routes.language),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3 — Language selection (switches RTL/LTR live)
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final current = ref.watch(localeProvider).languageCode;
    Widget option(String code, String name, String sub) {
      final on = current == code;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: on ? OlfaColors.primaryTint() : OlfaColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: OlfaRadius.all(18),
            side: BorderSide(color: on ? OlfaColors.primary : OlfaColors.gray, width: 1.5),
          ),
          child: InkWell(
            borderRadius: OlfaRadius.all(18),
            onTap: () => ref.read(localeProvider.notifier).set(Locale(code)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: on ? OlfaColors.primary : OlfaColors.textDisabled),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(fontFamily: code == 'ar' ? 'Tajawal' : 'Montserrat', fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(sub, style: t.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: OlfaSpace.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OlfaLogo(size: 56),
              const SizedBox(height: 22),
              Text(l.languageTitle, style: t.h1),
              const SizedBox(height: 8),
              Text(l.languageBody, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted)),
              const SizedBox(height: 26),
              option('ar', 'العربية', 'Arabic · RTL'),
              option('en', 'English', 'الإنجليزية · LTR'),
              const Spacer(),
              OlfaButton(label: l.continueLabel, onPressed: () => context.push(Routes.phone)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
