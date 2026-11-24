import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';

import '../localization/generated/app_localizations.dart';
import '../theme/olfa_colors.dart';
import '../theme/olfa_typography.dart';

/// Protects members' photos from screen capture, across the whole app (every
/// tab shows other people's photos: discover, likes, matches, chats, profiles).
///
/// - Android: FLAG_SECURE — screenshots and screen recordings come out black, and
///   the app is blank in the recent-apps switcher.
/// - iOS: content is drawn in a secure layer that screenshots capture as blank
///   (iOS 13+); while the screen is being recorded, mirrored or AirPlayed the app
///   is covered ([CaptureShield]); in the app switcher it is blurred.
///
/// Limits (said plainly in Help): no app can stop someone photographing the
/// screen with another camera, and a jailbroken/rooted device can bypass the OS.
abstract final class ScreenProtection {
  /// True while iOS reports the screen is being recorded / mirrored.
  static final capturing = ValueNotifier<bool>(false);
  static bool _on = false;

  static Future<void> enable() async {
    if (_on || kIsWeb) return;
    _on = true;
    try {
      if (Platform.isAndroid) {
        await ScreenProtector.protectDataLeakageOn();
      } else if (Platform.isIOS) {
        await ScreenProtector.preventScreenshotOn();
        await ScreenProtector.protectDataLeakageWithBlur();
        ScreenProtector.addListener(() {}, (isCaptured) => capturing.value = isCaptured);
        capturing.value = await ScreenProtector.isRecording();
      }
    } catch (e) {
      // never block the app if the platform call fails; logged for diagnosis
      debugPrint('screen protection unavailable: $e');
    }
  }
}

/// Covers the whole app while the screen is being recorded or mirrored (iOS).
class CaptureShield extends StatelessWidget {
  const CaptureShield({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: ScreenProtection.capturing,
        builder: (context, capturing, _) => Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (capturing)
              ColoredBox(
                color: OlfaColors.white,
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.screen_lock_portrait_rounded, size: 48, color: OlfaColors.primary),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context).captureBlockedTitle, style: context.type.h3, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context).captureBlockedBody, style: context.type.bodyMedium.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
