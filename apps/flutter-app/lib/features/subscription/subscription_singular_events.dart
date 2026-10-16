import 'package:subscription_core/subscription_core.dart';

import '../../shared/api/api_environment.dart';
import '../../shared/attribution/app_attribution.dart';
import 'subscription_revenue_reporter.dart';

String? singularSubscriptionSuccessEventName({
  required SubscriptionEvent event,
  required AppEnvironment environment,
  required bool isFreshPurchase,
  String? eventName,
}) {
  if (!isFreshPurchase ||
      event.purchase?.status != SubscriptionPurchaseStatus.purchased ||
      event.failure != null ||
      event.entitlement?.isActive != true) {
    return null;
  }

  return eventName ??
      _eventName(
        event.entitlement!.planId,
        environment,
        productId: event.purchase!.storeProductId,
      );
}

String? _eventName(
  String planId,
  AppEnvironment environment, {
  required String productId,
}) {
  if (environment == AppEnvironment.test) {
    switch (productId) {
      case 'weekly.trial':
        return 'card_weekly_trialtest';
      case 'yearly.pro':
        return 'yearly_cardtest';
    }
  }
  final suffix = environment == AppEnvironment.test ? 'test' : '';
  return switch (planId) {
    'weekly' => 'weekly_card$suffix',
    'yearly' => 'yearly_card$suffix',
    'lifetime' => 'lifetime_card$suffix',
    _ => null,
  };
}

class SingularSubscriptionRevenueReporter {
  SingularSubscriptionRevenueReporter({
    required AppEnvironment environment,
    required AppAttributionEventReporter attribution,
  }) : _environment = environment,
       _reporter = SubscriptionRevenueReporter(
         storage: PreferencesSubscriptionRevenueStorage(
           keyPrefix: 'subscription.singular_revenue.${environment.name}',
         ),
         sink: _SingularRevenueSink(attribution, environment),
       );

  final AppEnvironment _environment;
  final SubscriptionRevenueReporter _reporter;

  Future<void> enqueueVerifiedPurchase(
    SubscriptionEvent event, {
    required bool isFreshPurchase,
    String? eventName,
  }) {
    if (singularSubscriptionSuccessEventName(
              event: event,
              environment: _environment,
              isFreshPurchase: isFreshPurchase,
              eventName: eventName,
            ) ==
            null ||
        event.plan?.id != event.entitlement?.planId) {
      return Future.value();
    }
    return _reporter.enqueueVerifiedPurchase(
      event,
      singularEventName: eventName,
    );
  }

  Future<void> flush() => _reporter.flush();
}

class _SingularRevenueSink implements SubscriptionRevenueSink {
  const _SingularRevenueSink(this.attribution, this.environment);

  final AppAttributionEventReporter attribution;
  final AppEnvironment environment;

  @override
  Future<void> report(SubscriptionRevenueRecord record) {
    final eventName =
        record.singularEventName ??
        _eventName(record.planType, environment, productId: record.productId);
    if (eventName == null) throw StateError('Unknown Singular revenue plan.');
    return attribution.trackRevenue(
      eventName: eventName,
      currency: record.currency,
      value: record.value,
      transactionId: record.transactionId,
      productId: record.productId,
    );
  }
}
