import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:kando_app/features/onboarding/onboarding_gate.dart';
import 'package:kando_app/features/onboarding/onboarding_page.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';
import 'package:kando_app/app/theme.dart';

void main() {
  test('app body typography uses the Figma Geist family', () {
    expect(buildKandoTheme().textTheme.bodyMedium?.fontFamily, 'Geist');
  });

  testWidgets(
    'first launch shows the Figma account decision immediately so users are not diverted through an unapproved guide',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));
      await tester.pump();

      expect(find.byKey(const ValueKey('onboarding-entry')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('figma-onboarding-entry-canvas')),
        findsOneWidget,
      );
      expect(find.byTooltip('Sign In / Sign Up'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsNothing);
      expect(find.byTooltip('Skip and start now'), findsOneWidget);
      expect(find.text('Track your collection'), findsNothing);
      expect(find.text('Build your collection'), findsNothing);
      expect(find.text('Sign In / Sign Up'), findsNothing);
      expect(find.text('Skip and start now'), findsNothing);

      final primaryButton = find.byTooltip('Sign In / Sign Up');
      expect(tester.getSize(primaryButton), const Size(350, 56));
    },
  );

  testWidgets('390x844 rendering stays aligned with the approved Figma pass', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));
    await tester.pump();

    await expectLater(
      find.byKey(const ValueKey('onboarding-entry')),
      matchesGoldenFile(
        'goldens/rendered/figma_onboarding_entry_183_8754_390x844.png',
      ),
    );
  });

  testWidgets(
    'missing guide configuration still requires the Figma account decision because first-launch access must be explicit',
    (tester) async {
      final storage = InMemoryOnboardingStorage();
      final repository = LocalOnboardingRepository(storage, slides: const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingRepositoryProvider.overrideWithValue(repository),
            authRepositoryProvider.overrideWithValue(
              LocalPlaceholderAuthRepository(InMemoryAuthStorage()),
            ),
          ],
          child: const MaterialApp(home: OnboardingGate(home: Text('Home'))),
        ),
      );

      expect(find.byKey(const ValueKey('onboarding-entry')), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    },
  );

  testWidgets(
    'Figma entry keeps sign-in and guest choices available to assistive technology',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));
      await tester.pump();

      expect(find.bySemanticsLabel('Sign In / Sign Up'), findsOneWidget);
      expect(find.bySemanticsLabel('Skip and start now'), findsOneWidget);
      semanticsHandle.dispose();
    },
  );

  testWidgets('guest choice persists completion before Home is revealed', (
    tester,
  ) async {
    final storage = InMemoryOnboardingStorage();
    await tester.pumpWidget(_testGate(storage));

    expect(find.byKey(const ValueKey('onboarding-entry')), findsOneWidget);
    expect(storage.readCompleted(), isFalse);

    await tester.tap(find.byTooltip('Skip and start now'));
    await tester.pumpAndSettle();

    expect(storage.readCompleted(), isTrue);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('primary action opens the existing account provider flow', (
    tester,
  ) async {
    await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));

    await tester.tap(find.byTooltip('Sign In / Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Email'), findsOneWidget);
    expect(find.byKey(const Key('auth-google-icon')), findsOneWidget);
    expect(find.byKey(const Key('auth-apple-icon')), findsOneWidget);
    expect(find.byKey(const Key('auth-email-icon')), findsOneWidget);
  });

  testWidgets('completed users bypass the first-launch decision', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testGate(InMemoryOnboardingStorage(completed: true)),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-entry')), findsNothing);
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
    child: MaterialApp(theme: buildKandoTheme(), home: const OnboardingPage()),
  );
}

Widget _testGate(InMemoryOnboardingStorage storage) {
  return ProviderScope(
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(
        LocalOnboardingRepository(storage),
      ),
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(InMemoryAuthStorage()),
      ),
    ],
    child: MaterialApp(
      theme: buildKandoTheme(),
      home: const OnboardingGate(home: Text('Home')),
    ),
  );
}
