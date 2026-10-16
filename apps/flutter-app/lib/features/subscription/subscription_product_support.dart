import 'dart:convert';

import 'subscription_display_config.dart';

/// A release's long-lived purchase/Restore registry, independent of paywall visibility.
class SupportedSubscriptionProduct {
  const SupportedSubscriptionProduct({
    required this.planId,
    required this.productId,
    required this.type,
    this.isTrialProduct = false,
    this.singularEventName,
  });
  final String planId, productId;
  final DisplayProductType type;
  final bool isTrialProduct;
  final String? singularEventName;

  Map<String, Object?> toJson() => {
    'plan_id': planId,
    'product_id': productId,
    'product_type': type == DisplayProductType.subscription
        ? 'subscription'
        : 'non_consumable',
    'is_trial_product': isTrialProduct,
    'singular_event_name': singularEventName,
  };

  static List<SupportedSubscriptionProduct> parse(String source) {
    if (source.trim().isEmpty) return const [];
    final values = jsonDecode(source);
    if (values is! List) {
      throw const FormatException('Supported products must be a list');
    }
    final ids = <String>{};
    final plans = <String>{};
    return List.unmodifiable(
      values.map((value) {
        if (value is! Map ||
            value['plan_id'] is! String ||
            value['product_id'] is! String ||
            value['is_trial_product'] is! bool) {
          throw const FormatException('Invalid supported product');
        }
        final id = value['product_id'] as String;
        final plan = value['plan_id'] as String;
        final event = value['singular_event_name'];
        if (event != null &&
            (event is! String ||
                !RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,99}$').hasMatch(event))) {
          throw const FormatException('Invalid revenue mapping');
        }
        final type = switch (value['product_type']) {
          'subscription' => DisplayProductType.subscription,
          'non_consumable' => DisplayProductType.nonConsumable,
          _ => throw const FormatException('Invalid supported product type'),
        };
        if (id.trim().isEmpty ||
            id != id.trim() ||
            plan.trim().isEmpty ||
            !ids.add(id) ||
            !plans.add(plan) ||
            (type == DisplayProductType.nonConsumable &&
                value['is_trial_product'] == true)) {
          throw const FormatException('Duplicate or invalid supported product');
        }
        return SupportedSubscriptionProduct(
          planId: plan,
          singularEventName: event as String?,
          productId: id,
          type: type,
          isTrialProduct: value['is_trial_product'] == true,
        );
      }),
    );
  }
}
