import 'package:subscription_core/subscription_core.dart';

import '../../shared/analytics/analytics_events.dart';
import '../../shared/analytics/app_analytics.dart';
import 'subscription_entitlement_cache.dart';

class SubscriptionProductAnalytics {
  const SubscriptionProductAnalytics({
    required this.sku,
    required this.currency,
    required this.price,
  });

  final String sku;
  final String currency;
  final double price;
}

class SubscriptionPurchaseAnalyticsContext {
  const SubscriptionPurchaseAnalyticsContext({
    required this.product,
    required this.scene,
  });

  final SubscriptionProductAnalytics product;
  final String scene;

  Map<String, Object?> get resultProperties => {
    AnalyticsProperty.plan: product.sku,
    AnalyticsProperty.currency: product.currency,
    AnalyticsProperty.price: product.price,
  };
}

String subscriptionAnalyticsScene({
  String? source,
  String? entrySource,
  String? explicitScene,
}) {
  if (explicitScene != null && _subscriptionScenes.contains(explicitScene)) {
    return explicitScene;
  }
  if (source == 'onboarding') return AnalyticsValue.sceneGuide;
  if (entrySource == 'top_subscription_entry') {
    return AnalyticsValue.sceneIcon;
  }
  if (entrySource == 'profile_banner') return AnalyticsValue.sceneBanner;
  if (entrySource == 'scan_pro_card') return AnalyticsValue.sceneScanTip;
  return AnalyticsValue.sceneUsual;
}

const _subscriptionScenes = {
  AnalyticsValue.sceneGuide,
  AnalyticsValue.sceneUsual,
  AnalyticsValue.sceneIcon,
  AnalyticsValue.sceneBanner,
  AnalyticsValue.sceneTimeRange,
  AnalyticsValue.sceneHomePerformance,
  AnalyticsValue.sceneCardDetailPerformance,
  AnalyticsValue.sceneScanTip,
  AnalyticsValue.sceneScanTimes,
  AnalyticsValue.sceneScanWaiting,
};

void trackSubscriptionView(AppAnalytics analytics, String scene) {
  analytics.track(
    AnalyticsEvent.subscribeView,
    properties: {AnalyticsProperty.scene: scene},
  );
}

void trackSubscriptionClick(
  AppAnalytics analytics,
  SubscriptionPurchaseAnalyticsContext context,
) {
  analytics.track(
    AnalyticsEvent.subClick,
    properties: {
      ...context.resultProperties,
      AnalyticsProperty.scene: context.scene,
    },
  );
}

void trackSubscriptionResult(
  AppAnalytics analytics,
  SubscriptionPurchaseAnalyticsContext context,
  String result,
) {
  analytics.track(
    AnalyticsEvent.subResult,
    properties: {
      AnalyticsProperty.results: result,
      ...context.resultProperties,
    },
  );
}

bool trackVerifiedSubscriptionSuccess(
  AppAnalytics analytics,
  SubscriptionPurchaseAnalyticsContext context,
  SubscriptionEvent event,
) {
  final purchase = event.purchase;
  if (purchase == null ||
      purchase.store != SubscriptionStore.appStore ||
      purchase.status != SubscriptionPurchaseStatus.purchased ||
      event.entitlement?.isActive != true ||
      event.failure != null ||
      purchase.storeProductId != context.product.sku) {
    return false;
  }
  final payload = decodeStoreKitJwsPayload(purchase.verificationData);
  final productId = payload?['productId'];
  final originalId = payload?['originalTransactionId'];
  final price = payload?['price'];
  final currency = payload?['currency'];
  if (productId != purchase.storeProductId ||
      originalId is! String ||
      originalId.trim().isEmpty ||
      price is! num ||
      !price.isFinite ||
      price < 0 ||
      currency is! String ||
      !RegExp(r'^[A-Za-z]{3}$').hasMatch(currency)) {
    return false;
  }
  analytics.track(
    AnalyticsEvent.subSuccess,
    properties: {
      AnalyticsProperty.plan: productId,
      AnalyticsProperty.currency: currency.toUpperCase(),
      AnalyticsProperty.price: price.toDouble() / 1000,
      AnalyticsProperty.originalId: originalId,
      AnalyticsProperty.scene: context.scene,
    },
  );
  return true;
}

void trackRestoreResult(AppAnalytics analytics, String result) {
  analytics.track(
    AnalyticsEvent.restoreResult,
    properties: {AnalyticsProperty.results: result},
  );
}
