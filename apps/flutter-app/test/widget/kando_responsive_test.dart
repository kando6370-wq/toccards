import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/kando_responsive.dart';

void main() {
  testWidgets('resizing columns keeps an in-progress form mounted', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final controller = TextEditingController(text: 'Unsubmitted notes');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KandoAdaptiveColumns(
              primary: const SizedBox(key: Key('hero'), height: 240),
              secondary: TextField(
                key: const Key('draft'),
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
    final draftState = tester.state(find.byType(TextField));
    for (final size in [const Size(951, 669), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      await tester.pump();
      final hero = tester.getRect(find.byKey(const Key('hero')));
      final draft = tester.getRect(find.byKey(const Key('draft')));
      if (size.width > 760) {
        expect(draft.left, greaterThan(hero.right));
        expect(draft.top, hero.top);
      } else {
        expect(draft.top, greaterThan(hero.bottom));
      }
      expect(tester.state(find.byType(TextField)), same(draftState));
      expect(controller.text, 'Unsubmitted notes');
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(951, 669);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const Key('draft'))).dy,
      greaterThan(tester.getBottomRight(find.byKey(const Key('hero'))).dy),
      reason:
          'A short window should fall back to the scrollable single column.',
    );
  });
}
