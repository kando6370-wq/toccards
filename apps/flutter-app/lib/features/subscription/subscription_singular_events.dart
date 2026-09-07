import 'package:subscription_core/subscription_core.dart';

import '../../shared/api/api_environment.dart';

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

  final suffix = environment == AppEnvironment.test ? 'test' : '';
  return switch (event.entitlement!.planId) {
    'weekly' => 'weekly_card$suffix',
    'yearly' => 'yearly_card$suffix',
    'lifetime' => 'lifetime_card$suffix',
    _ => null,
  };
}
