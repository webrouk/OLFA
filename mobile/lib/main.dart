import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/network/api_client.dart' show useApi;

void main() {
  // Release builds must talk to the real backend — never ship demo data.
  if (kReleaseMode && !useApi) {
    throw StateError('API_BASE_URL is required for release builds: --dart-define=API_BASE_URL=https://api.example.com');
  }
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: OlfaApp()));
}
