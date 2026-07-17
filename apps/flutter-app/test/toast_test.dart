import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/toast.dart';

void main() {
  test('global Toast copy matches PRD text', () {
    expect(genericFailureToastText, 'Something went wrong. Please try again.');
    expect(
      networkFailureToastText,
      'No internet connection. Please check your network and try again.',
    );
  });

  test('Toast builder uses the Figma floating toast shell', () {
    final snackBar = buildKandoToast('Saved');

    expect(snackBar.content, isA<KandoFloatingToast>());
    expect(snackBar.duration, kandoToastDuration);
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.width, 350);
  });

  testWidgets('failure Toast renders generic failure copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showKandoFailureToast(context),
                child: const Text('Show failure'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show failure'));
    await tester.pump();

    expect(find.text(genericFailureToastText), findsOneWidget);
    expect(find.byKey(const Key('kando-floating-toast')), findsOneWidget);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, kandoToastDuration);
    expect(snackBar.behavior, SnackBarBehavior.floating);
  });

  testWidgets('new Toast replaces the current message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showKandoToast(context, message: 'First');
                  showKandoToast(context, message: 'Second');
                },
                child: const Text('Show twice'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show twice'));
    await tester.pump();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('top Toast renders near the top safe area by type', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showKandoTopToast(
                  context,
                  message: networkFailureToastText,
                  type: KandoTopToastType.network,
                ),
                child: const Text('Show top toast'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show top toast'));
    await tester.pump();

    expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
    expect(find.text(networkFailureToastText), findsOneWidget);
    final messageText = tester.widget<Text>(find.text(networkFailureToastText));
    expect(messageText.maxLines, 2);
    expect(messageText.overflow, TextOverflow.ellipsis);
    expect(
      tester.getTopLeft(find.byKey(const Key('kando-top-toast'))).dy,
      kandoTopToastTopGap,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
  });

  testWidgets('top Toast replaces current message and closes manually', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showKandoTopToast(
                    context,
                    message: 'First top',
                    type: KandoTopToastType.failure,
                  );
                  showKandoTopToast(
                    context,
                    message: 'Second top',
                    type: KandoTopToastType.success,
                  );
                },
                child: const Text('Show top twice'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show top twice'));
    await tester.pump();

    expect(find.text('First top'), findsNothing);
    expect(find.text('Second top'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
  });

  testWidgets('top Toast dismisses when swiped upward', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showKandoTopToast(
                  context,
                  message: 'Swipe me away',
                  type: KandoTopToastType.warning,
                ),
                child: const Text('Show swipe toast'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show swipe toast'));
    await tester.pump();

    expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);

    await tester.fling(
      find.byKey(const Key('kando-top-toast')),
      const Offset(0, -160),
      800,
    );
    await tester.pump();

    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
  });
}
