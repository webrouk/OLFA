import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';

/// 1 — Splash
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _visible = true));
    // Phase 3: restore the session (secure storage + GET /me) and route by
    // account status instead of the fixed delay.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) context.go(Routes.onboarding);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: OlfaColors.primary,
      body: GestureDetector(
        onTap: () => context.go(Routes.onboarding),
        child: SafeArea(
          child: SizedBox.expand(
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: motion(context, const Duration(milliseconds: 600)),
              child: Column(
                children: [
                  const Spacer(),
                  const OlfaLogo(size: 104, variant: OlfaLogoVariant.symbolOnly),
                  const SizedBox(height: 22),
                  const OlfaWordmark(),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(30, 0, 30, 40),
                    child: Text(l.tagline, textAlign: TextAlign.center, style: context.type.bodySmall.copyWith(color: OlfaColors.white.withValues(alpha: 0.85))),
                  ),
                ],
              ),
            ),
          ),
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
      (l.onboarding1Title, l.onboarding1Body, null),
      (l.onboarding2Title, l.onboarding2Body, Icons.people_alt_rounded),
      (l.onboarding3Title, l.onboarding3Body, Icons.verified_user_rounded),
    ];
    final last = _i == slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton(onPressed: () => context.go(Routes.language), child: Text(l.skip)),
                ),
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
                            height: (c.maxHeight * 0.5).clamp(180.0, 380.0).toDouble(),
                            width: double.infinity,
                            decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(32)),
                            alignment: Alignment.center,
                            child: slides[i].$3 == null
                                ? const OlfaLogo(size: 124)
                                : Container(
                                    width: 124,
                                    height: 124,
                                    decoration: BoxDecoration(color: i == 1 ? OlfaColors.white : OlfaColors.black, borderRadius: OlfaRadius.all(30)),
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
              Semantics(
                label: '${_i + 1} / ${slides.length}',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var j = 0; j < slides.length; j++)
                      AnimatedContainer(
                        duration: motion(context, const Duration(milliseconds: 250)),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: j == _i ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(color: j == _i ? OlfaColors.primary : OlfaColors.gray, borderRadius: OlfaRadius.all(4)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: PrimaryButton(
                  label: last ? l.getStarted : l.next,
                  onPressed: () => last
                      ? context.go(Routes.language)
                      : _page.nextPage(duration: motion(context, const Duration(milliseconds: 300)), curve: Curves.easeOut),
                ),
              ),
            ],
          ),
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
    final current = ref.watch(localeProvider).languageCode;

    Widget option(String code, String name, String sub) {
      final on = current == code;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          selected: on,
          button: true,
          child: Material(
            color: on ? OlfaColors.primaryTint() : OlfaColors.white,
            shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(18), side: BorderSide(color: on ? OlfaColors.primary : OlfaColors.gray, width: 1.5)),
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
                          Text(sub, style: context.type.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return FormPage(
      action: PrimaryButton(label: l.continueLabel, onPressed: () => context.push(Routes.phone)),
      children: [
        const Padding(padding: EdgeInsets.only(bottom: 22), child: OlfaLogo(size: 56)),
        PageHeading(l.languageTitle, body: l.languageBody),
        option('ar', 'العربية', 'Arabic · RTL'),
        option('en', 'English', 'الإنجليزية · LTR'),
      ],
    );
  }
}
