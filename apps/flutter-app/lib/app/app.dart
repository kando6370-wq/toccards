import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/app_upgrade/app_upgrade_gate.dart';
import 'app_startup_preloader.dart';
import 'router.dart';
import 'theme.dart';

class KandoApp extends ConsumerWidget {
  const KandoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appStartupPreloaderProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Card AI',
      debugShowCheckedModeBanner: false,
      theme: buildKandoTheme(),
      routerConfig: router,
      builder: (context, child) {
        return AppUpgradeGate(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
