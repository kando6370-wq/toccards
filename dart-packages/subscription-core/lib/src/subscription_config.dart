enum SubscriptionStore { appStore, googlePlay }

class SubscriptionPlanConfig {
  SubscriptionPlanConfig({
    required this.id,
    required this.entitlementId,
    required Map<SubscriptionStore, String> productIds,
  }) : productIds = Map.unmodifiable(productIds) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (entitlementId.trim().isEmpty) {
      throw ArgumentError.value(
        entitlementId,
        'entitlementId',
        'must not be empty',
      );
    }
    for (final entry in productIds.entries) {
      if (entry.value.trim().isEmpty) {
        throw ArgumentError.value(
          entry.value,
          'productIds[${entry.key.name}]',
          'must not be empty',
        );
      }
    }
  }

  final String id;
  final String entitlementId;
  final Map<SubscriptionStore, String> productIds;

  String productIdFor(SubscriptionStore store) => productIds[store]!;
}

class SubscriptionConfig {
  SubscriptionConfig({
    required Set<SubscriptionStore> enabledStores,
    required List<SubscriptionPlanConfig> plans,
  }) : enabledStores = Set.unmodifiable(enabledStores),
       plans = List.unmodifiable(plans) {
    if (enabledStores.isEmpty) {
      throw ArgumentError.value(
        enabledStores,
        'enabledStores',
        'at least one store must be enabled',
      );
    }
    if (plans.isEmpty) {
      throw ArgumentError.value(plans, 'plans', 'must not be empty');
    }

    final planIds = <String>{};
    final productIds = <String>{};
    for (final plan in plans) {
      if (!planIds.add(plan.id)) {
        throw ArgumentError.value(plan.id, 'plans', 'duplicate plan id');
      }
      for (final store in enabledStores) {
        final productId = plan.productIds[store];
        if (productId == null) {
          throw ArgumentError.value(
            plan.productIds,
            'plans',
            'plan ${plan.id} has no product id for ${store.name}',
          );
        }
        if (!productIds.add('${store.name}:$productId')) {
          throw ArgumentError.value(
            productId,
            'plans',
            'duplicate product id for ${store.name}',
          );
        }
      }
    }
  }

  final Set<SubscriptionStore> enabledStores;
  final List<SubscriptionPlanConfig> plans;

  SubscriptionPlanConfig planById(String planId) =>
      plans.firstWhere((plan) => plan.id == planId);

  SubscriptionPlanConfig? planByProductId(
    SubscriptionStore store,
    String productId,
  ) {
    for (final plan in plans) {
      if (plan.productIds[store] == productId) {
        return plan;
      }
    }
    return null;
  }

  Set<String> productIdsFor(SubscriptionStore store) =>
      plans.map((plan) => plan.productIds[store]).whereType<String>().toSet();
}
