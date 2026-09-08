import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/app/app.dart';
import 'package:kando_app/app/app_startup_preloader.dart';
import 'package:kando_app/app/router.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'KandoApp blocks unsupported versions on $platform because update enforcement must work above the real router',
      (tester) async {
        var actions = 0;
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => actions++,
                  child: const Text('Use App'),
                ),
              ),
            ),
            GoRoute(
              path: '/other',
              builder: (context, state) =>
                  const Scaffold(body: Text('Other page')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStartupPreloaderProvider.overrideWith((ref) async {}),
              authControllerProvider.overrideWith(_IdleAuthController.new),
              appRouterProvider.overrideWithValue(router),
              appUpgradeRepositoryProvider.overrideWithValue(
                const _MandatoryUpgradeRepository(),
              ),
              installedVersionReaderProvider.overrideWithValue(
                const _OldInstalledVersion(),
              ),
            ],
            child: const KandoApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Update Now'), findsOneWidget);
        expect(find.text('LATER'), findsNothing);
        await tester.tap(find.text('Use App'), warnIfMissed: false);
        await tester.tapAt(Offset.zero);
        await tester.binding.handlePopRoute();
        router.go('/other');
        await tester.pumpAndSettle();
        expect(actions, 0);
        expect(find.text('Update Now'), findsOneWidget);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
}

class _IdleAuthController extends AuthController {
  @override
  AuthState build() => const AuthState.loading();
}

class _MandatoryUpgradeRepository implements AppUpgradeRepository {
  const _MandatoryUpgradeRepository();
  @override
  Future<AppUpgradeConfig> loadConfig() async => const AppUpgradeConfig(
    upgradePrompt: UpgradePrompt(
      latestVersion: '1.0.1',
      minVersion: '1.0.1',
      forceUpdate: true,
      title: 'Update available',
      message: 'Please install the latest version.',
      forcedMessage: 'Please update to continue.',
      storeUrl: 'https://apps.apple.com/app/id6793017224',
    ),
  );
}

class _OldInstalledVersion implements InstalledVersionReader {
  const _OldInstalledVersion();
  @override
  Future<String> currentVersion() async => '1.0.0+124';
}
