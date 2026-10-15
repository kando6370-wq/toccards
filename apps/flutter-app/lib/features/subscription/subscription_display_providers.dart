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

/// Existing page/modal defaults are retained until their separate 1.0.6 designs
/// and real SKU mappings are approved. This is not a new production SKU list.
SubscriptionDisplayConfig legacySubscriptionFallback(
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
          final ids = requested.intersection(configuration.supportedProductIds);
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
            for (final p in configuration.supportedProducts) p.productId: p,
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
