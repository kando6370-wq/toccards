import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

void main() {
  test(
    'all custom events wait for identity and receive the restored uid',
    () async {
      final mixpanel = _RecordingMixpanel();
      final analytics = AppAnalytics.initializingForTest(
        Future.value(mixpanel),
      );

      for (final event in AnalyticsEvent.all) {
        analytics.track(event);
      }
      await pumpEventQueue();

      expect(mixpanel.operations, isEmpty);

      analytics.updateIdentity(uid: '100028', isUser: true);
      await pumpEventQueue();

      expect(mixpanel.operations.first, 'identify:100028');
      expect(
        mixpanel.operations.skip(1).map((operation) => operation.substring(6)),
        unorderedEquals(AnalyticsEvent.all),
      );
      expect(mixpanel.properties, hasLength(AnalyticsEvent.all.length));
      expect(
        mixpanel.properties,
        everyElement(containsPair(AnalyticsProperty.uid, '100028')),
      );
    },
  );

  test('initial events use the restored anonymous id as uid', () async {
    final mixpanel = _RecordingMixpanel();
    final analytics = AppAnalytics.initializingForTest(Future.value(mixpanel));

    analytics.track(AnalyticsEvent.splashView);
    await pumpEventQueue();
    analytics.updateIdentity(uid: 'anonymous-123', isUser: false);
    await pumpEventQueue();

    expect(mixpanel.operations, ['track:${AnalyticsEvent.splashView}']);
    expect(
      mixpanel.properties.single,
      containsPair(AnalyticsProperty.uid, 'anonymous-123'),
    );
  });

  test(
    'initial events are released with an empty uid after auth failure',
    () async {
      final mixpanel = _RecordingMixpanel();
      final analytics = AppAnalytics.initializingForTest(
        Future.value(mixpanel),
      );

      analytics.track(AnalyticsEvent.splashView);
      await pumpEventQueue();
      analytics.updateIdentity(uid: null, isUser: false);
      await pumpEventQueue();

      expect(mixpanel.operations, ['track:${AnalyticsEvent.splashView}']);
      expect(
        mixpanel.properties.single,
        containsPair(AnalyticsProperty.uid, ''),
      );
    },
  );

  test(
    'non-blocking initialization restores identity and flushes queued events',
    () async {
      final initialization = Completer<Mixpanel?>();
      final mixpanel = _RecordingMixpanel();

      final analytics = AppAnalytics.initializingForTest(initialization.future);
      analytics.updateIdentity(uid: 'user-123', isUser: true);
      analytics.track(
        AnalyticsEvent.subscribeView,
        properties: {AnalyticsProperty.scene: AnalyticsValue.sceneGuide},
      );

      expect(mixpanel.operations, isEmpty);

      initialization.complete(mixpanel);
      await pumpEventQueue();

      expect(mixpanel.operations, [
        'identify:user-123',
        'track:${AnalyticsEvent.subscribeView}',
      ]);
      expect(
        mixpanel.properties.single,
        containsPair(AnalyticsProperty.scene, AnalyticsValue.sceneGuide),
      );
    },
  );
}

class _RecordingMixpanel extends Mixpanel {
  _RecordingMixpanel() : super('test-token');

  final operations = <String>[];
  final properties = <Map<String, dynamic>>[];

  @override
  Future<void> identify(String distinctId) async {
    operations.add('identify:$distinctId');
  }

  @override
  Future<void> track(
    String eventName, {
    Map<String, dynamic>? properties,
  }) async {
    operations.add('track:$eventName');
    this.properties.add(Map<String, dynamic>.of(properties ?? const {}));
  }
}
