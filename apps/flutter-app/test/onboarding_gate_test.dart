import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app_startup_preloader.dart';
import 'package:kando_app/features/onboarding/onboarding_gate.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';

void main() {
  testWidgets('cold-start branding remains visible for at least 2 seconds', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupPreloaderProvider.overrideWith((ref) async {}),
          onboardingRepositoryProvider.overrideWithValue(
            const _ImmediateOnboardingRepository(completed: true),
          ),
        ],
        child: const MaterialApp(
          home: OnboardingGate(home: Text('Home ready')),
        ),
      ),
    );

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('onboarding-loading-progress-fill')),
          )
          .width,
      0,
    );

    await tester.pump(const Duration(milliseconds: 1000));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('onboarding-loading-progress-fill')),
          )
          .width,
      closeTo(116, 0.1),
    );

    await tester.pump(const Duration(milliseconds: 999));
    expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
    expect(find.text('Home ready'), findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('onboarding-loading-branding'))),
      const Rect.fromLTWH(137, 255, 116, 160),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('onboarding-loading-progress'))),
      const Rect.fromLTWH(55, 707, 280, 34),
    );

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(find.byKey(const ValueKey('onboarding-loading')), findsNothing);
    expect(find.text('Home ready'), findsOneWidget);
  });

  testWidgets(
    'startup branding stays visible while first-launch state is unresolved because Home must not flash',
    (tester) async {
      final repository = _PendingOnboardingRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStartupPreloaderProvider.overrideWith((ref) async {}),
            onboardingRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: OnboardingGate(home: Text('Home ready')),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
      expect(find.text('Card AI'), findsOneWidget);
      expect(find.text('LOADING YOUR COLLECTION...'), findsOneWidget);
      expect(find.text('Home ready'), findsNothing);

      repository.readResult.complete(true);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('onboarding-loading')), findsNothing);
      expect(find.text('Home ready'), findsOneWidget);
    },
  );

  testWidgets(
    'startup branding waits for main-tab preloading after 2 seconds',
    (tester) async {
      final preload = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStartupPreloaderProvider.overrideWith((ref) => preload.future),
            onboardingRepositoryProvider.overrideWithValue(
              const _ImmediateOnboardingRepository(completed: true),
            ),
          ],
          child: const MaterialApp(
            home: OnboardingGate(home: Text('Home ready')),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
      expect(find.text('Home ready'), findsNothing);

      preload.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-loading')), findsNothing);
      expect(find.text('Home ready'), findsOneWidget);
    },
  );
}

class _ImmediateOnboardingRepository implements OnboardingRepository {
  const _ImmediateOnboardingRepository({required this.completed});

  final bool completed;

  @override
  Future<bool> readCompleted() async => completed;

  @override
  Future<void> markCompleted() async {}
}

class _PendingOnboardingRepository implements OnboardingRepository {
  final readResult = Completer<bool>();

  @override
  Future<bool> readCompleted() => readResult.future;

  @override
  Future<void> markCompleted() async {}
}
