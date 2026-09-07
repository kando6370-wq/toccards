import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'features/auth/auth_storage.dart';
import 'shared/analytics/app_analytics.dart';
import 'shared/api/api_environment.dart';
import 'shared/debug/app_debug_overlay.dart';
import 'shared/firebase/app_firebase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  AppConfig.validate();
  configureAppDebugOverlay();
  await const SecureAuthStorage().prepareForCurrentInstallation();
  final firebase = await AppFirebase.initialize();
  firebase?.installGlobalErrorHandlers();
  installAppDebugErrorHandlers();
  final analytics = AppAnalytics.initialize(firebase: firebase);
  runApp(
    ProviderScope(
      overrides: [analyticsProvider.overrideWithValue(analytics)],
      child: const KandoApp(),
    ),
  );
}
