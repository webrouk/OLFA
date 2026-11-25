import 'package:flutter/material.dart';

import 'olfa_colors.dart';

/// Typography system: Tajawal for Arabic, Montserrat for English.
/// Weights: Regular 400 (body) · Medium 500 (subtitles) ·
/// SemiBold 600 (buttons, emphasis) · Bold 700 (headings).
class OlfaTypography {
  OlfaTypography._(this.family, this.isArabic);

  factory OlfaTypography.forLocale(Locale locale) {
    final ar = locale.languageCode == 'ar';
    return OlfaTypography._(ar ? 'Tajawal' : 'Montserrat', ar);
  }

  final String family;
  final bool isArabic;

  // Montserrat is wider than Tajawal, so English sizes are slightly smaller.
  double _s(double ar, double en) => isArabic ? ar : en;

  TextStyle _t(double size, FontWeight w, {double h = 1.5, double ls = 0}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: w,
        height: h,
        letterSpacing: isArabic ? 0 : ls,
        color: OlfaColors.black,
      );

  TextStyle get display => _t(_s(34, 31), FontWeight.w700, h: 1.2, ls: -0.6);
  TextStyle get h1 => _t(_s(28, 26), FontWeight.w700, h: 1.25, ls: -0.5);
  TextStyle get h2 => _t(_s(22, 21), FontWeight.w700, h: 1.3);
  TextStyle get h3 => _t(_s(17, 16), FontWeight.w600, h: 1.35);
  TextStyle get bodyLarge => _t(_s(16, 15), FontWeight.w400, h: 1.6);
  TextStyle get bodyMedium => _t(_s(15, 14), FontWeight.w400, h: 1.6);
  TextStyle get bodySmall => _t(_s(13, 12.5), FontWeight.w400, h: 1.55);
  TextStyle get caption =>
      _t(_s(12.5, 12), FontWeight.w400).copyWith(color: OlfaColors.textMuted);
  TextStyle get button => _t(_s(16, 15), FontWeight.w600, h: 1.2);
  TextStyle get inputLabel => _t(13, FontWeight.w500, h: 1.3);

  /// Numbers (counts, prices, ratings, timers) are always set in Montserrat,
  /// in every language, so figures line up the same way across the app.
  TextStyle number(double size, {FontWeight weight = FontWeight.w700, Color color = OlfaColors.black}) =>
      TextStyle(fontFamily: 'Montserrat', fontSize: size, fontWeight: weight, height: 1.25, color: color);

  TextTheme toTextTheme() => TextTheme(
        displayLarge: display,
        headlineLarge: h1,
        headlineMedium: h2,
        titleLarge: h3,
        titleMedium: h3,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: button,
        labelMedium: inputLabel,
        labelSmall: caption,
      );
}

extension OlfaTextX on BuildContext {
  OlfaTypography get type => OlfaTypography.forLocale(Localizations.localeOf(this));
}
