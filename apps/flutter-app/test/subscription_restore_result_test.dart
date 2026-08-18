import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/subscription_restore_result.dart';

void main() {
  const expectedHeights = {
    SubscriptionRestoreResultType.premiumRestored: 204.0,
    SubscriptionRestoreResultType.notFound: 230.0,
    SubscriptionRestoreResultType.failed: 260.0,
  };

  for (final entry in expectedHeights.entries) {
    testWidgets('${entry.key.name} uses its Figma maximum card size', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SubscriptionRestoreResultCard(
                type: entry.key,
                onAction: () {},
              ),
            ),
          ),
        ),
      );

      final card = find.byKey(
        Key('subscription-restore-${entry.key.name}-card'),
      );
      expect(tester.getSize(card), Size(260, entry.value));

      final clip = tester.widget<ClipRRect>(
        find.byKey(Key('subscription-restore-${entry.key.name}-clip')),
      );
      expect(clip.borderRadius, BorderRadius.circular(16));

      final surface = tester.widget<DecoratedBox>(
        find.byKey(Key('subscription-restore-${entry.key.name}-surface')),
      );
      final decoration = surface.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF292B22));
      expect(decoration.border, Border.all(color: Colors.white));
    });
  }

  testWidgets('restored content and original Figma icon match the contract', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SubscriptionRestoreResultCard(
              type: SubscriptionRestoreResultType.premiumRestored,
            ),
          ),
        ),
      ),
    );

    expect(find.text(premiumRestoredTitle), findsOneWidget);
    expect(find.text(premiumRestoredMessage), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const Key('subscription-restore-premiumRestored-icon')),
      ),
      const Size(56, 56),
    );

    final title = tester.widget<Text>(find.text(premiumRestoredTitle));
    expect(title.style?.color, KandoColors.accent);
    expect(title.style?.fontFamily, 'Fraunces');
    expect(title.style?.fontSize, 20);
    expect(title.style?.height, 26 / 20);

    final message = tester.widget<Text>(find.text(premiumRestoredMessage));
    expect(message.style?.color, KandoColors.mutedText);
    expect(message.style?.fontSize, 15);
    expect(message.style?.height, 22 / 15);
  });

  testWidgets('danger variants use their distinct original Figma icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SubscriptionRestoreResultCard(
                type: SubscriptionRestoreResultType.notFound,
              ),
              SubscriptionRestoreResultCard(
                type: SubscriptionRestoreResultType.failed,
                onAction: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(
        find.byKey(const Key('subscription-restore-notFound-icon')),
      ),
      const Size(26, 26),
    );
    expect(
      tester.getSize(find.byKey(const Key('subscription-restore-failed-icon'))),
      const Size(26, 26),
    );
    expect(find.byType(SvgPicture), findsNWidgets(2));
  });

  testWidgets('automatic centered results scale down but never scale up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSubscriptionRestoreResult(
                context,
                type: SubscriptionRestoreResultType.premiumRestored,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pump();

    final frame = find.byKey(
      const Key('subscription-restore-premiumRestored-frame'),
    );
    final size = tester.getSize(frame);
    expect(size.width, lessThanOrEqualTo(208));
    expect(size.height, lessThanOrEqualTo(188));
    expect(size.width / size.height, closeTo(260 / 204, 0.001));
    expect(tester.getCenter(frame), tester.getCenter(find.byType(Scaffold)));

    await tester.pump(subscriptionRestoreSuccessDuration);
    expect(frame, findsNothing);
  });

  testWidgets('not found result is centered instead of top aligned', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSubscriptionRestoreResult(
                context,
                type: SubscriptionRestoreResultType.notFound,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pump();

    final frame = find.byKey(const Key('subscription-restore-notFound-frame'));
    expect(tester.getCenter(frame), tester.getCenter(find.byType(Scaffold)));

    await tester.pump(subscriptionRestoreNotFoundDuration);
    expect(frame, findsNothing);
  });

  testWidgets('failed result is centered, capitalized, and waits for OK', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSubscriptionRestoreResult(
                context,
                type: SubscriptionRestoreResultType.failed,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text(restoreFailedTitle), findsOneWidget);
    expect(find.text(restoreFailedMessage), findsOneWidget);
    expect(
      find.text('something went wrong. Please try again later.'),
      findsNothing,
    );
    expect(find.text('OK'), findsOneWidget);
    expect(
      tester.getCenter(
        find.byKey(const Key('subscription-restore-failed-frame')),
      ),
      tester.getCenter(find.byType(Scaffold)),
    );

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(restoreFailedTitle), findsNothing);
  });
}
