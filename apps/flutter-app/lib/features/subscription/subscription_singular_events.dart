import 'package:subscription_core/subscription_core.dart';

import '../../shared/api/api_environment.dart';
import '../../shared/attribution/app_attribution.dart';
import 'subscription_revenue_reporter.dart';

String? singularSubscriptionSuccessEventName({
  required SubscriptionEvent event,
  required AppEnvironment environment,
  required bool isFreshPurchase,
}) {
  if (!isFreshPurchase ||
      event.purchase?.status != SubscriptionPurchaseStatus.purchased ||
      event.failure != null ||
      event.entitlement?.isActive != true) {
    return null;
  }

  return _eventName(event.entitlement!.planId, environment);
}

String? _eventName(String planId, AppEnvironment environment) {
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
  }) {
    if (singularSubscriptionSuccessEventName(
              event: event,
              environment: _environment,
              isFreshPurchase: isFreshPurchase,
            ) ==
            null ||
        event.plan?.id != event.entitlement?.planId) {
      return Future.value();
    }
    return _reporter.enqueueVerifiedPurchase(event);
  }

  Future<void> flush() => _reporter.flush();
}

class _SingularRevenueSink implements SubscriptionRevenueSink {
  const _SingularRevenueSink(this.attribution, this.environment);

  final AppAttributionEventReporter attribution;
  final AppEnvironment environment;

  @override
  Future<void> report(SubscriptionRevenueRecord record) {
    final eventName = _eventName(record.planType, environment);
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
