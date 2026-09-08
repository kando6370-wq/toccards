import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_gate.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';

void main() {
  testWidgets(
    'the update gate uses fixed Figma copy so legacy backend release notes cannot alter the approved prompt',
    (tester) async {
      await tester.pumpWidget(
        _upgradeTestApp(
          repository: const _FakeAppUpgradeRepository(
            AppUpgradeConfig(
              upgradePrompt: UpgradePrompt(
                latestVersion: '1.0.1',
                forceUpdate: false,
                title: 'Legacy update title',
                message: 'Legacy release notes',
                storeUrl: 'https://apps.apple.com/app/kando',
              ),
            ),
          ),
          versionReader: const _FakeInstalledVersionReader('1.0.0'),
          launcher: _FakeAppStoreLauncher(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Update Now'), findsOneWidget);
      expect(find.text('New update available! Tap to upgrade'), findsOneWidget);
      expect(find.text('INSTALL'), findsOneWidget);
      expect(find.text('LATER'), findsOneWidget);
      expect(find.text('Legacy release notes'), findsNothing);
    },
  );

  const mandatoryConfig = AppUpgradeConfig(
    upgradePrompt: UpgradePrompt(
      latestVersion: '1.0.1',
      minVersion: '1.0.1',
      forceUpdate: true,
      title: 'Update available',
      message: 'Update to continue.',
      storeUrl: 'https://apps.apple.com/app/kando',
    ),
  );

  testWidgets(
    'the initial request blocks business actions before a version decision arrives',
    (tester) async {
      var actions = 0;
      final pending = Completer<AppUpgradeConfig>();
      final repository = _MutableUpgradeRepository()..pending = pending;
      await tester.pumpWidget(
        _upgradeTestApp(
          repository: repository,
          versionReader: const _FakeInstalledVersionReader('1.0.0'),
          launcher: _FakeAppStoreLauncher(),
          onUseApp: () => actions++,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Home'), warnIfMissed: false);
      expect(actions, 0);
      pending.complete(mandatoryConfig);
      await tester.pumpAndSettle();
      expect(find.text('Update Now'), findsOneWidget);
    },
  );

  testWidgets(
    'failed startup checks must block interaction until a successful retry establishes support',
    (tester) async {
      final repository = _MutableUpgradeRepository()..fail = true;
      await tester.pumpWidget(
        _upgradeTestApp(
          repository: repository,
          versionReader: const _FakeInstalledVersionReader('1.0.0'),
          launcher: _FakeAppStoreLauncher(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('REFRESH'), findsOneWidget);
      repository.fail = false;
      final retry = Completer<AppUpgradeConfig>();
      repository.pending = retry;
      await tester.tap(find.text('REFRESH'));
      await tester.pump();
      expect(find.text('REFRESH'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      retry.complete(const AppUpgradeConfig());
      await tester.pumpAndSettle();
      expect(repository.calls, 2);
      expect(find.text('REFRESH'), findsNothing);
    },
  );

  testWidgets(
    'foreground refresh must apply a new mandatory rule after an optional prompt was dismissed',
    (tester) async {
      final repository = _MutableUpgradeRepository()
        ..config = const AppUpgradeConfig(
          upgradePrompt: UpgradePrompt(
            latestVersion: '1.0.1',
            minVersion: '1.0.0',
            forceUpdate: true,
            title: 'Update available',
            message: 'A new version is available.',
            storeUrl: 'https://apps.apple.com/app/kando',
          ),
        );
      await tester.pumpWidget(
        _upgradeTestApp(
          repository: repository,
          versionReader: const _FakeInstalledVersionReader('1.0.0'),
          launcher: _FakeAppStoreLauncher(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('LATER'));
      await tester.pumpAndSettle();
      repository.config = mandatoryConfig;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repository.calls, 2);
      expect(find.text('Update Now'), findsOneWidget);
      expect(find.text('LATER'), findsNothing);
    },
  );

  testWidgets(
    'store return and failed rechecks retain enforcement until the installed version becomes supported',
    (tester) async {
      var actions = 0;
      final repository = _MutableUpgradeRepository()..config = mandatoryConfig;
      final versionReader = _MutableInstalledVersionReader('1.0.0');
      final launcher = _FakeAppStoreLauncher();
      await tester.pumpWidget(
        _upgradeTestApp(
          repository: repository,
          versionReader: versionReader,
          launcher: launcher,
          onUseApp: () => actions++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('INSTALL'));
      await tester.pumpAndSettle();
      expect(launcher.openedUrls, ['https://apps.apple.com/app/kando']);
      repository.fail = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repository.calls, 2);
      expect(find.text('Update Now'), findsOneWidget);
      await tester.tap(find.text('Home'), warnIfMissed: false);
      expect(actions, 0);

      repository.fail = false;
      versionReader.version = '1.0.1';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repository.calls, 3);
      expect(find.text('Update Now'), findsNothing);
      await tester.tap(find.text('Home'));
      expect(actions, 1);
    },
  );

  testWidgets(
    'store launch failures offer another attempt while keeping mandatory updates blocking',
    (tester) async {
      final launcher = _FakeAppStoreLauncher()..fail = true;
      await tester.pumpWidget(
        _upgradeTestApp(
          repository: const _FakeAppUpgradeRepository(mandatoryConfig),
          versionReader: const _FakeInstalledVersionReader('1.0.0'),
          launcher: launcher,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('INSTALL'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to open the store. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('LATER'), findsNothing);
      launcher.fail = false;
      await tester.tap(find.text('INSTALL'));
      await tester.pumpAndSettle();
      expect(launcher.openedUrls, hasLength(2));
      expect(find.text('Update Now'), findsOneWidget);
    },
  );

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
      expect(find.text('Update Now'), findsOneWidget);
      expect(find.text('New update available! Tap to upgrade'), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Update Now'), findsOneWidget);

      await tester.tap(find.text('INSTALL'));
      await tester.pumpAndSettle();

      expect(launcher.openedUrls, ['https://apps.apple.com/app/kando']);
      expect(find.text('Update Now'), findsOneWidget);
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

      expect(find.text('Update Now'), findsOneWidget);

      await tester.tap(find.text('LATER'));
      await tester.pumpAndSettle();

      expect(find.text('Update Now'), findsNothing);
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
      expect(find.text('Update Now'), findsNothing);
    },
  );
}

Widget _upgradeTestApp({
  required AppUpgradeRepository repository,
  required InstalledVersionReader versionReader,
  required AppStoreLauncher launcher,
  VoidCallback? onUseApp,
}) {
  return ProviderScope(
    overrides: [
      appUpgradeRepositoryProvider.overrideWithValue(repository),
      installedVersionReaderProvider.overrideWithValue(versionReader),
      appStoreLauncherProvider.overrideWithValue(launcher),
    ],
    child: MaterialApp(
      home: AppUpgradeGate(
        child: Scaffold(
          body: TextButton(
            onPressed: onUseApp ?? () {},
            child: const Text('Home'),
          ),
        ),
      ),
    ),
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
  bool fail = false;

  @override
  Future<void> open(String url) async {
    openedUrls.add(url);
    if (fail) throw StateError('Store unavailable');
  }
}

class _MutableUpgradeRepository implements AppUpgradeRepository {
  AppUpgradeConfig config = const AppUpgradeConfig();
  bool fail = false;
  int calls = 0;
  Completer<AppUpgradeConfig>? pending;

  @override
  Future<AppUpgradeConfig> loadConfig() async {
    calls++;
    if (fail) throw StateError('Version service unavailable');
    return pending?.future ?? config;
  }
}

class _MutableInstalledVersionReader implements InstalledVersionReader {
  _MutableInstalledVersionReader(this.version);
  String version;
  @override
  Future<String> currentVersion() async => version;
}
