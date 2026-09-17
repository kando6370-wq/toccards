import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  testWidgets('failure card shows the shared copy and invokes refresh', (
    tester,
  ) async {
    var refreshCount = 0;
    final events = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(
            AppAnalytics.recording((event, properties) => events.add(event)),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: KandoFailureBlock(onRefresh: () => refreshCount += 1),
          ),
        ),
      ),
    );

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(BackdropFilter)).width, 260);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(refreshText));
    await tester.pump();

    expect(refreshCount, 1);
    expect(events, [AnalyticsEvent.refreshClick]);
  });

  testWidgets('failure card remains usable in compact space', (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 190,
                height: 170,
                child: KandoFailureBlock(onRefresh: () => refreshCount += 1),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(BackdropFilter)).width, 190);
    expect(tester.getSize(find.byType(BackdropFilter)).height, lessThan(170));
    await tester.tap(find.text(refreshText));
    await tester.pump();
    expect(refreshCount, 1);
    expect(tester.takeException(), isNull);
  });
}
