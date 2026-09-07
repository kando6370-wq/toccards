import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../shared/analytics/app_analytics.dart';
import '../shared/debug/app_debug_overlay.dart';
import 'router.dart';
import 'theme.dart';

class KandoApp extends ConsumerWidget {
  const KandoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final authState = ref.watch(authControllerProvider);
    final session = authState.session;
    if (!authState.isLoading) {
      ref
          .read(analyticsProvider)
          .updateIdentity(
            uid: session?.userId ?? session?.anonymousId,
            isUser: session?.isUser ?? false,
          );
    }

    return MaterialApp.router(
      title: 'App Skeleton',
      debugShowCheckedModeBanner: false,
      theme: buildKandoTheme(),
      routerConfig: router,
      builder: (context, child) {
        ref
            .read(analyticsProvider)
            .updateDeviceType(
              MediaQuery.sizeOf(context),
              Theme.of(context).platform,
            );
        return buildAppDebugOverlay(child ?? const SizedBox.shrink());
      },
    );
  }
}
