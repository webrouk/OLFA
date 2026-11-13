import 'package:flutter/material.dart';

/// OLFA brand palette. These four colours are the ONLY brand colours.
/// Tints are opacity variants of the same colours — no new hues, no gradients.
abstract final class OlfaColors {
  static const Color primary = Color(0xFF8B0D2B); // Burgundy — أحمر دم الغزال
  static const Color black = Color(0xFF1A1A1A); // Primary text
  static const Color gray = Color(0xFFE9E9E9); // Secondary surfaces, dividers
  static const Color white = Color(0xFFFFFFFF); // Main background

  static Color primaryTint([double opacity = 0.08]) =>
      primary.withValues(alpha: opacity);
  static final Color textMuted = black.withValues(alpha: 0.62);
  static final Color textDisabled = black.withValues(alpha: 0.40);
  static final Color scrim = black.withValues(alpha: 0.42);
}
