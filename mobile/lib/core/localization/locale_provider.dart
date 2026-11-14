import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const supportedLocales = [Locale('ar'), Locale('en')];

/// The user's language choice: follow the device (default, as Apple and Google
/// recommend — iOS "Settings › OLFA › Language" and Android 13+ per-app
/// language both change the device-side locale the app receives) or a fixed
/// in-app choice that is remembered across launches.
enum LanguageChoice { system, ar, en }

/// Device locale → a supported one (Arabic for any Arabic region, else English).
Locale resolveDeviceLocale([List<Locale>? preferred]) {
  for (final l in preferred ?? PlatformDispatcher.instance.locales) {
    if (l.languageCode == 'ar') return const Locale('ar');
    if (l.languageCode == 'en') return const Locale('en');
  }
  return const Locale('ar');
}

class LocaleController extends Notifier<Locale> with WidgetsBindingObserver {
  static const _key = 'olfa.language';
  static const _store = FlutterSecureStorage();
  LanguageChoice _choice = LanguageChoice.system;

  /// Optional hook (set by the account layer) to tell the server, so push
  /// notifications and SMS follow the same language.
  static Future<void> Function(String code)? onChanged;

  LanguageChoice get choice => _choice;

  @override
  Locale build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    _restore();
    return resolveDeviceLocale();
  }

  Future<void> _restore() async {
    try {
      final saved = await _store.read(key: _key);
      final c = LanguageChoice.values.where((x) => x.name == saved).firstOrNull;
      if (c != null && c != LanguageChoice.system) {
        _choice = c;
        state = Locale(c.name);
      }
    } catch (_) {
      // Storage unavailable: keep following the device.
    }
  }

  /// Device language changed (system settings or per-app language).
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_choice == LanguageChoice.system) state = resolveDeviceLocale(locales);
  }

  Future<void> choose(LanguageChoice c) async {
    _choice = c;
    state = c == LanguageChoice.system ? resolveDeviceLocale() : Locale(c.name);
    try {
      await _store.write(key: _key, value: c.name);
    } catch (_) {}
    await onChanged?.call(state.languageCode).catchError((_) {});
  }

  /// Onboarding language step: an explicit choice.
  void set(Locale locale) => choose(locale.languageCode == 'ar' ? LanguageChoice.ar : LanguageChoice.en);
  void toggle() => set(state.languageCode == 'ar' ? const Locale('en') : const Locale('ar'));
}

final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);
