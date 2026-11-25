import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/motion.dart';
import 'olfa_colors.dart';
import 'olfa_spacing.dart';
import 'olfa_typography.dart';

/// Material 3 theme customised to the OLFA identity. Light only — the brand
/// palette has no dark variant yet (needs owner approval to add colours).
abstract final class OlfaTheme {
  static ThemeData light(Locale locale) {
    final type = OlfaTypography.forLocale(locale);
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: OlfaColors.primary,
      onPrimary: OlfaColors.white,
      secondary: OlfaColors.black,
      onSecondary: OlfaColors.white,
      error: OlfaColors.primary,
      onError: OlfaColors.white,
      surface: OlfaColors.white,
      onSurface: OlfaColors.black,
      surfaceContainerHighest: OlfaColors.gray,
      outline: OlfaColors.gray,
      outlineVariant: OlfaColors.gray,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: OlfaRadius.all(OlfaRadius.input),
      borderSide: const BorderSide(color: Colors.transparent, width: 1.5),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: OlfaColors.white,
      fontFamily: type.family,
      textTheme: type.toTextTheme(),
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: const DividerThemeData(color: OlfaColors.gray, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: OlfaColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: type.h3.copyWith(fontWeight: FontWeight.w700),
        iconTheme: const IconThemeData(color: OlfaColors.black),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: OlfaColors.primary,
          foregroundColor: OlfaColors.white,
          disabledBackgroundColor: OlfaColors.primary.withValues(alpha: 0.3),
          disabledForegroundColor: OlfaColors.white,
          minimumSize: const Size.fromHeight(OlfaSize.buttonHeight),
          shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(OlfaRadius.button)),
          textStyle: type.button,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: OlfaColors.black,
          minimumSize: const Size.fromHeight(OlfaSize.buttonHeight),
          side: const BorderSide(color: OlfaColors.gray, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(OlfaRadius.button)),
          textStyle: type.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: OlfaColors.primary,
          textStyle: type.button.copyWith(fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: OlfaColors.gray,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: type.bodyLarge.copyWith(color: OlfaColors.textDisabled),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: OlfaColors.primary, width: 1.5),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: OlfaColors.primary, width: 1.5),
        ),
        errorStyle: type.bodySmall.copyWith(color: OlfaColors.primary, fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: OlfaColors.white,
        selectedColor: OlfaColors.primaryTint(),
        side: const BorderSide(color: OlfaColors.gray, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(OlfaRadius.chip)),
        labelStyle: type.bodyMedium,
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? OlfaColors.primary : OlfaColors.gray,
        ),
        thumbColor: const WidgetStatePropertyAll(OlfaColors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: OlfaColors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: OlfaColors.gray,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(OlfaRadius.sheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: OlfaColors.black,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: type.bodyMedium.copyWith(color: OlfaColors.white),
        shape: RoundedRectangleBorder(borderRadius: OlfaRadius.all(14)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: OlfaPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
