import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:kando_app/features/onboarding/onboarding_page.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';

void main() {
  testWidgets('first launch keeps the splash visible for at least 1.2 seconds', (
    tester,
  ) async {
    await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));

    expect(find.byKey(const ValueKey('onboarding-splash')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1199));
    expect(find.byKey(const ValueKey('onboarding-splash')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-guide-0')), findsOneWidget);
  });

  testWidgets('guide skip requires an explicit anonymous entry decision', (
    tester,
  ) async {
    final storage = InMemoryOnboardingStorage();
    await tester.pumpWidget(_testPage(storage));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('onboarding-entry')), findsOneWidget);
    expect(storage.readCompleted(), isFalse);

    await tester.tap(find.text('Skip and start now'));
    await tester.pumpAndSettle();
    expect(storage.readCompleted(), isTrue);
  });

  testWidgets('onboarding renders configured app config slides', (
    tester,
  ) async {
    final storage = InMemoryOnboardingStorage();
    final repository = LocalOnboardingRepository(
      storage,
      slides: const [
        OnboardingSlide(
          imageUrl: 'https://example.com/onboarding-collection.png',
          title: 'Configured collection',
          body: 'A configured first slide.',
        ),
        OnboardingSlide(
          imageUrl: 'https://example.com/onboarding-market.png',
          title: 'Configured market',
          body: 'A configured second slide.',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: OnboardingPage()),
      ),
    );

    expect(find.text('Configured collection'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-image-0')), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Configured market'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-image-1')), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(storage.readCompleted(), isTrue);
  });
}

Widget _testPage(InMemoryOnboardingStorage storage) {
  return ProviderScope(
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(
        LocalOnboardingRepository(storage),
      ),
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(InMemoryAuthStorage()),
      ),
    ],
    child: const MaterialApp(home: OnboardingPage()),
  );
}
