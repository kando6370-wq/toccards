import 'package:kando_app/features/subscription/subscription_display_config.dart';
import 'package:kando_app/features/subscription/subscription_store_product.dart';
import 'package:subscription_core/subscription_core.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_display_controller.dart';
import 'package:kando_app/features/subscription/subscription_display_providers.dart';

SubscriptionStoreProduct displayProduct(
  String id, {
  bool trial = false,
  bool lifetime = false,
  TrialEligibility eligibility = TrialEligibility.unknown,
  double amount = 12,
  String currency = 'USD',
  String unit = 'month',
  int value = 1,
  String group = 'test-group',
  int? level = 1,
}) => SubscriptionStoreProduct(
  product: SubscriptionProduct(
    store: SubscriptionStore.appStore,
    storeProductId: id,
    title: id,
    description: '',
    displayPrice: '$currency $amount',
    rawPrice: amount,
    currencyCode: currency,
  ),
  type: lifetime
      ? DisplayProductType.nonConsumable
      : DisplayProductType.subscription,
  decimalPrice: amount.toString(),
  periodUnit: lifetime ? null : unit,
  periodValue: lifetime ? null : value,
  groupId: group,
  groupLevel: level,
  trialUnit: trial ? 'day' : null,
  trialValue: trial ? 3 : null,
  isTrialProduct: trial,
  eligibility: eligibility,
  weeklyPrice: lifetime ? null : 'USD 2.77',
);
SubscriptionDisplayConfig displayConfig({
  SubscriptionPageType type = SubscriptionPageType.page,
  bool trials = true,
  Duration closeDelay = Duration.zero,
}) => SubscriptionDisplayConfig(
  pageType: type,
  configId: 'fixture-only',
  revision: 1,
  trialEnabled: trials,
  trialToggleText: 'Enable free trial',
  cta: 'CONTINUE',
  closeDelay: closeDelay,
  skus: [
    SubscriptionDisplaySku(
      productId: 'paid',
      type: DisplayProductType.subscription,
      copy: const SubscriptionCopy(
        name: 'Monthly',
        cta: 'BUY',
        subtitle: 'Billed {price}',
      ),
      trial: trials
          ? const SubscriptionTrial(
              productId: 'trial',
              copy: SubscriptionCopy(name: 'Try Monthly', cta: 'START TRIAL'),
            )
          : null,
    ),
    const SubscriptionDisplaySku(
      productId: 'once',
      type: DisplayProductType.nonConsumable,
      isDefault: true,
      copy: SubscriptionCopy(name: 'Lifetime'),
    ),
    const SubscriptionDisplaySku(
      productId: 'independent',
      type: DisplayProductType.subscription,
      copy: SubscriptionCopy(
        name: 'Free access',
        cta: 'FREE',
        badge: 'FREE',
        billingNote: 'FREE',
        autoBillingNote: false,
      ),
    ),
  ],
);
Map<String, Object?> displayDto() => {
  'schema_version': 1,
  'config_id': '01ARZ3NDEKTSV4RRFFQ69G5FAV',
  'revision': 1,
  'page_type': 'page',
  'trial_enabled': false,
  'trial_toggle_text': '',
  'cta': '',
  'close_delay_seconds': 0,
  'skus': [
    {
      'product_id': 'paid',
      'product_type': 'subscription',
      'is_default': true,
      'price_mode': 'weekly',
      'trial': null,
      ...displayCopyDto(),
    },
  ],
};
Map<String, Object?> displayCopyDto() => {
  'name': 'Premium',
  'subtitle': '',
  'badge': '',
  'price_note': '',
  'cta': '',
  'billing_note_mode': 'auto',
  'billing_note': '',
};

SubscriptionDisplayController displayPageFixture(SubscriptionPageType type) {
  const configuration = AppSubscriptionConfiguration(
    store: SubscriptionStore.appStore,
    productIds: {
      subscriptionWeeklyPlanId: 'weekly.product',
      subscriptionYearlyPlanId: 'yearly.product',
      subscriptionLifetimePlanId: 'lifetime.product',
    },
  );
  final config = legacySubscriptionFallback(configuration, type);
  return SubscriptionDisplayController(
    fallback: config,
    loadConfig: (_) async => null,
    loadProducts: (ids) async => [
      if (ids.contains('weekly.product'))
        displayProduct('weekly.product', unit: 'week', amount: 3.99),
      if (ids.contains('yearly.product'))
        displayProduct('yearly.product', unit: 'year', amount: 49.99),
      if (ids.contains('lifetime.product'))
        displayProduct('lifetime.product', lifetime: true, amount: 79.99),
    ],
    loadEligibility: (_) async => TrialEligibility.unknown,
  );
}
