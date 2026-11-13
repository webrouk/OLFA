import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const supportedLocales = [Locale('ar'), Locale('en')];

/// Current app locale. Arabic is the default; persisted in Phase 2.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => const Locale('ar');

  void set(Locale locale) => state = locale;
  void toggle() => state = state.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
}

final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);
