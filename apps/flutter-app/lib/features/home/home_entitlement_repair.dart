import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/portfolio/portfolio_api_client.dart';
import '../subscription/subscription_controller.dart';

final homeEntitlementRepairProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    final result = await ref
        .read(subscriptionControllerProvider.notifier)
        .reconcileServerEntitlement();
    return result == EntitlementReconciliationResult.premiumSynchronized;
  };
});

bool isEntitlementSyncRequired(Object error) {
  return error is PortfolioApiException &&
      error.statusCode == 409 &&
      error.code == 'ENTITLEMENT_SYNC_REQUIRED';
}
