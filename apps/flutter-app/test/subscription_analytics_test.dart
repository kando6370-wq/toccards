import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/subscription/subscription_analytics.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  test('subscription entry context maps to the spreadsheet Scene values', () {
    expect(
      subscriptionAnalyticsScene(source: 'onboarding'),
      AnalyticsValue.sceneGuide,
    );
    expect(
      subscriptionAnalyticsScene(source: 'cold_start'),
      AnalyticsValue.sceneUsual,
    );
    expect(
      subscriptionAnalyticsScene(entrySource: 'top_subscription_entry'),
      AnalyticsValue.sceneIcon,
    );
    expect(
      subscriptionAnalyticsScene(entrySource: 'profile_banner'),
      AnalyticsValue.sceneBanner,
    );
    expect(
      subscriptionAnalyticsScene(entrySource: 'scan_pro_card'),
      AnalyticsValue.sceneScanTip,
    );
    expect(
      subscriptionAnalyticsScene(
        explicitScene: AnalyticsValue.sceneScanWaiting,
      ),
      AnalyticsValue.sceneScanWaiting,
    );
    expect(
      subscriptionAnalyticsScene(explicitScene: 'unsupported'),
      AnalyticsValue.sceneUsual,
    );
  });

  test('verified Apple purchase reports trusted subscription properties', () {
    final events = <(String, Map<String, Object?>)>[];
    final analytics = AppAnalytics.recording(
      (event, properties) => events.add((event, properties)),
    );
    const context = SubscriptionPurchaseAnalyticsContext(
      product: SubscriptionProductAnalytics(
        sku: 'com.kando.yearly',
        currency: 'USD',
        price: 49.99,
      ),
      scene: AnalyticsValue.sceneGuide,
    );
    final event = SubscriptionEvent(
      purchase: SubscriptionPurchase(
        store: SubscriptionStore.appStore,
        storeProductId: 'com.kando.yearly',
        status: SubscriptionPurchaseStatus.purchased,
        verificationData: _jws({
          'productId': 'com.kando.yearly',
          'originalTransactionId': 'original-123',
          'price': 49990,
          'currency': 'usd',
        }),
      ),
      entitlement: const SubscriptionEntitlement(
        planId: 'yearly',
        entitlementId: 'performance_pro',
        status: SubscriptionEntitlementStatus.active,
      ),
    );

    expect(trackVerifiedSubscriptionSuccess(analytics, context, event), isTrue);
    expect(events.single.$1, AnalyticsEvent.subSuccess);
    expect(
      events.single.$2,
      allOf(
        containsPair(AnalyticsProperty.plan, 'com.kando.yearly'),
        containsPair(AnalyticsProperty.currency, 'USD'),
        containsPair(AnalyticsProperty.price, 49.99),
        containsPair(AnalyticsProperty.originalId, 'original-123'),
        containsPair(AnalyticsProperty.scene, AnalyticsValue.sceneGuide),
      ),
    );
  });

  test('malformed Apple evidence never reports subscription success', () {
    final events = <String>[];
    final analytics = AppAnalytics.recording((event, _) => events.add(event));
    const context = SubscriptionPurchaseAnalyticsContext(
      product: SubscriptionProductAnalytics(
        sku: 'com.kando.yearly',
        currency: 'USD',
        price: 49.99,
      ),
      scene: AnalyticsValue.sceneUsual,
    );
    const event = SubscriptionEvent(
      purchase: SubscriptionPurchase(
        store: SubscriptionStore.appStore,
        storeProductId: 'com.kando.yearly',
        status: SubscriptionPurchaseStatus.purchased,
        verificationData: 'invalid',
      ),
      entitlement: SubscriptionEntitlement(
        planId: 'yearly',
        entitlementId: 'performance_pro',
        status: SubscriptionEntitlementStatus.active,
      ),
    );

    expect(
      trackVerifiedSubscriptionSuccess(analytics, context, event),
      isFalse,
    );
    expect(events, isEmpty);
  });

  test('purchase and restore results preserve exact result properties', () {
    final events = <(String, Map<String, Object?>)>[];
    final analytics = AppAnalytics.recording(
      (event, properties) => events.add((event, properties)),
    );
    const context = SubscriptionPurchaseAnalyticsContext(
      product: SubscriptionProductAnalytics(
        sku: 'com.kando.weekly',
        currency: 'CAD',
        price: 5.49,
      ),
      scene: AnalyticsValue.sceneUsual,
    );

    trackSubscriptionResult(analytics, context, AnalyticsValue.resultCancel);
    trackRestoreResult(analytics, AnalyticsValue.resultNotFound);

    expect(events[0].$1, AnalyticsEvent.subResult);
    expect(events[0].$2, containsPair(AnalyticsProperty.results, 'cancel'));
    expect(
      events[0].$2,
      containsPair(AnalyticsProperty.plan, 'com.kando.weekly'),
    );
    expect(events[0].$2, containsPair(AnalyticsProperty.currency, 'CAD'));
    expect(events[0].$2, containsPair(AnalyticsProperty.price, 5.49));
    expect(events[1].$1, AnalyticsEvent.restoreResult);
    expect(events[1].$2, containsPair(AnalyticsProperty.results, 'notFound'));
  });
}

String _jws(Map<String, Object?> payload) {
  final body = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'header.$body.signature';
}
