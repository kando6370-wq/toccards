import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';

void main() {
  testWidgets('top toast shows each state with its distinct icon and color', (
    tester,
  ) async {
    const styles = <KandoTopToastType, (IconData, Color)>{
      KandoTopToastType.failure: (
        Icons.priority_high_rounded,
        KandoColors.errorText,
      ),
      KandoTopToastType.network: (
        Icons.wifi_off_rounded,
        KandoColors.mutedText,
      ),
      KandoTopToastType.success: (Icons.check_rounded, KandoColors.gain),
      KandoTopToastType.warning: (
        Icons.priority_high_rounded,
        KandoColors.money,
      ),
      KandoTopToastType.info: (Icons.info_outline_rounded, KandoColors.accent),
    };

    for (final entry in styles.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KandoTopToast(message: entry.key.name, type: entry.key),
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(entry.value.$1));
      expect(icon.color, entry.value.$2);
      expect(find.text(entry.key.name), findsOneWidget);
    }
  });

  testWidgets('top toast replaces an existing message and closes on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showKandoTopToast(
                  context,
                  message: 'First',
                  type: KandoTopToastType.failure,
                );
                showKandoTopToast(
                  context,
                  message: 'Second',
                  type: KandoTopToastType.success,
                );
              },
              child: const Text('Show top toast'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show top toast'));
    await tester.pump();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('kando-top-toast'))).dy,
      kandoTopToastTopGap,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
  });

  testWidgets('top toast dismisses on upward swipe and after its duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKandoTopToast(
                context,
                message: 'Temporary',
                type: KandoTopToastType.warning,
                duration: const Duration(milliseconds: 500),
              ),
              child: const Text('Show warning'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show warning'));
    await tester.pump();
    await tester.fling(
      find.byKey(const Key('kando-top-toast')),
      const Offset(0, -160),
      800,
    );
    await tester.pump();
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);

    await tester.tap(find.text('Show warning'));
    await tester.pump();
    expect(find.text('Temporary'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
  });

  testWidgets('common failure and network helpers use top feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showKandoTopFailureToast(context),
                  child: const Text('Failure'),
                ),
                TextButton(
                  onPressed: () => showKandoTopNetworkToast(context),
                  child: const Text('Network'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Failure'));
    await tester.pump();
    expect(find.text(genericFailureToastText), findsOneWidget);
    await tester.tap(find.text('Network'));
    await tester.pump();
    expect(find.text(genericFailureToastText), findsNothing);
    expect(find.text(networkFailureToastText), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
  });
}
