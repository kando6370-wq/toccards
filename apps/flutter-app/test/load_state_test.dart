import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  test('global load state copy matches PRD fallback text', () {
    expect(noContentAvailableText, 'No content available');
    expect(refreshText, 'REFRESH');
  });

  testWidgets('loading block uses the shared progress indicator', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: KandoLoadingBlock()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('failure block shows fallback copy and refresh action', (
    tester,
  ) async {
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(home: KandoFailureBlock(onRefresh: () => refreshCount += 1)),
    );

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);

    await tester.tap(find.text(refreshText));
    await tester.pump();

    expect(refreshCount, 1);
  });

  testWidgets('empty block renders successful empty state copy and action', (
    tester,
  ) async {
    var actionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: KandoEmptyBlock(
          title: 'No cards in this portfolio yet.',
          body: 'Scan or search cards to start tracking your collection.',
          primaryLabel: 'Search Cards',
          onPrimary: () => actionCount += 1,
        ),
      ),
    );

    expect(find.text('No cards in this portfolio yet.'), findsOneWidget);
    expect(
      find.text('Scan or search cards to start tracking your collection.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Search Cards'));
    await tester.pump();

    expect(actionCount, 1);
  });
}
