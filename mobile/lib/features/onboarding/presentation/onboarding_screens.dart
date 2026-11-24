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
import '../../../core/network/api_client.dart';
import '../../../core/security/secure_store.dart';
import '../../../shared/components/labels.dart';

/// 1 — Splash
/// Where a returning user lands, from the server's view of the account.
Future<String> resolveStartRoute(WidgetRef ref) async {
  if (!useApi) return Routes.onboarding;
  final token = await ref.read(secureStoreProvider).readAccessToken();
  if (token == null) return Routes.onboarding;
  try {
    final me = (await ref.read(apiClientProvider).dio.get<Map<String, dynamic>>('/me')).data!;
    // keep server-side push language in sync with the app
    LocaleController.onChanged = (code) => ref.read(apiClientProvider).dio.put<void>('/me/locale', data: {'locale': code});
    if (me['frozenAt'] != null) return Routes.frozen;
    if (me['profile'] == null) return Routes.gender;
    return Routes.discover; // pending accounts browse discovery read-only until approved
  } catch (_) {
    return Routes.onboarding;
  }
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _visible = true));
    // Restore the session (secure storage + GET /me) and route by account state.
    Future.wait([resolveStartRoute(ref), Future<void>.delayed(const Duration(milliseconds: 1200))]).then((r) {
      if (mounted) context.go(r.first as String);
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

/// 2 — Onboarding: four illustrated slides (flat shapes in the four brand
/// colours — no gradients, no 3D), each with a small "proof" row, a progress
/// bar, and the legal links before the account is created.
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
      (l.onboarding1Title, l.onboarding1Body, const _IntentArt(), OlfaColors.primary, [l.proofSerious, l.proofOneAccount]),
      (l.onboarding2Title, l.onboarding2Body, const _MatchArt(), OlfaColors.gray, [l.proofMutual, l.proofNearest]),
      (l.onboarding3Title, l.onboarding3Body, const _VerifiedArt(), OlfaColors.black, [l.proofReviewed, l.proofTwoTicks]),
      (l.onboarding4Title, l.onboarding4Body, const _ConsultArt(), OlfaColors.gray, [l.proofCounselors, l.proofPrivate]),
    ];
    final last = _i == slides.length - 1;
    final next = () => last
        ? context.go(Routes.language)
        : _page.nextPage(duration: motion(context, const Duration(milliseconds: 320)), curve: Curves.easeOutCubic);
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(children: [
                const OlfaLogo(size: 30, variant: OlfaLogoVariant.symbolOnly),
                const SizedBox(width: 14),
                // segmented progress
                Expanded(
                  child: Semantics(
                    label: '${_i + 1} / ${slides.length}',
                    child: Row(children: [
                      for (var j = 0; j < slides.length; j++)
                        Expanded(
                          child: AnimatedContainer(
                            duration: motion(context, const Duration(milliseconds: 250)),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            height: 4,
                            decoration: BoxDecoration(color: j <= _i ? OlfaColors.primary : OlfaColors.gray, borderRadius: OlfaRadius.all(2)),
                          ),
                        ),
                    ]),
                  ),
                ),
                TextButton(onPressed: () => context.go(Routes.language), child: Text(l.skip)),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _i = i),
                itemBuilder: (context, i) {
                  final s = slides[i];
                  return LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          height: (c.maxHeight * 0.52).clamp(200.0, 400.0).toDouble(),
                          width: double.infinity,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(color: s.$4, borderRadius: OlfaRadius.all(32)),
                          child: s.$3,
                        ),
                        const SizedBox(height: 26),
                        Text(s.$1, style: t.h1),
                        const SizedBox(height: 10),
                        Text(s.$2, style: t.bodyLarge.copyWith(color: OlfaColors.textMuted)),
                        const SizedBox(height: 16),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final p in s.$5)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(border: Border.all(color: OlfaColors.gray, width: 1.5), borderRadius: OlfaRadius.all(20)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.check_rounded, size: 16, color: OlfaColors.primary),
                                const SizedBox(width: 6),
                                Text(p, style: t.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                              ]),
                            ),
                        ]),
                      ]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Row(children: [
                if (_i > 0) ...[
                  OlfaIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: l.back,
                    size: 52,
                    onPressed: () => _page.previousPage(duration: motion(context, const Duration(milliseconds: 300)), curve: Curves.easeOutCubic),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(child: PrimaryButton(label: last ? l.getStarted : l.next, onPressed: next)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 14),
              child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(l.agreeByContinuing, style: t.caption),
                TextButton(onPressed: () => context.push(Routes.terms), style: TextButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(l.terms)),
                Text(l.and, style: t.caption),
                TextButton(onPressed: () => context.push(Routes.privacyPolicy), style: TextButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(l.privacyPolicy)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── slide illustrations (flat shapes in the brand colours) ──────────────

/// Slide 1 — intention: the symbol over two interlocking rings.
class _IntentArt extends StatelessWidget {
  const _IntentArt();
  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
        PositionedDirectional(start: -40, top: -40, child: _ring(180, OlfaColors.white.withValues(alpha: 0.10))),
        PositionedDirectional(end: -30, bottom: -50, child: _ring(220, OlfaColors.white.withValues(alpha: 0.08))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _ring(92, OlfaColors.white, stroke: 10),
          Transform.translate(offset: const Offset(-26, 0), child: _ring(92, OlfaColors.white.withValues(alpha: 0.75), stroke: 10)),
        ]),
        const Positioned(bottom: 22, child: OlfaWordmark()),
      ]);

  static Widget _ring(double d, Color c, {double stroke = 0}) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: stroke == 0 ? c : null, border: stroke == 0 ? null : Border.all(color: c, width: stroke)),
      );
}

/// Slide 2 — mutual compatibility: two profile cards and a score.
class _MatchArt extends StatelessWidget {
  const _MatchArt();
  @override
  Widget build(BuildContext context) {
    Widget card(double angle, Color head, Color body) => Transform.rotate(
          angle: angle,
          child: Container(
            width: 120,
            height: 158,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: OlfaColors.white, borderRadius: OlfaRadius.all(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Container(decoration: BoxDecoration(color: head, borderRadius: OlfaRadius.all(14)))),
              const SizedBox(height: 8),
              Container(height: 8, width: 70, decoration: BoxDecoration(color: body, borderRadius: OlfaRadius.all(4))),
              const SizedBox(height: 5),
              Container(height: 8, width: 46, decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(4))),
            ]),
          ),
        );
    return Stack(alignment: Alignment.center, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        card(-0.10, OlfaColors.primary, OlfaColors.black),
        const SizedBox(width: 18),
        card(0.10, OlfaColors.black, OlfaColors.primary),
      ]),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: OlfaColors.primary, borderRadius: OlfaRadius.all(22), border: Border.all(color: OlfaColors.white, width: 3)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.favorite_rounded, color: OlfaColors.white, size: 18),
          SizedBox(width: 6),
          Text('92%', textDirection: TextDirection.ltr, style: TextStyle(color: OlfaColors.white, fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'Montserrat')),
        ]),
      ),
    ]);
  }
}

/// Slide 3 — reviewed and verified: shield with the two ticks.
class _VerifiedArt extends StatelessWidget {
  const _VerifiedArt();
  @override
  Widget build(BuildContext context) {
    Widget tick(IconData i, String label) => Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(color: OlfaColors.white, borderRadius: OlfaRadius.all(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 16, color: OlfaColors.white),
            ),
            const SizedBox(width: 8),
            Icon(i, size: 18, color: OlfaColors.black),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: OlfaColors.black)),
          ]),
        );
    final l = AppLocalizations.of(context);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(color: OlfaColors.primary, borderRadius: OlfaRadius.all(34)),
        child: const Icon(Icons.verified_user_rounded, size: 58, color: OlfaColors.white),
      ),
      const SizedBox(height: 18),
      tick(Icons.photo_camera_outlined, l.photoVerifiedShort),
      const SizedBox(height: 8),
      tick(Icons.badge_outlined, l.detailsVerifiedShort),
    ]);
  }
}

/// Slide 4 — counselors and privacy: chat bubbles with a lock.
class _ConsultArt extends StatelessWidget {
  const _ConsultArt();
  @override
  Widget build(BuildContext context) {
    Widget bubble(double w, Color c, AlignmentDirectional a, {bool tail = true}) => Align(
          alignment: a,
          child: Container(
            width: w,
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: c, borderRadius: OlfaRadius.all(20)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
      child: Stack(children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          bubble(170, OlfaColors.white, AlignmentDirectional.centerStart),
          bubble(130, OlfaColors.primary, AlignmentDirectional.centerEnd),
          bubble(190, OlfaColors.white, AlignmentDirectional.centerStart),
          bubble(110, OlfaColors.primary, AlignmentDirectional.centerEnd),
        ]),
        Align(
          alignment: AlignmentDirectional.topEnd,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: OlfaColors.black, borderRadius: OlfaRadius.all(18)),
            child: const Icon(Icons.support_agent_rounded, color: OlfaColors.white, size: 30),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: OlfaColors.white, shape: BoxShape.circle, border: Border.all(color: OlfaColors.primary, width: 3)),
            child: const Icon(Icons.lock_rounded, color: OlfaColors.primary, size: 22),
          ),
        ),
      ]),
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
        // Pre-selected from the phone's language (English if it isn't one of these).
        for (final code in const ['ar', 'en', 'fr']) option(code, kNativeLanguageNames[code]!, languageNameIn(current, code)),
      ],
    );
  }
}
