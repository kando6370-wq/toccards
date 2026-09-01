import 'dart:async';

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
                    confirmLabel: 'DELETE',
                    cancelLabel: 'CANCEL',
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
      tester.getSize(find.byKey(const Key('kando-modal-frame'))),
      const Size(342, 355),
    );
    expect(find.text('Delete all cards ?'), findsOneWidget);
    expect(
      find.byKey(const Key('kando-danger-modal-header-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('kando-danger-modal-delete-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('kando-danger-modal-background')),
      findsNothing,
    );
    final frame = tester.widget<Container>(
      find.byKey(const Key('kando-modal-frame')),
    );
    expect((frame.decoration! as BoxDecoration).color, const Color(0xFF1D1D1C));
    final headerIcon = tester.widget<Container>(
      find.byKey(const Key('kando-danger-modal-header-icon')),
    );
    expect((headerIcon.decoration! as BoxDecoration).border, isNull);
    expect(
      tester
          .getSize(
            find.text(
              'This action will permanently delete all these cards and cannot be undone',
            ),
          )
          .width,
      greaterThan(276),
    );
    expect(find.text('DELETE'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);

    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('danger confirm modal adapts to a 320px phone without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKandoDangerConfirmModal(
                context,
                title: 'Delete all cards ?',
                message:
                    'This action will permanently delete all these cards and cannot be undone',
                confirmLabel: 'DELETE',
                cancelLabel: 'CANCEL',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final frame = tester.getRect(find.byKey(const Key('kando-modal-frame')));
    expect(frame.width, 272);
    expect(frame.left, greaterThanOrEqualTo(24));
    expect(frame.right, lessThanOrEqualTo(296));
    expect(tester.takeException(), isNull);
    expect(find.text('DELETE'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
  });

  testWidgets('danger confirm modal waits for async action before closing', (
    tester,
  ) async {
    final action = Completer<bool>();
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmed = await showKandoDangerConfirmModal(
                  context,
                  title: 'Delete all cards ?',
                  message:
                      'This action will permanently delete all these cards and cannot be undone',
                  confirmLabel: 'DELETE',
                  cancelLabel: 'CANCEL',
                  confirmAction: () => action.future,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE'));
    await tester.pump();

    expect(find.byKey(const Key('kando-modal-frame')), findsOneWidget);
    expect(find.byKey(const Key('kando-danger-modal-loading')), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    expect(confirmed, isNull);

    action.complete(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kando-modal-frame')), findsNothing);
    expect(confirmed, isTrue);
  });

  testWidgets('danger confirm modal remains open when async action fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKandoDangerConfirmModal(
                context,
                title: 'Delete all cards ?',
                message:
                    'This action will permanently delete all these cards and cannot be undone',
                confirmLabel: 'DELETE',
                cancelLabel: 'CANCEL',
                confirmAction: () async => false,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kando-modal-frame')), findsOneWidget);
    expect(find.text('DELETE'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
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
