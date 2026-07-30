import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/auth/auth_storage.dart';
import 'shared/analytics/app_analytics.dart';
import 'shared/api/api_environment.dart';
import 'shared/debug/app_debug_overlay.dart';
import 'shared/firebase/app_firebase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  configureAppDebugOverlay();
  await const SecureAuthStorage().prepareForCurrentInstallation();
  final firebase = await AppFirebase.initialize();
  firebase?.installGlobalErrorHandlers();
  installAppDebugErrorHandlers();
  final analytics = await AppAnalytics.initialize(firebase: firebase);
  runApp(
    ProviderScope(
      overrides: [analyticsProvider.overrideWithValue(analytics)],
      child: const KandoApp(),
    ),
  );
}
