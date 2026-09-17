import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/kando_modal.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

void main() {
  Future<void> openUpdate(
    WidgetTester tester, {
    bool forceUpdate = false,
    void Function(KandoUpdateModalResult?)? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showKandoUpdateModal(
                  context,
                  title: 'Update Now',
                  message: 'New update available! Tap to upgrade',
                  forceUpdate: forceUpdate,
                );
                onResult?.call(result);
              },
              child: const Text('Upgrade'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
  }

  testWidgets('optional update shows the illustration and returns later', (
    tester,
  ) async {
    KandoUpdateModalResult? result;
    await openUpdate(tester, onResult: (value) => result = value);

    final frame = tester.getRect(find.byKey(const Key('kando-modal-frame')));
    expect(frame.width, 342);
    expect(frame.height, closeTo(452.267, 0.01));
    expect(find.byKey(const Key('kando-update-rocket')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('kando-update-rocket'))),
      const Size(160, 158.267),
    );
    expect(find.text('Update Now'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Update Now')).style?.color,
      KandoColors.accent,
    );
    expect(
      tester.widget<Text>(find.text('Update Now')).style?.fontFamily,
      isNull,
    );
    expect(find.text('INSTALL'), findsOneWidget);
    expect(find.text('LATER'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('LATER'));
    await tester.pumpAndSettle();
    expect(result, KandoUpdateModalResult.later);
    expect(find.byKey(const Key('kando-modal-frame')), findsNothing);
  });

  testWidgets('optional update returns install or null on barrier dismissal', (
    tester,
  ) async {
    final results = <KandoUpdateModalResult?>[];
    await openUpdate(tester, onResult: results.add);
    await tester.tap(find.text('INSTALL'));
    await tester.pumpAndSettle();
    expect(results, [KandoUpdateModalResult.updateNow]);

    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(results, [KandoUpdateModalResult.updateNow, null]);
  });

  testWidgets(
    'forced update blocks barrier and back, and only install closes',
    (tester) async {
      KandoUpdateModalResult? result;
      await openUpdate(
        tester,
        forceUpdate: true,
        onResult: (value) => result = value,
      );

      expect(
        tester.getSize(find.byKey(const Key('kando-modal-frame'))).height,
        closeTo(396.267, 0.01),
      );
      expect(find.text('LATER'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kando-modal-frame')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kando-modal-frame')), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.text('INSTALL'));
      await tester.pumpAndSettle();
      expect(result, KandoUpdateModalResult.updateNow);
    },
  );

  testWidgets(
    'long copy scrolls while install stays reachable on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var installCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: KandoUpdateModal(
                title: 'Update required',
                message: 'Please install the latest version to continue. ' * 8,
                primaryLabel: 'INSTALL',
                secondaryLabel: 'LATER',
                forceUpdate: true,
                onPrimary: () => installCount++,
                onSecondary: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final frame = tester.getRect(find.byKey(const Key('kando-modal-frame')));
      expect(frame.width, 272);
      expect(frame.left, greaterThanOrEqualTo(24));
      expect(frame.right, lessThanOrEqualTo(296));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('INSTALL')).bottom, lessThan(568));
      await tester.tap(find.text('INSTALL'));
      expect(installCount, 1);
    },
  );
}
