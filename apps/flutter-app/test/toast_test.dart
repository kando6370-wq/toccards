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

  test('Toast builder uses a short floating SnackBar', () {
    final snackBar = buildKandoToast('Saved');

    expect(snackBar.content, isA<Text>());
    expect((snackBar.content as Text).data, 'Saved');
    expect(snackBar.duration, kandoToastDuration);
    expect(snackBar.behavior, SnackBarBehavior.floating);
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
}
