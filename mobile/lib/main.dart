import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/network/api_client.dart' show useApi;
import 'core/security/screen_protection.dart';

void main() {
  // Release builds must talk to the real backend — never ship demo data.
  if (kReleaseMode && !useApi) {
    throw StateError('API_BASE_URL is required for release builds: --dart-define=API_BASE_URL=https://api.example.com');
  }
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Members' photos must not be captured (screenshots / recordings).
  unawaited(ScreenProtection.enable());
  runApp(const ProviderScope(child: OlfaApp()));
}
