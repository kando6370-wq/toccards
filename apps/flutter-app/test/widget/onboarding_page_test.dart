import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/onboarding/onboarding_page.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';

void main() {
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
