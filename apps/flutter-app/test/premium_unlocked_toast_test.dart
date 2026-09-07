import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/premium_unlocked_toast.dart';

void main() {
  testWidgets('Premium unlocked toast matches the Figma visual contract', (
    tester,
  ) async {
    tester.view.padding = FakeViewPadding(
      top: 24 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPremiumUnlockedToast(context),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    final toast = find.byKey(const Key('premium-unlocked-toast'));
    expect(toast, findsOneWidget);
    expect(tester.getSize(toast), const Size(201, 48));
    expect(tester.getTopLeft(toast).dy, 24 + premiumUnlockedToastTopGap);

    final clip = tester.widget<ClipRRect>(
      find.byKey(const Key('premium-unlocked-toast-clip')),
    );
    expect(clip.borderRadius, BorderRadius.circular(12));

    final surface = tester.widget<ColoredBox>(
      find.byKey(const Key('premium-unlocked-toast-surface')),
    );
    expect(surface.color, const Color(0xCC4D4F36));
    expect(
      find.byKey(const Key('premium-unlocked-toast-icon')),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(SvgPicture)), const Size(32, 32));

    final text = tester.widget<Text>(find.text(premiumUnlockedToastText));
    expect(text.style?.color, KandoColors.mutedText);
    expect(text.style?.fontSize, 14);
    expect(text.style?.height, 20 / 14);
    expect(text.style?.letterSpacing, 0);
    expect(text.style?.decoration, TextDecoration.none);

    await tester.pump(premiumUnlockedToastDuration);
    expect(toast, findsNothing);
  });

  testWidgets('a new Premium unlocked toast replaces the active instance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showPremiumUnlockedToast(context);
                showPremiumUnlockedToast(context);
              },
              child: const Text('Show twice'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show twice'));
    await tester.pump();

    expect(find.byKey(const Key('premium-unlocked-toast')), findsOneWidget);

    await tester.pump(premiumUnlockedToastDuration);
  });
}
