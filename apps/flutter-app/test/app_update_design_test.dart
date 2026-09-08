import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/kando_modal.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

void main() {
  for (final forced in [false, true]) {
    testWidgets(
      'Figma update modal keeps install reachable and ${forced ? 'removes' : 'offers'} defer action',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var installed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: KandoUpdateModal(
                title: 'Update Now',
                message: 'New update available! Tap to upgrade',
                primaryLabel: 'INSTALL',
                secondaryLabel: 'LATER',
                forceUpdate: forced,
                onPrimary: () => installed = true,
                onSecondary: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final frame = tester.getRect(
          find.byKey(const Key('kando-modal-frame')),
        );
        expect(frame.width, 342);
        expect(frame.height, closeTo(forced ? 396.267 : 452.267, 0.01));
        final image = find.byKey(const Key('kando-update-rocket'));
        expect(image, findsOneWidget);
        expect(tester.getSize(image), const Size(160, 158.267));
        expect(tester.getTopLeft(image).dy - frame.top, closeTo(43, 0.001));
        final title = tester.widget<Text>(find.text('Update Now'));
        expect(title.style?.fontSize, 24);
        expect(title.style?.color, KandoColors.accent);
        expect(find.text('LATER'), forced ? findsNothing : findsOneWidget);
        await tester.tap(find.text('INSTALL'));
        expect(installed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
