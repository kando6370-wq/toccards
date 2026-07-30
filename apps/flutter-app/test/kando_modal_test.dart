import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/kando_modal.dart';

void main() {
  testWidgets('danger confirm modal renders Figma-sized shell and returns true', (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  confirmed = await showKandoDangerConfirmModal(
                    context,
                    title: 'Delete all cards ?',
                    message:
                        'This action will permanently delete all these cards and cannot be undone',
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kando-modal-frame')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('kando-modal-frame'))).width,
      342,
    );
    expect(find.text('Delete all cards ?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('update modal hides secondary action when forced', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showKandoUpdateModal(
                    context,
                    title: 'Update Now',
                    message: 'New update available! Tap to upgrade',
                    forceUpdate: true,
                  );
                },
                child: const Text('Upgrade'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();

    expect(find.text('Update Now'), findsNWidgets(2));
    expect(find.text('Later'), findsNothing);
  });
}
