import 'package:flutter/services.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:subscription_core/subscription_core.dart';

import 'subscription_display_config.dart';

enum TrialEligibility { eligible, ineligible, unknown }

class SubscriptionStoreProduct {
  const SubscriptionStoreProduct({
    required this.product,
    required this.type,
    required this.decimalPrice,
    this.periodUnit,
    this.periodValue,
    this.groupId,
    this.groupLevel,
    this.trialUnit,
    this.trialValue,
    this.weeklyPrice,
    this.fourWeekPrice,
    this.isTrialProduct = false,
    this.eligibility = TrialEligibility.unknown,
  });
  final SubscriptionProduct product;
  final DisplayProductType type;
  final String decimalPrice;
  final String? periodUnit, groupId, trialUnit, weeklyPrice;
  final String? fourWeekPrice;
  final int? periodValue, groupLevel, trialValue;
  final bool isTrialProduct;
  final TrialEligibility eligibility;
  String get id => product.storeProductId;
  bool get hasFreeTrial =>
      trialValue != null && trialValue! > 0 && trialUnit != null;
  bool get canUseTrial =>
      hasFreeTrial && eligibility == TrialEligibility.eligible;
  bool get useNeutralCopy => isTrialProduct && !canUseTrial;
  String get periodLabel => type == DisplayProductType.nonConsumable
      ? 'one-time purchase'
      : 'every ${_period(periodValue!, periodUnit!)}';
  String get billingSummary {
    final normal = type == DisplayProductType.nonConsumable
        ? '${product.displayPrice}, one-time purchase.'
        : '${product.displayPrice} $periodLabel. Auto-renews until cancelled.';
    if (canUseTrial) {
      return '${_period(trialValue!, trialUnit!)} free, then $normal';
    }
    if (isTrialProduct && eligibility == TrialEligibility.unknown) {
      return 'Standard price: $normal Available offers are confirmed by the App Store.';
    }
    return normal;
  }

  bool matchesTrial(SubscriptionStoreProduct target) =>
      type == DisplayProductType.subscription &&
      !isTrialProduct &&
      !hasFreeTrial &&
      target.type == DisplayProductType.subscription &&
      target.canUseTrial &&
      groupId != null &&
      groupId == target.groupId &&
      groupLevel != null &&
      groupLevel == target.groupLevel &&
      periodUnit == target.periodUnit &&
      periodValue == target.periodValue &&
      id != target.id;

  SubscriptionStoreProduct withEligibility(TrialEligibility value) =>
      SubscriptionStoreProduct(
        product: product,
        type: type,
        decimalPrice: decimalPrice,
        periodUnit: periodUnit,
        periodValue: periodValue,
        groupId: groupId,
        groupLevel: groupLevel,
        trialUnit: trialUnit,
        trialValue: trialValue,
        weeklyPrice: weeklyPrice,
        fourWeekPrice: fourWeekPrice,
        isTrialProduct: isTrialProduct,
        eligibility: value,
      );

  bool sameTerms(SubscriptionStoreProduct other) =>
      id == other.id &&
      type == other.type &&
      decimalPrice == other.decimalPrice &&
      product.currencyCode == other.product.currencyCode &&
      product.displayPrice == other.product.displayPrice &&
      periodUnit == other.periodUnit &&
      periodValue == other.periodValue &&
      canUseTrial == other.canUseTrial &&
      (!canUseTrial ||
          (trialUnit == other.trialUnit && trialValue == other.trialValue));

  static SubscriptionStoreProduct? fromStore(
    SubscriptionProduct product,
    Map<String, Object?> facts, {
    required bool knownTrialProduct,
  }) {
    final type = switch (facts['product_type']) {
      'subscription' => DisplayProductType.subscription,
      'non_consumable' => DisplayProductType.nonConsumable,
      _ => null,
    };
    final decimal = facts['price_decimal'];
    final unit = _periodUnit(facts['period_unit']);
    final value = _positive(facts['period_value']);
    if (type == null ||
        facts['product_id'] != product.storeProductId ||
        decimal is! String ||
        !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(decimal) ||
        !product.rawPrice.isFinite ||
        product.rawPrice < 0 ||
        !_sameStorePrice(decimal, product.rawPrice) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(product.currencyCode) ||
        facts['currency_code'] != product.currencyCode ||
        facts['display_price'] != product.displayPrice ||
        product.displayPrice.trim().isEmpty ||
        (type == DisplayProductType.subscription &&
            (unit == null || value == null))) {
      return null;
    }
    final trialUnit = _periodUnit(facts['trial_unit']);
    final trialValue = _positive(facts['trial_value']);
    final hasFree = trialUnit != null && trialValue != null;
    return SubscriptionStoreProduct(
      product: product,
      type: type,
      decimalPrice: decimal,
      periodUnit: unit,
      periodValue: value,
      groupId: facts['group_id'] is String ? facts['group_id'] as String : null,
      groupLevel: _positive(facts['group_level']),
      trialUnit: trialUnit,
      trialValue: trialValue,
      weeklyPrice: facts['weekly_price'] is String
          ? facts['weekly_price'] as String
          : null,
      fourWeekPrice: facts['four_week_price'] is String
          ? facts['four_week_price'] as String
          : null,
      isTrialProduct: knownTrialProduct || hasFree,
    );
  }
}

String _period(int value, String unit) =>
    '$value $unit${value == 1 ? '' : 's'}';
String? _periodUnit(Object? value) =>
    ['day', 'week', 'month', 'year'].contains(value) ? value as String : null;
int? _positive(Object? value) => value is int && value > 0 ? value : null;

bool _sameStorePrice(String decimal, double rawPrice) {
  final parsed = double.tryParse(decimal);
  if (parsed == null || !parsed.isFinite) return false;
  if (parsed == 0 || rawPrice == 0) {
    return parsed == 0 && rawPrice == 0 && !RegExp(r'[1-9]').hasMatch(decimal);
  }
  // Decimal string parsing and StoreKit's Decimal-to-double conversion can
  // round the same price to adjacent binary values.
  final bits = ByteData(8)..setFloat64(0, parsed);
  final parsedBits = bits.getUint64(0);
  bits.setFloat64(0, rawPrice);
  return (parsedBits - bits.getUint64(0)).abs() <= 1;
}

class AppleSubscriptionProductReader {
  const AppleSubscriptionProductReader({
    MethodChannel channel = const MethodChannel(
      'com.cardai.tcg/subscription-products',
    ),
  }) : _channel = channel;
  final MethodChannel _channel;
  Future<Map<String, Map<String, Object?>>> read(Set<String> ids) async {
    final values = await _channel.invokeListMethod<Object?>('read', {
      'product_ids': ids.toList(),
    });
    if (values == null) {
      throw const FormatException('Missing StoreKit product facts');
    }
    final result = <String, Map<String, Object?>>{};
    for (final value in values) {
      if (value is! Map || value['product_id'] is! String) continue;
      final id = value['product_id'] as String;
      if (ids.contains(id)) result[id] = Map<String, Object?>.from(value);
    }
    return result;
  }

  Future<TrialEligibility> eligibility(String productId) async {
    try {
      return await SK2Product.isIntroductoryOfferEligible(productId)
          ? TrialEligibility.eligible
          : TrialEligibility.ineligible;
    } on Object {
      return TrialEligibility.unknown;
    }
  }
}
