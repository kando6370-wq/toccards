import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'shared/analytics/app_analytics.dart';
import 'shared/api/api_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  final analytics = await AppAnalytics.initialize();
  runApp(
    ProviderScope(
      overrides: [analyticsProvider.overrideWithValue(analytics)],
      child: const KandoApp(),
    ),
  );
}
