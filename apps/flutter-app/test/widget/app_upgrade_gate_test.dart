import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_gate.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';

void main() {
  testWidgets(
    'forced upgrade dialog blocks dismissal because unsupported app versions must not continue',
    (tester) async {
      final launcher = _FakeAppStoreLauncher();

      await tester.pumpWidget(
        _upgradeTestApp(
          repository: const _FakeAppUpgradeRepository(
            AppUpgradeConfig(
              upgradePrompt: UpgradePrompt(
                latestVersion: '1.0.1',
                forceUpdate: true,
                title: 'Update required',
                message: 'Please install the latest Kando build.',
                storeUrl: 'https://apps.apple.com/app/kando',
              ),
              appStoreUrl: 'https://apps.apple.com/app/kando',
            ),
          ),
          versionReader: const _FakeInstalledVersionReader('1.0.0+1'),
          launcher: launcher,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Update required'), findsOneWidget);
      expect(
        find.text('Please install the latest Kando build.'),
        findsOneWidget,
      );

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Update required'), findsOneWidget);

      await tester.tap(find.text('Update Now'));
      await tester.pumpAndSettle();

      expect(launcher.openedUrls, ['https://apps.apple.com/app/kando']);
      expect(find.text('Update required'), findsOneWidget);
    },
  );

  testWidgets(
    'optional upgrade dialog can be dismissed because operations did not require this release',
    (tester) async {
      await tester.pumpWidget(
        _upgradeTestApp(
          repository: const _FakeAppUpgradeRepository(
            AppUpgradeConfig(
              upgradePrompt: UpgradePrompt(
                latestVersion: '1.0.1',
                forceUpdate: false,
                title: 'Update available',
                message: 'Please install the latest Kando build.',
                storeUrl: 'https://apps.apple.com/app/kando',
              ),
              appStoreUrl: 'https://apps.apple.com/app/kando',
            ),
          ),
          versionReader: const _FakeInstalledVersionReader('1.0.0+1'),
          launcher: _FakeAppStoreLauncher(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets(
    'matching app version continues without prompt because users already meet the minimum',
    (tester) async {
      await tester.pumpWidget(
        _upgradeTestApp(
          repository: const _FakeAppUpgradeRepository(
            AppUpgradeConfig(
              upgradePrompt: UpgradePrompt(
                latestVersion: '1.0.1',
                forceUpdate: true,
                title: 'Update required',
                message: 'Please install the latest Kando build.',
                storeUrl: 'https://apps.apple.com/app/kando',
              ),
              appStoreUrl: 'https://apps.apple.com/app/kando',
            ),
          ),
          versionReader: const _FakeInstalledVersionReader('1.0.1+1'),
          launcher: _FakeAppStoreLauncher(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Update required'), findsNothing);
    },
  );
}

Widget _upgradeTestApp({
  required AppUpgradeRepository repository,
  required InstalledVersionReader versionReader,
  required AppStoreLauncher launcher,
}) {
  return ProviderScope(
    overrides: [
      appUpgradeRepositoryProvider.overrideWithValue(repository),
      installedVersionReaderProvider.overrideWithValue(versionReader),
      appStoreLauncherProvider.overrideWithValue(launcher),
    ],
    child: const MaterialApp(home: AppUpgradeGate(child: Text('Home'))),
  );
}

class _FakeAppUpgradeRepository implements AppUpgradeRepository {
  const _FakeAppUpgradeRepository(this.config);

  final AppUpgradeConfig config;

  @override
  Future<AppUpgradeConfig> loadConfig() async => config;
}

class _FakeInstalledVersionReader implements InstalledVersionReader {
  const _FakeInstalledVersionReader(this.version);

  final String version;

  @override
  Future<String> currentVersion() async => version;
}

class _FakeAppStoreLauncher implements AppStoreLauncher {
  final openedUrls = <String>[];

  @override
  Future<void> open(String url) async {
    openedUrls.add(url);
  }
}
