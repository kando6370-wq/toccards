import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:subscription_core/subscription_core.dart';

import '../../shared/portfolio/portfolio_providers.dart';
import 'subscription_controller.dart';
import 'subscription_display_config.dart';
import 'subscription_display_controller.dart';
import 'subscription_store_product.dart';

class SubscriptionDisplayApi {
  const SubscriptionDisplayApi(this.dio);
  final Dio dio;
  Future<SubscriptionDisplayConfig?> load(SubscriptionPageType type) async {
    final cancel = CancelToken();
    try {
      final response = await dio
          .get<Object?>(
            '/subscription-display-config',
            queryParameters: {'type': type.name, 'platform': 'ios'},
            cancelToken: cancel,
          )
          .timeout(const Duration(seconds: 3));
      final body = response.data;
      if (body is! Map ||
          body['success'] != true ||
          !body.containsKey('data')) {
        throw const FormatException(
          'Unable to read subscription configuration',
        );
      }
      return body['data'] == null
          ? null
          : SubscriptionDisplayConfig.fromJson(body['data'], type);
    } finally {
      cancel.cancel('Subscription configuration lookup finished');
    }
  }
}

final appleSubscriptionProductReaderProvider = Provider(
  (ref) => const AppleSubscriptionProductReader(),
);
final subscriptionDisplayApiProvider = Provider(
  (ref) => SubscriptionDisplayApi(ref.watch(portfolioDioProvider)),
);

const _fallbackYearlyTrialPlanId = 'yearly_trial';

/// Build the local Page/Modal fallback from the approved long-lived products.
///
/// Display the ordinary weekly, yearly trial and lifetime products. All other
/// registered products remain available to the purchase listener and Restore.
SubscriptionDisplayConfig legacySubscriptionFallback(
  AppSubscriptionConfiguration configuration,
  SubscriptionPageType type,
) {
  final ids = configuration.configuredProductIds;
  final weeklyId = ids[subscriptionWeeklyPlanId];
  final lifetimeId = ids[subscriptionLifetimePlanId];
  final additional = {
    for (final product in configuration.additionalProducts)
      product.planId: product,
  };
  final trial = additional[_fallbackYearlyTrialPlanId];

  // Keep old builds usable when the optional additions are not present yet.
  // A partially registered new set must not produce a misleading mixed card
  // list, so it falls back to the previous local configuration as a unit.
  if (weeklyId == null ||
      lifetimeId == null ||
      trial?.type != DisplayProductType.subscription ||
      trial?.isTrialProduct != true) {
    return _legacySubscriptionFallback(configuration, type);
  }

  return SubscriptionDisplayConfig(
    pageType: type,
    isLocalFallback: true,
    skus: [
      SubscriptionDisplaySku(
        productId: weeklyId,
        type: DisplayProductType.subscription,
        offlinePrice: 'US\$4.99',
        offlineFullPrice: 'US\$4.99',
        copy: const SubscriptionCopy(
          name: 'Unlimited Weekly',
          priceNote: 'per week',
          cta: 'SUBSCRIBE',
        ),
      ),
      SubscriptionDisplaySku(
        productId: trial!.productId,
        type: DisplayProductType.subscription,
        isDefault: true,
        offlinePrice: 'US\$49.99',
        offlineFullPrice: 'US\$49.99',
        offlineTrial: true,
        copy: const SubscriptionCopy(
          name: '3-Day Free',
          badge: 'SAVE 81%',
          priceNote: 'per year',
          cta: 'TRY FOR FREE',
        ),
      ),
      SubscriptionDisplaySku(
        productId: lifetimeId,
        type: DisplayProductType.nonConsumable,
        offlinePrice: 'US\$79.99',
        offlineFullPrice: 'US\$79.99',
        copy: const SubscriptionCopy(
          name: 'Lifetime Access',
          badge: 'Best Offer',
          cta: 'SUBSCRIBE',
        ),
      ),
    ],
  );
}

SubscriptionDisplayConfig _legacySubscriptionFallback(
  AppSubscriptionConfiguration configuration,
  SubscriptionPageType type,
) {
  final ids = configuration.configuredProductIds;
  final plans = subscriptionPlans
      .where((p) => ids.containsKey(p.id))
      .toList(growable: false);
  final defaultId = ids.containsKey(subscriptionYearlyPlanId)
      ? subscriptionYearlyPlanId
      : plans.firstOrNull?.id;
  return SubscriptionDisplayConfig(
    pageType: type,
    skus: [
      for (final plan in plans)
        SubscriptionDisplaySku(
          productId: ids[plan.id]!,
          type: plan.id == subscriptionLifetimePlanId
              ? DisplayProductType.nonConsumable
              : DisplayProductType.subscription,
          isDefault: plan.id == defaultId,
          copy: SubscriptionCopy(name: plan.title, badge: plan.badge ?? ''),
        ),
    ],
  );
}

final subscriptionDisplayFactoryProvider =
    Provider<SubscriptionDisplayController Function(SubscriptionPageType)>((
      ref,
    ) {
      final configuration = ref.watch(appSubscriptionConfigurationProvider);
      final api = ref.watch(subscriptionDisplayApiProvider);
      final reader = ref.watch(appleSubscriptionProductReaderProvider);
      return (type) => SubscriptionDisplayController(
        fallback: legacySubscriptionFallback(configuration, type),
        loadConfig: (pageType) async {
          if (configuration.store != SubscriptionStore.appStore) return null;
          return api.load(pageType);
        },
        loadProducts: (requested) async {
          if (configuration.store != SubscriptionStore.appStore) {
            return const [];
          }
          final currentConfiguration = await ref
              .read(subscriptionControllerProvider.notifier)
              .supportedConfiguration(requested: requested);
          if (!ref.mounted) return const [];
          final ids = requested.intersection(
            currentConfiguration.supportedProductIds,
          );
          if (ids.isEmpty) return const [];
          final results = await Future.wait<Object>([
            ref
                .read(subscriptionControllerProvider.notifier)
                .loadDisplayProducts(ids),
            reader.read(ids),
          ]);
          final details = results[0] as List<SubscriptionProduct>;
          final facts = results[1] as Map<String, Map<String, Object?>>;
          final supported = {
            for (final p in currentConfiguration.supportedProducts)
              p.productId: p,
          };
          return [
                for (final product in details)
                  if (facts[product.storeProductId] != null)
                    SubscriptionStoreProduct.fromStore(
                      product,
                      facts[product.storeProductId]!,
                      knownTrialProduct:
                          supported[product.storeProductId]!.isTrialProduct,
                    ),
              ]
              .whereType<SubscriptionStoreProduct>()
              .where((p) => supported[p.id]?.type == p.type)
              .toList(growable: false);
        },
        loadEligibility: reader.eligibility,
      );
    });
