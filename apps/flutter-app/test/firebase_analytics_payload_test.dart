import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/firebase/firebase_analytics_payload.dart';

void main() {
  test('maps spreadsheet property names to Firebase-safe names', () {
    final parameters = firebaseAnalyticsParameters({
      AnalyticsProperty.operatingSystem: 'ios',
      AnalyticsProperty.appVersion: '1.2.3',
      AnalyticsProperty.checkDebug: true,
      AnalyticsProperty.subPlan: 'com.kando.yearly',
      AnalyticsProperty.scene: 'guide',
      AnalyticsProperty.plan: 'com.kando.yearly',
      AnalyticsProperty.currency: 'USD',
      AnalyticsProperty.price: 49.99,
      AnalyticsProperty.originalId: 'original-123',
      AnalyticsProperty.results: 'success',
      AnalyticsProperty.ipType: 'Pokemon',
      AnalyticsProperty.entrySource: 'scan',
    });

    expect(parameters, {
      'operating_system': 'ios',
      'app_version': '1.2.3',
      'check_debug': 1,
      'sub_plan': 'com.kando.yearly',
      'scene': 'guide',
      'plan': 'com.kando.yearly',
      'currency': 'USD',
      'price': 49.99,
      'original_id': 'original-123',
      'results': 'success',
      'ip_type': 'Pokemon',
      'entry_source': 'scan',
    });
  });

  test('normalizes future property names and supported value types', () {
    final parameters = firebaseAnalyticsParameters({
      '99 invalid property': false,
      'firebase_reserved': DateTime.utc(2026).toIso8601String(),
      'null_property': null,
    });

    expect(parameters['param_99_invalid_property'], 0);
    expect(parameters['custom_firebase_reserved'], '2026-01-01T00:00:00.000Z');
    expect(parameters, isNot(contains('null_property')));
  });

  test('truncates string parameters to the Firebase limit', () {
    final parameters = firebaseAnalyticsParameters({'long': 'x' * 101});

    expect((parameters['long']! as String).length, 100);
  });
}
