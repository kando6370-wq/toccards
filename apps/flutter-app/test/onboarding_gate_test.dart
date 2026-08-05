import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app_startup_preloader.dart';
import 'package:kando_app/features/onboarding/onboarding_controller.dart';
import 'package:kando_app/features/onboarding/onboarding_gate.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';

void main() {
  testWidgets('iOS launch logo keeps the same responsive center and size', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    try {
      const viewports = [Size(390, 844), Size(430, 932), Size(768, 1024)];
      tester.view.physicalSize = viewports.first;
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

      for (final viewport in viewports) {
        tester.view.physicalSize = viewport;
        await tester.pump();
        final logo = find.byKey(const ValueKey('onboarding-loading-logo'));
        expect(tester.getSize(logo), const Size(63, 77));
        expect(tester.getCenter(logo).dx, closeTo(viewport.width / 2, .01));
        expect(
          tester.getCenter(logo).dy,
          closeTo(viewport.height * 311 / 844, .01),
        );
      }

      await tester.pump(OnboardingController.minimumSplashDuration);
      await tester.pump();
      await tester.pump(OnboardingController.progressCompletionDuration);
      await tester.pump(OnboardingController.completedProgressHoldDuration);
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android launch logo stays centered at the native splash size', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    try {
      const viewports = [Size(390, 844), Size(430, 932), Size(768, 1024)];
      tester.view.physicalSize = viewports.first;
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

      for (final viewport in viewports) {
        tester.view.physicalSize = viewport;
        await tester.pump();
        final logo = find.byKey(const ValueKey('onboarding-loading-logo'));
        expect(tester.getSize(logo), const Size.square(90));
        expect(tester.getCenter(logo).dx, closeTo(viewport.width / 2, .01));
        expect(tester.getCenter(logo).dy, closeTo(viewport.height / 2, .01));
      }

      await tester.pump(OnboardingController.minimumSplashDuration);
      await tester.pump();
      await tester.pump(OnboardingController.progressCompletionDuration);
      await tester.pump(OnboardingController.completedProgressHoldDuration);
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('cold-start branding remains visible for at least 3 seconds', (
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
    final partialWidth = tester
        .getSize(find.byKey(const ValueKey('onboarding-loading-progress-fill')))
        .width;
    expect(partialWidth, greaterThan(0));
    expect(partialWidth, lessThan(232));

    await tester.pump(const Duration(milliseconds: 1999));
    expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
    expect(find.text('Home ready'), findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('onboarding-loading-branding'))),
      const Rect.fromLTWH(137, 366, 116, 160),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('onboarding-loading-progress'))),
      const Rect.fromLTWH(55, 706, 280, 35),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('onboarding-loading-progress-track')),
      ),
      const Size(232, 3),
    );

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
    await tester.pump(OnboardingController.progressCompletionDuration);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('onboarding-loading-progress-fill')),
          )
          .width,
      closeTo(232, .1),
    );
    await tester.pump(OnboardingController.completedProgressHoldDuration);
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
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(OnboardingController.progressCompletionDuration);
      await tester.pump(OnboardingController.completedProgressHoldDuration);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('onboarding-loading')), findsNothing);
      expect(find.text('Home ready'), findsOneWidget);
    },
  );

  testWidgets(
    'startup branding waits for preloading after 3 seconds and stays below 100 percent',
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

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
      expect(find.text('Home ready'), findsNothing);
      final trackWidth = tester
          .getSize(
            find.byKey(const ValueKey('onboarding-loading-progress-track')),
          )
          .width;
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('onboarding-loading-progress-fill')),
            )
            .width,
        closeTo(trackWidth * .99, .1),
      );

      preload.complete();
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(OnboardingController.progressCompletionDuration);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('onboarding-loading-progress-fill')),
            )
            .width,
        closeTo(trackWidth, .1),
      );
      await tester.pump(OnboardingController.completedProgressHoldDuration);
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
