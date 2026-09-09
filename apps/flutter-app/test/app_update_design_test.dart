import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/kando_modal.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

void main() {
  for (final size in [
    const Size(342, 452.267),
    const Size(342, 396.267),
    const Size(272, 396.267),
  ]) {
    testWidgets('update background preserves Figma light falloff at $size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const boundaryKey = Key('update-background-capture');
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundaryKey,
            child: KandoModalFrame(
              width: size.width,
              height: size.height,
              update: true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final frame = tester.getRect(find.byKey(const Key('kando-modal-frame')));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          // Background samples from Figma 736:13370, relative to its
          // 342 x 452.267 frame; avoid illustration, text, buttons and edges.
          const samples = [
            (12, 16, [55, 56, 39]),
            (12, 60, [51, 52, 38]),
            (12, 120, [46, 47, 34]),
            (12, 200, [39, 39, 32]),
            (12, 300, [30, 30, 28]),
            (60, 16, [46, 48, 36]),
            (100, 16, [41, 42, 33]),
            (170, 16, [30, 30, 28]),
            (325, 220, [29, 29, 28]),
          ];
          for (final (x, y, expected) in samples) {
            final px = (frame.left + x / 342 * frame.width).round();
            final py = (frame.top + y / 452.267 * frame.height).round();
            final offset = (py * image.width + px) * 4;
            for (var channel = 0; channel < 3; channel++) {
              expect(
                pixels.getUint8(offset + channel),
                closeTo(expected[channel], 2),
                reason: 'Figma background ($x, $y), RGB channel $channel',
              );
            }
          }
        } finally {
          image.dispose();
        }
      });
    });
  }

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
