import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_gate.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';

const _optional = AppUpgradeConfig(
  upgradePrompt: UpgradePrompt(
    latestVersion: '1.0.2',
    minVersion: '1.0.0',
    forceUpdate: false,
    title: 'Update Now',
    message: 'New update available!',
    storeUrl: 'https://apps.apple.com/app/id6793017224',
  ),
);
const _mandatory = AppUpgradeConfig(
  upgradePrompt: UpgradePrompt(
    latestVersion: '1.0.2',
    minVersion: '1.0.2',
    forceUpdate: true,
    title: 'Update Now',
    message: 'New update available!',
    storeUrl: 'https://apps.apple.com/app/id6793017224',
  ),
);

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'Home resume keeps content interactive during recheck and failure on $platform',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.router.dispose);
        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();
        final pending = Completer<AppUpgradeConfig>();
        harness.repository.pending = pending;
        await _resume(tester);
        expect(harness.repository.calls, 2);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('Home action'));
        expect(harness.actions, 1);
        pending.completeError(StateError('Offline'));
        await tester.pumpAndSettle();
        expect(find.text('No content available'), findsNothing);
        await tester.tap(find.text('Home action'));
        expect(harness.actions, 2);
        harness.repository.pending = null;
        harness.repository.config = _mandatory;
        await _resume(tester);
        await tester.pumpAndSettle();
        expect(find.text('Update Now'), findsOneWidget);
        expect(find.text('LATER'), findsNothing);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  for (final replace in [false, true]) {
    testWidgets(
      'Details resume skips upgrade requests; returning Home rechecks (replace=$replace)',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.router.dispose);
        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();
        if (replace) {
          harness.router.go('/details');
        } else {
          unawaited(harness.router.push<void>('/details'));
        }
        await tester.pumpAndSettle();
        harness.repository.config = _optional;
        await _resume(tester);
        await tester.pumpAndSettle();
        expect(harness.repository.calls, 1);
        expect(find.text('Update Now'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('Details action'));
        expect(harness.actions, 1);
        if (replace) {
          harness.router.go('/');
        } else {
          harness.router.pop();
        }
        await tester.pumpAndSettle();
        expect(harness.repository.calls, 2);
        expect(find.text('Update Now'), findsOneWidget);
        await tester.tap(find.text('LATER'));
        harness.router.go('/details');
        await tester.pumpAndSettle();
        harness.router.go('/');
        await tester.pumpAndSettle();
        expect(find.text('Update Now'), findsNothing);
      },
    );
  }

  for (final config in [_optional, _mandatory]) {
    testWidgets(
      'A recheck completing after Home is covered defers its prompt (forced=${config.upgradePrompt!.forceUpdate})',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.router.dispose);
        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();
        final pending = Completer<AppUpgradeConfig>();
        harness.repository.pending = pending;
        await _resume(tester);
        unawaited(harness.router.push<void>('/details'));
        await tester.pumpAndSettle();
        pending.complete(config);
        await tester.pumpAndSettle();
        expect(find.text('Update Now'), findsNothing);
        await tester.tap(find.text('Details action'));
        expect(harness.actions, 1);
        harness.repository.pending = null;
        harness.repository.config = config;
        harness.router.pop();
        await tester.pumpAndSettle();
        expect(find.text('Update Now'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Optional prompt disappears when Home is covered without losing its dismissal state',
    (tester) async {
      final harness = _Harness();
      harness.repository.config = _optional;
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      expect(find.text('LATER'), findsOneWidget);
      unawaited(harness.router.push<void>('/details'));
      await tester.pumpAndSettle();
      expect(find.text('Update Now'), findsNothing);
      await tester.tap(find.text('Details action'));
      expect(harness.actions, 1);
      harness.router.pop();
      await tester.pumpAndSettle();
      expect(find.text('LATER'), findsOneWidget);
      await tester.tap(find.text('LATER'));
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Update Now'), findsNothing);
    },
  );

  testWidgets(
    'An initial pending check does not cover Details or duplicate requests when Home returns',
    (tester) async {
      final harness = _Harness();
      final pending = Completer<AppUpgradeConfig>();
      harness.repository.pending = pending;
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.app);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      unawaited(harness.router.push<void>('/details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _resume(tester);
      expect(harness.repository.calls, 1);
      harness.router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _resume(tester);
      expect(harness.repository.calls, 1);
      pending.complete(const AppUpgradeConfig());
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Home action'));
      expect(harness.actions, 1);
    },
  );

  testWidgets(
    'Known mandatory update stays global during failed recheck and clears only after successful verification',
    (tester) async {
      final harness = _Harness();
      harness.repository.config = _mandatory;
      addTearDown(harness.router.dispose);
      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      harness.router.go('/details');
      await tester.pumpAndSettle();
      final pending = Completer<AppUpgradeConfig>();
      harness.repository.pending = pending;
      await _resume(tester);
      expect(harness.repository.calls, 2);
      expect(find.text('Update Now'), findsOneWidget);
      pending.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Update Now'), findsOneWidget);
      await tester.tap(find.text('Details action'), warnIfMissed: false);
      expect(harness.actions, 0);
      harness.repository.pending = null;
      harness.repository.config = const AppUpgradeConfig();
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Update Now'), findsNothing);
      await tester.tap(find.text('Details action'));
      expect(harness.actions, 1);
    },
  );
}

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

class _Harness {
  final repository = _Repository();
  int actions = 0;
  late final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => AppUpgradeHomeEntry(child: _page('Home action')),
      ),
      GoRoute(path: '/details', builder: (_, _) => _page('Details action')),
    ],
  );

  Widget _page(String label) => Scaffold(
    body: TextButton(onPressed: () => actions++, child: Text(label)),
  );

  Widget get app => ProviderScope(
    overrides: [
      appUpgradeRepositoryProvider.overrideWithValue(repository),
      installedVersionReaderProvider.overrideWithValue(_Version()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppUpgradeGate(child: child!),
    ),
  );
}

class _Repository implements AppUpgradeRepository {
  int calls = 0;
  AppUpgradeConfig config = const AppUpgradeConfig();
  Completer<AppUpgradeConfig>? pending;

  @override
  Future<AppUpgradeConfig> loadConfig() async {
    calls++;
    return pending?.future ?? config;
  }
}

class _Version implements InstalledVersionReader {
  @override
  Future<String> currentVersion() async => '1.0.1';
}
