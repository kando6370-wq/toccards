import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/portfolio/portfolio_api_client.dart';
import '../subscription/subscription_controller.dart';

final homeEntitlementRepairProvider = Provider<Future<bool> Function()>((ref) {
  return ref
      .read(subscriptionControllerProvider.notifier)
      .synchronizeServerEntitlement;
});

bool isEntitlementSyncRequired(Object error) {
  return error is PortfolioApiException &&
      error.statusCode == 409 &&
      error.code == 'ENTITLEMENT_SYNC_REQUIRED';
}
