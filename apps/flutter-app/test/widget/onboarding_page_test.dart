import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/onboarding/onboarding_gate.dart';
import 'package:kando_app/features/onboarding/onboarding_page.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/in_memory_onboarding_storage.dart';
import '../support/local_placeholder_auth_repository.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Fraunces',
    )..addFont(rootBundle.load('assets/fonts/Fraunces-Variable.ttf'))).load();
  });

  test('app body typography uses the platform default family', () {
    expect(buildKandoTheme().textTheme.bodyMedium?.fontFamily, 'Roboto');
  });

  testWidgets(
    'first launch starts on the scan guide with its Lottie animation',
    (tester) async {
      await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));

      expect(find.byKey(const ValueKey('onboarding-guides')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-guide-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-media-placeholder-0')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('onboarding-lottie-0')), findsOneWidget);
      expect(
        _placeholderAsset(tester, 0),
        'assets/onboarding/guide_scan_placeholder.png',
      );
      expect(find.text('Instantly Scan Cards'), findsOneWidget);
      expect(find.byTooltip("LET'S START"), findsOneWidget);
      expect(find.byTooltip('Skip and start now'), findsNothing);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('onboarding-page-indicator-0')),
        ),
        const Size(16, 6),
      );
      expect(
        find.byKey(const ValueKey('onboarding-page-indicator-3')),
        findsNothing,
      );
    },
  );

  testWidgets('guide actions advance through both Lotties and the video', (
    tester,
  ) async {
    await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));

    await tester.tap(find.byTooltip("LET'S START"));
    await _finishPageTransition(tester);

    expect(find.text('Track Card Values'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-media-placeholder-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('onboarding-lottie-1')), findsOneWidget);
    expect(
      _placeholderAsset(tester, 1),
      'assets/onboarding/guide_values_placeholder.png',
    );

    await tester.tap(find.byTooltip('NEXT'));
    await _finishPageTransition(tester);

    expect(find.text('Personalized Wishlist'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-media-placeholder-2')),
      findsOneWidget,
    );
    expect(
      _placeholderAsset(tester, 2),
      'assets/onboarding/guide_wishlist_placeholder.png',
    );
    expect(
      find.byKey(const ValueKey('onboarding-media-first-frame-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('onboarding-video-2')), findsOneWidget);
    expect(find.byTooltip('SIGN UP/SIGN IN'), findsOneWidget);
    expect(find.byTooltip('Skip and start now'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-page-indicator-2')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('onboarding-page-indicator-2'))),
      const Size(16, 6),
    );
    expect(
      find.byKey(const ValueKey('onboarding-page-indicator-3')),
      findsNothing,
    );
  });

  testWidgets(
    'guide layout stays usable at reference and compact phone sizes',
    (tester) async {
      addTearDown(tester.view.reset);
      for (final size in [const Size(390, 844), const Size(320, 700)]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;

        await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));
        await _advanceToFinalGuide(tester);

        expect(tester.takeException(), isNull, reason: 'viewport: $size');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('guide media starts below the top safe area', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(left: 19, top: 47, right: 23);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));

    final media = find.descendant(
      of: find.byKey(const ValueKey('onboarding-media-placeholder-0')),
      matching: find.byType(Image),
    );
    expect(tester.getTopLeft(media), const Offset(0, 47));
  });

  testWidgets('page swipes pause media until the destination page settles', (
    tester,
  ) async {
    await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));

    expect(_lottieIsAnimating(tester, 0), isTrue);
    final pageView = find.byKey(const ValueKey('onboarding-page-view'));
    final gesture = await tester.startGesture(tester.getCenter(pageView));
    await gesture.moveBy(Offset(-tester.getSize(pageView).width * 0.7, 0));
    await tester.pump();
    await tester.pump();

    expect(_lottieIsAnimating(tester, 0), isFalse);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Track Card Values'), findsOneWidget);
    expect(_lottieIsAnimating(tester, 1), isTrue);
  });

  testWidgets('reduced-motion devices keep the video first-frame fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testPage(InMemoryOnboardingStorage(), disableAnimations: true),
    );
    await _advanceToFinalGuide(tester);

    expect(
      find.byKey(const ValueKey('onboarding-media-first-frame-2')),
      findsOneWidget,
    );
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets(
    'first-launch gate keeps Home hidden until onboarding completes',
    (tester) async {
      await tester.pumpWidget(_testGate(InMemoryOnboardingStorage()));
      await _finishStartup(tester);

      expect(find.byKey(const ValueKey('onboarding-guides')), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    },
  );

  testWidgets(
    'final guide exposes both account choices to assistive technology',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));
      await _advanceToFinalGuide(tester);

      expect(find.bySemanticsLabel('SIGN UP/SIGN IN'), findsWidgets);
      expect(find.bySemanticsLabel('Skip and start now'), findsWidgets);
      semanticsHandle.dispose();
    },
  );

  testWidgets('guest choice persists completion before Home is revealed', (
    tester,
  ) async {
    final storage = InMemoryOnboardingStorage();
    await tester.pumpWidget(_testGate(storage));
    await _finishStartup(tester);
    await _advanceToFinalGuide(tester);

    expect(await storage.readCompleted(), isFalse);

    await tester.tap(find.byTooltip('Skip and start now'));
    await tester.pumpAndSettle();

    expect(await storage.readCompleted(), isTrue);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('final primary action opens the existing account provider flow', (
    tester,
  ) async {
    await tester.pumpWidget(_testPage(InMemoryOnboardingStorage()));
    await _advanceToFinalGuide(tester);

    await tester.tap(find.byTooltip('SIGN UP/SIGN IN'));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Email'), findsOneWidget);
    expect(find.byKey(const Key('auth-google-icon')), findsOneWidget);
    expect(find.byKey(const Key('auth-apple-icon')), findsOneWidget);
    expect(find.byKey(const Key('auth-email-icon')), findsOneWidget);
  });

  testWidgets('completed users bypass the first-launch guides', (tester) async {
    await tester.pumpWidget(
      _testGate(InMemoryOnboardingStorage(completed: true)),
    );
    await _finishStartup(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-guides')), findsNothing);
  });
}

Future<void> _advanceToFinalGuide(WidgetTester tester) async {
  await tester.tap(find.byTooltip("LET'S START"));
  await _finishPageTransition(tester);
  await tester.tap(find.byTooltip('NEXT'));
  await _finishPageTransition(tester);
}

Future<void> _finishPageTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _finishStartup(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump();
}

String _placeholderAsset(WidgetTester tester, int index) {
  final image = tester.widget<Image>(
    find.descendant(
      of: find.byKey(ValueKey('onboarding-media-placeholder-$index')),
      matching: find.byType(Image),
    ),
  );
  return (image.image as AssetImage).assetName;
}

bool _lottieIsAnimating(WidgetTester tester, int index) {
  final lottie = tester.widget<LottieBuilder>(
    find.descendant(
      of: find.byKey(ValueKey('onboarding-lottie-$index')),
      matching: find.byType(LottieBuilder),
    ),
  );
  return lottie.animate ?? true;
}

Widget _testPage(
  InMemoryOnboardingStorage storage, {
  bool disableAnimations = false,
}) {
  final page = disableAnimations
      ? const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: OnboardingPage(),
        )
      : const OnboardingPage();
  return ProviderScope(
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(
        LocalOnboardingRepository(storage),
      ),
      authDeviceIdProvider.overrideWithValue('onboarding-test-device'),
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(InMemoryAuthStorage()),
      ),
    ],
    child: MaterialApp(theme: buildKandoTheme(), home: page),
  );
}

Widget _testGate(InMemoryOnboardingStorage storage) {
  return ProviderScope(
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(
        LocalOnboardingRepository(storage),
      ),
      authDeviceIdProvider.overrideWithValue('onboarding-test-device'),
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
