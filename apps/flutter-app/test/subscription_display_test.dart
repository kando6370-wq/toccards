import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_display_config.dart';
import 'package:kando_app/features/subscription/subscription_display_controller.dart';
import 'package:kando_app/features/subscription/subscription_display_providers.dart';
import 'package:kando_app/features/subscription/subscription_product_support.dart';
import 'package:kando_app/features/subscription/subscription_store_product.dart';
import 'package:subscription_core/subscription_core.dart';
import 'subscription_display_fixtures.dart';

void main() {
  test(
    'a shown remote snapshot cannot turn into different fallback SKUs on foreground failure',
    () async {
      var available = true;
      final remote = displayConfig();
      final model = _model(
        config: remote,
        loader: (_) async => available ? [displayProduct('paid')] : [],
      );
      addTearDown(model.dispose);
      await model.load();
      expect(model.usesRemoteConfiguration, isTrue);
      available = false;
      await model.load();
      expect(identical(model.config, remote), isTrue);
      expect(model.selectedId, 'paid');
      expect(model.canPurchase, isFalse);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'public response tolerates future fields but rejects unknown schema and wrong presentation',
    () {
      final dto = displayDto()..['future_field'] = true;
      expect(
        SubscriptionDisplayConfig.fromJson(
          dto,
          SubscriptionPageType.page,
        ).skus.single.productId,
        'paid',
      );
      expect(
        () =>
            SubscriptionDisplayConfig.fromJson(dto, SubscriptionPageType.modal),
        throwsFormatException,
      );
      dto['schema_version'] = 2;
      expect(
        () =>
            SubscriptionDisplayConfig.fromJson(dto, SubscriptionPageType.page),
        throwsFormatException,
      );
    },
  );
  test(
    'page and modal accept three cards plus linked trials and count independent trial cards toward the limit',
    () {
      for (final type in SubscriptionPageType.values) {
        final dto = displayDto()
          ..['page_type'] = type.name
          ..['trial_enabled'] = true
          ..['trial_toggle_text'] = 'Enable trial';
        final skus = dto['skus'] as List<Map<String, Object?>>;
        final first = skus.first;
        first['trial'] = {'product_id': 'linked.trial', ...displayCopyDto()};
        skus.addAll([
          {
            ...first,
            'product_id': 'second',
            'is_default': false,
            'trial': null,
          },
          {
            ...first,
            'product_id': 'independent.trial',
            'is_default': false,
            'trial': null,
          },
        ]);
        final config = SubscriptionDisplayConfig.fromJson(dto, type);
        expect(config.skus.map((sku) => sku.productId), [
          'paid',
          'second',
          'independent.trial',
        ]);
        expect(
          config.skus.singleWhere((sku) => sku.isDefault).productId,
          'paid',
        );
        expect(config.productIds, {
          'paid',
          'second',
          'independent.trial',
          'linked.trial',
        });
        skus.add({
          ...first,
          'product_id': 'fourth',
          'is_default': false,
          'trial': null,
        });
        expect(
          () => SubscriptionDisplayConfig.fromJson(dto, type),
          throwsFormatException,
        );
        expect(skus, hasLength(4));
      }
    },
  );
  test(
    'trial price settings inherit when omitted and override when provided',
    () async {
      for (final type in SubscriptionPageType.values) {
        final dto = displayDto()
          ..['page_type'] = type.name
          ..['trial_enabled'] = true
          ..['trial_toggle_text'] = 'Enable trial';
        final sku = (dto['skus'] as List).first as Map<String, Object?>;
        sku['hide_price'] = true;
        sku['trial'] = {'product_id': 'trial', ...displayCopyDto()};

        final inherited = SubscriptionDisplayConfig.fromJson(dto, type);
        expect(inherited.skus.single.hidePrice, isTrue);
        expect(inherited.skus.single.trial!.hidePrice, isNull);
        expect(inherited.skus.single.trial!.weeklyReference, isNull);
        final inheritedModel = _model(config: inherited);
        addTearDown(inheritedModel.dispose);
        await inheritedModel.load();
        await Future<void>.delayed(Duration.zero);
        inheritedModel.toggleTrial(true);
        expect(inheritedModel.selectedCard!.product.id, 'trial');
        expect(inheritedModel.selectedCard!.hidePrice, isTrue);
        expect(inheritedModel.selectedCard!.weeklyReference, isTrue);

        sku['trial'] = {
          'product_id': 'trial',
          'price_mode': 'actual',
          'hide_price': false,
          ...displayCopyDto(),
        };
        final overridden = SubscriptionDisplayConfig.fromJson(dto, type);
        final overriddenModel = _model(config: overridden);
        addTearDown(overriddenModel.dispose);
        await overriddenModel.load();
        await Future<void>.delayed(Duration.zero);
        overriddenModel.toggleTrial(true);
        expect(overriddenModel.selectedCard!.hidePrice, isFalse);
        expect(overriddenModel.selectedCard!.weeklyReference, isFalse);
        expect(overriddenModel.selectedCard!.product.id, 'trial');
      }
    },
  );
  test('price display fields reject invalid types and modes', () {
    for (final invalid in [null, 'true', 1]) {
      final dto = displayDto();
      final sku = (dto['skus'] as List).first as Map<String, Object?>;
      sku['hide_price'] = invalid;
      expect(
        () =>
            SubscriptionDisplayConfig.fromJson(dto, SubscriptionPageType.page),
        throwsFormatException,
      );
    }
    for (final field in ['price_mode', 'hide_price']) {
      for (final invalid
          in field == 'price_mode' ? [null, 'hide', true] : [null, 'true', 1]) {
        final dto = displayDto()
          ..['trial_enabled'] = true
          ..['trial_toggle_text'] = 'Enable trial';
        final sku = (dto['skus'] as List).first as Map<String, Object?>;
        sku['trial'] = {
          'product_id': 'trial',
          field: invalid,
          ...displayCopyDto(),
        };
        expect(
          () => SubscriptionDisplayConfig.fromJson(
            dto,
            SubscriptionPageType.page,
          ),
          throwsFormatException,
        );
      }
    }
  });
  test(
    'an oversized remote configuration uses the existing fallback without querying truncated remote purchase targets',
    () async {
      for (final type in SubscriptionPageType.values) {
        final dto = displayDto()..['page_type'] = type.name;
        final first = (dto['skus'] as List).first as Map<String, Object?>;
        dto['skus'] = [
          for (var i = 0; i < 4; i++)
            {...first, 'product_id': 'remote-$i', 'is_default': i == 3},
        ];
        final fallback = displayConfig(type: type, trials: false);
        final model = SubscriptionDisplayController(
          fallback: fallback,
          loadConfig: (type) async =>
              SubscriptionDisplayConfig.fromJson(dto, type),
          loadProducts: (ids) async {
            expect(ids, fallback.productIds);
            return [
              displayProduct('paid'),
              displayProduct('once', lifetime: true),
            ];
          },
          loadEligibility: (_) async => TrialEligibility.unknown,
        );
        addTearDown(model.dispose);
        await model.load();
        expect(identical(model.config, fallback), isTrue);
        expect(model.usesRemoteConfiguration, isFalse);
        expect(model.selectedId, 'once');
        expect(model.canPurchase, isTrue);
      }
    },
  );
  test(
    'malformed defaults, duplicates and unsafe CTA cannot reach a purchase page',
    () {
      for (final edit in <void Function(Map<String, Object?>)>[
        (d) => (d['skus'] as List).add((d['skus'] as List).first),
        (d) => ((d['skus'] as List).first as Map)['is_default'] = false,
        (d) => d['cta'] = 'Pay {price}',
        (d) => ((d['skus'] as List).first as Map)['subtitle'] = '{unsupported}',
        (d) => d['close_delay_seconds'] = -1,
      ]) {
        final dto = displayDto();
        edit(dto);
        expect(
          () => SubscriptionDisplayConfig.fromJson(
            dto,
            SubscriptionPageType.page,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'hidden trial payload cannot change purchase targets when switching is disabled',
    () {
      final dto = displayDto();
      ((dto['skus'] as List).first as Map)['trial'] = {'product_id': 'hidden'};
      expect(
        SubscriptionDisplayConfig.fromJson(
          dto,
          SubscriptionPageType.page,
        ).productIds,
        {'paid'},
      );
    },
  );
  test(
    'API preserves page/modal scope and distinguishes disabled from failed configuration',
    () async {
      final adapter = _Adapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://fixture.test/api/v1'))
        ..httpClientAdapter = adapter;
      final api = SubscriptionDisplayApi(dio);
      adapter.body = {'success': true, 'data': displayDto()};
      expect(
        (await api.load(SubscriptionPageType.page))!.pageType,
        SubscriptionPageType.page,
      );
      expect(adapter.last!.path, '/subscription-display-config');
      expect(adapter.last!.queryParameters, {
        'type': 'page',
        'platform': 'ios',
      });
      adapter.body = {'success': true, 'data': null};
      expect(await api.load(SubscriptionPageType.modal), isNull);
      expect(adapter.last!.queryParameters['type'], 'modal');
      adapter.body = {
        'success': false,
        'error': {'code': 'UNAVAILABLE'},
      };
      await expectLater(
        api.load(SubscriptionPageType.page),
        throwsFormatException,
      );
      dio.close();
    },
  );
  test(
    'supported registry retains hidden products and preserves Android platform isolation',
    () {
      final additional = SupportedSubscriptionProduct.parse(
        '[{"plan_id":"trial-plan","product_id":"trial","product_type":"subscription","is_trial_product":true}]',
      );
      final configuration = AppSubscriptionConfiguration(
        store: SubscriptionStore.appStore,
        productIds: const {subscriptionWeeklyPlanId: 'paid'},
        additionalProducts: additional,
      );
      expect(configuration.supportedProductIds, {'paid', 'trial'});
      expect(configuration.configuredProductIds.values, ['paid']);
      expect(
        legacySubscriptionFallback(
          configuration,
          SubscriptionPageType.modal,
        ).productIds,
        {'paid'},
      );
      expect(
        AppSubscriptionConfiguration.fromEnvironment(
          platform: TargetPlatform.android,
        ).store,
        isNull,
      );
      expect(
        () => SupportedSubscriptionProduct.parse('[{"plan_id":"x"}]'),
        throwsFormatException,
      );
    },
  );
  test(
    'dev retains new products for purchase and restore while fallback uses the approved cards',
    () {
      final defines =
          jsonDecode(File('config/test.json').readAsStringSync())
              as Map<String, Object?>;
      final configuration = AppSubscriptionConfiguration(
        store: SubscriptionStore.appStore,
        productIds: {
          subscriptionWeeklyPlanId:
              defines['SUBSCRIPTION_APP_STORE_WEEKLY_ID'] as String,
          subscriptionYearlyPlanId:
              defines['SUBSCRIPTION_APP_STORE_YEARLY_ID'] as String,
          subscriptionLifetimePlanId:
              defines['SUBSCRIPTION_APP_STORE_LIFETIME_ID'] as String,
        },
        additionalProducts: SupportedSubscriptionProduct.parse(
          defines['SUBSCRIPTION_APP_STORE_SUPPORTED_PRODUCTS'] as String,
        ),
      );
      expect(configuration.supportedProductIds, {
        'cardx.week',
        'cardx.year',
        'cardx.lifetime',
        'weekly.trial',
        'yearly.pro',
        'cardx.month',
      });
      final yearly = configuration.supportedProducts.singleWhere(
        (p) => p.productId == 'yearly.pro',
      );
      expect(yearly.planId, 'yearly_pro');
      expect(yearly.type, DisplayProductType.subscription);
      expect(yearly.isTrialProduct, isFalse);
      final trial = configuration.supportedProducts.singleWhere(
        (p) => p.productId == 'weekly.trial',
      );
      expect(trial.planId, 'weekly_trial');
      expect(trial.type, DisplayProductType.subscription);
      expect(trial.isTrialProduct, isTrue);
      for (final type in SubscriptionPageType.values) {
        final fallback = legacySubscriptionFallback(configuration, type);
        expect(fallback.skus.map((sku) => sku.productId), [
          'weekly.trial',
          'yearly.pro',
          'cardx.month',
        ]);
        expect(
          fallback.skus.singleWhere((sku) => sku.isDefault).productId,
          'weekly.trial',
        );
        expect(fallback.skus[0].copy.name, '3-Day Free');
        expect(fallback.skus[0].copy.cta, 'TRY FOR FREE');
        expect(fallback.skus[1].copy.name, 'Unlimited Yearly');
        expect(fallback.skus[1].copy.subtitle, 'Only {price} per year');
        expect(fallback.skus[1].copy.badge, 'save 81%');
        expect(fallback.skus[2].copy.name, 'Unlimited Monthly');
        expect(fallback.skus[2].copy.subtitle, 'Only {price} per month');
        expect(fallback.skus[2].copy.badge, 'Most Popular');
        expect(
          configuration.supportedProductIds,
          containsAll(['weekly.trial', 'yearly.pro', 'cardx.month']),
        );
      }

      final productionDefines =
          jsonDecode(File('config/production.json').readAsStringSync())
              as Map<String, Object?>;
      final productionConfiguration = AppSubscriptionConfiguration(
        store: SubscriptionStore.appStore,
        productIds: {
          subscriptionWeeklyPlanId:
              productionDefines['SUBSCRIPTION_APP_STORE_WEEKLY_ID'] as String,
          subscriptionYearlyPlanId:
              productionDefines['SUBSCRIPTION_APP_STORE_YEARLY_ID'] as String,
          subscriptionLifetimePlanId:
              productionDefines['SUBSCRIPTION_APP_STORE_LIFETIME_ID'] as String,
        },
        additionalProducts: SupportedSubscriptionProduct.parse(
          productionDefines['SUBSCRIPTION_APP_STORE_SUPPORTED_PRODUCTS']
              as String,
        ),
      );
      expect(
        legacySubscriptionFallback(
          productionConfiguration,
          SubscriptionPageType.page,
        ).skus.map((sku) => sku.productId),
        ['CardAi.weekly.trial', 'CardAi.yearly', 'CardAi.monthly'],
      );
    },
  );
  test(
    'StoreKit facts must match the purchasable object; missing facts never produce a fake price',
    () {
      final product = displayProduct('paid').product;
      final facts = <String, Object?>{
        'product_id': 'paid',
        'product_type': 'subscription',
        'price_decimal': '12.00',
        'display_price': product.displayPrice,
        'currency_code': 'USD',
        'period_unit': 'month',
        'period_value': 1,
      };
      expect(
        SubscriptionStoreProduct.fromStore(
          product,
          facts,
          knownTrialProduct: false,
        ),
        isNotNull,
      );
      for (final change in [
        {'currency_code': 'EUR'},
        {'price_decimal': '13'},
        {'period_value': 0},
        {'product_type': 'consumable'},
      ]) {
        expect(
          SubscriptionStoreProduct.fromStore(product, {
            ...facts,
            ...change,
          }, knownTrialProduct: false),
          isNull,
        );
      }
    },
  );
  test(
    'monthly fallback price survives StoreKit mapping and eligibility update',
    () {
      final product = displayProduct('cardx.month', amount: 12.99).product;
      final monthly = SubscriptionStoreProduct.fromStore(product, {
        'product_id': 'cardx.month',
        'product_type': 'subscription',
        'price_decimal': '12.99',
        'display_price': product.displayPrice,
        'currency_code': 'USD',
        'period_unit': 'month',
        'period_value': 1,
        'weekly_price': 'US\$3.00',
        'four_week_price': 'US\$3.25',
      }, knownTrialProduct: false);
      expect(monthly?.weeklyPrice, 'US\$3.00');
      expect(monthly?.fourWeekPrice, 'US\$3.25');
      expect(
        monthly?.withEligibility(TrialEligibility.eligible).fourWeekPrice,
        'US\$3.25',
      );
    },
  );
  test(
    'StoreKit rounding keeps the weekly trial switch on both pages',
    () async {
      const product = SubscriptionProduct(
        store: SubscriptionStore.appStore,
        storeProductId: 'cardx.week',
        title: 'Weekly',
        description: '',
        displayPrice: r'$3.99',
        rawPrice: 3.9899999999999998,
        currencyCode: 'USD',
      );
      final facts = <String, Object?>{
        'product_id': 'cardx.week',
        'product_type': 'subscription',
        'price_decimal': '3.99',
        'display_price': r'$3.99',
        'currency_code': 'USD',
        'period_unit': 'week',
        'period_value': 1,
        'group_id': 'weekly-group',
        'group_level': 2,
      };
      final weekly = SubscriptionStoreProduct.fromStore(
        product,
        facts,
        knownTrialProduct: false,
      );
      expect(weekly, isNotNull);
      for (final decimal in ['3.98', '4.00', '3.990000000000001']) {
        expect(
          SubscriptionStoreProduct.fromStore(product, {
            ...facts,
            'price_decimal': decimal,
          }, knownTrialProduct: false),
          isNull,
        );
      }
      const trialProduct = SubscriptionProduct(
        store: SubscriptionStore.appStore,
        storeProductId: 'weekly.trial',
        title: 'Weekly Trial',
        description: '',
        displayPrice: r'$3.99',
        rawPrice: 3.9899999999999998,
        currencyCode: 'USD',
      );
      final trial = SubscriptionStoreProduct.fromStore(trialProduct, {
        ...facts,
        'product_id': 'weekly.trial',
        'trial_unit': 'day',
        'trial_value': 3,
      }, knownTrialProduct: true);
      expect(trial, isNotNull);
      for (final type in SubscriptionPageType.values) {
        final model = _model(
          config: SubscriptionDisplayConfig(
            pageType: type,
            trialEnabled: true,
            trialToggleText: 'Enable trial',
            skus: [
              const SubscriptionDisplaySku(
                productId: 'cardx.week',
                type: DisplayProductType.subscription,
                isDefault: true,
                copy: SubscriptionCopy(name: 'Weekly'),
                trial: SubscriptionTrial(
                  productId: 'weekly.trial',
                  copy: SubscriptionCopy(name: 'Weekly Trial'),
                ),
              ),
            ],
          ),
          products: [weekly!, trial!],
        );
        addTearDown(model.dispose);
        await model.load();
        await Future<void>.delayed(Duration.zero);
        expect(model.availableSkus.map((sku) => sku.productId), ['cardx.week']);
        expect(model.showTrialSwitch, isTrue);
        model.toggleTrial(true);
        expect(model.selectedCard!.product.id, 'weekly.trial');
      }
    },
  );
  test('zero price cannot match a nonzero decimal rounded to zero', () {
    const product = SubscriptionProduct(
      store: SubscriptionStore.appStore,
      storeProductId: 'free',
      title: 'Free',
      description: '',
      displayPrice: r'$0.00',
      rawPrice: 0,
      currencyCode: 'USD',
    );
    final facts = <String, Object?>{
      'product_id': 'free',
      'product_type': 'non_consumable',
      'price_decimal': '0.00',
      'display_price': r'$0.00',
      'currency_code': 'USD',
    };
    expect(
      SubscriptionStoreProduct.fromStore(
        product,
        facts,
        knownTrialProduct: false,
      ),
      isNotNull,
    );
    expect(
      SubscriptionStoreProduct.fromStore(product, {
        ...facts,
        'price_decimal': '0.${'0' * 350}1',
      }, knownTrialProduct: false),
      isNull,
    );
  });
  test(
    'native bridge passes exact supported IDs and retains independent trial role when offer disappears',
    () async {
      const channel = MethodChannel('fixture/subscription-products');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'read');
            expect((call.arguments as Map)['product_ids'], ['trial']);
            final p = displayProduct('trial').product;
            return [
              {
                'product_id': 'trial',
                'product_type': 'subscription',
                'price_decimal': '12',
                'display_price': p.displayPrice,
                'currency_code': 'USD',
                'period_unit': 'month',
                'period_value': 1,
              },
            ];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final facts = await const AppleSubscriptionProductReader(
        channel: channel,
      ).read({'trial'});
      final value = SubscriptionStoreProduct.fromStore(
        displayProduct('trial').product,
        facts['trial']!,
        knownTrialProduct: true,
      )!;
      expect(value.hasFreeTrial, isFalse);
      expect(value.useNeutralCopy, isTrue);
    },
  );

  test(
    'default downgrade follows visible ordering and never selects a trial-only target',
    () async {
      final model = _model(
        products: [
          displayProduct('paid'),
          displayProduct('trial', trial: true),
        ],
      );
      addTearDown(model.dispose);
      await model.load();
      expect(model.selectedId, 'paid');
      expect(model.availableSkus.map((s) => s.productId), ['paid']);
      expect(model.selectedCard!.product.id, 'paid');
      expect(model.trialOn, isFalse);
    },
  );
  test(
    'linked trial list stays active while selecting and purchasing another position',
    () async {
      final model = _model();
      addTearDown(model.dispose);
      await model.load();
      await Future<void>.delayed(Duration.zero);
      expect(model.selectedId, 'once');
      expect(model.showTrialSwitch, isTrue);
      model.toggleTrial(true);
      expect(model.selectedId, 'paid');
      expect(model.selectedCard!.product.id, 'trial');
      expect(model.selectedCard!.cta, 'START TRIAL');
      final trialProducts = [
        for (final sku in model.availableSkus) model.card(sku)!.product.id,
      ];
      expect(trialProducts, ['trial', 'once', 'independent']);

      model.select('once');
      expect(model.trialOn, isTrue);
      expect(model.selectedId, 'once');
      expect(model.selectedCard!.product.id, 'once');
      expect([
        for (final sku in model.availableSkus) model.card(sku)!.product.id,
      ], trialProducts);
      expect(model.canPurchase, isTrue);
      expect((await model.confirmPurchase())!.storeProductId, 'once');

      model.select('paid');
      expect(model.trialOn, isTrue);
      expect(model.selectedCard!.product.id, 'trial');
      model.toggleTrial(false);
      expect(model.selectedId, 'paid');
      expect(model.selectedCard!.product.id, 'paid');
      expect(model.selectedCard!.cta, 'BUY');
    },
  );
  test('trial mode keeps only its activated relationship replaced', () async {
    final config = SubscriptionDisplayConfig(
      pageType: SubscriptionPageType.page,
      trialEnabled: true,
      trialToggleText: 'Enable trial',
      skus: const [
        SubscriptionDisplaySku(
          productId: 'paid',
          type: DisplayProductType.subscription,
          copy: SubscriptionCopy(name: 'First'),
          trial: SubscriptionTrial(
            productId: 'trial',
            copy: SubscriptionCopy(name: 'First trial'),
          ),
        ),
        SubscriptionDisplaySku(
          productId: 'second',
          type: DisplayProductType.subscription,
          copy: SubscriptionCopy(name: 'Second'),
          trial: SubscriptionTrial(
            productId: 'second-trial',
            copy: SubscriptionCopy(name: 'Second trial'),
          ),
        ),
        SubscriptionDisplaySku(
          productId: 'once',
          type: DisplayProductType.nonConsumable,
          isDefault: true,
          copy: SubscriptionCopy(name: 'Lifetime'),
        ),
      ],
    );
    final model = _model(
      config: config,
      products: [
        displayProduct('paid'),
        displayProduct('trial', trial: true),
        displayProduct('second'),
        displayProduct('second-trial', trial: true),
        displayProduct('once', lifetime: true),
      ],
    );
    addTearDown(model.dispose);
    await model.load();
    await Future<void>.delayed(Duration.zero);

    model.toggleTrial(true);
    expect(
      [for (final sku in model.availableSkus) model.card(sku)!.product.id],
      ['trial', 'second', 'once'],
    );
    model.select('second');
    expect(model.trialOn, isTrue);
    expect(model.selectedCard!.product.id, 'second');
    expect(
      [for (final sku in model.availableSkus) model.card(sku)!.product.id],
      ['trial', 'second', 'once'],
    );
    expect((await model.confirmPurchase())!.storeProductId, 'second');
  });
  test(
    'account qualification does not lock the activated trial position',
    () async {
      var qualificationCalls = 0;
      final model = _model(
        eligibility: (_) async {
          qualificationCalls++;
          return TrialEligibility.ineligible;
        },
      );
      addTearDown(model.dispose);
      await model.load();
      model.toggleTrial(true);
      model.select('once');

      await model.load();
      model.select('paid');
      expect(model.trialOn, isTrue);
      expect(model.trialInvalid, isFalse);
      expect(model.canPurchase, isTrue);
      expect((await model.confirmPurchase())!.storeProductId, 'trial');
      expect(qualificationCalls, 0);
    },
  );
  test(
    'account qualification is not queried during a different product purchase',
    () async {
      var qualificationCalls = 0;
      final model = _model(
        eligibility: (_) async {
          qualificationCalls++;
          return TrialEligibility.unknown;
        },
      );
      addTearDown(model.dispose);
      await model.load();
      model.toggleTrial(true);
      model.select('once');

      await model.load();
      expect((await model.confirmPurchase())!.storeProductId, 'once');

      model.select('paid');
      expect(model.trialOn, isTrue);
      expect(model.trialInvalid, isFalse);
      expect((await model.confirmPurchase())!.storeProductId, 'trial');
      expect(model.trialInvalid, isFalse);
      expect(qualificationCalls, 0);
    },
  );
  test(
    'independent trial keeps configured copy without account qualification',
    () async {
      for (final eligibility in [
        TrialEligibility.unknown,
        TrialEligibility.ineligible,
      ]) {
        final model = _model(eligibility: (_) async => eligibility);
        addTearDown(model.dispose);
        await model.load();
        await Future<void>.delayed(Duration.zero);
        model.select('independent');
        final card = model.selectedCard!;
        expect(card.product.id, 'independent');
        expect(card.copy.name, 'Free access');
        expect(card.cta, 'FREE');
        expect(card.badge, 'FREE');
        expect(card.billingNote, 'FREE');
        expect(model.canPurchase, isTrue);
        expect(card.product.billingSummary, isNot(contains('Standard price')));
      }
    },
  );
  test(
    'trial switch appears with products before account qualification returns',
    () async {
      final unknown = Completer<TrialEligibility>();
      final model = _model(eligibility: (_) => unknown.future);
      addTearDown(model.dispose);
      await model.load();
      expect(model.isLoading, isFalse);
      expect(model.canPurchase, isTrue);
      expect(model.showTrialSwitch, isTrue);
      expect(model.selectedCard!.product.id, 'once');
    },
  );
  test(
    'group, level and period mismatches exclude only that relationship',
    () async {
      for (final target in [
        displayProduct('trial', trial: true, group: 'other'),
        displayProduct('trial', trial: true, level: null),
        displayProduct('trial', trial: true, unit: 'year'),
      ]) {
        final model = _model(products: [displayProduct('paid'), target]);
        addTearDown(model.dispose);
        await model.load();
        await Future<void>.delayed(Duration.zero);
        expect(model.showTrialSwitch, isFalse);
        expect(model.canPurchase, isTrue);
      }
    },
  );
  test(
    'configuration timeout fixes fallback and ignores late remote success across retries',
    () async {
      final late = Completer<SubscriptionDisplayConfig?>();
      var configCalls = 0;
      final fallback = displayConfig(trials: false);
      final model = SubscriptionDisplayController(
        fallback: fallback,
        loadConfig: (_) {
          configCalls++;
          return late.future;
        },
        loadProducts: (_) async => [displayProduct('paid')],
        loadEligibility: (_) async => TrialEligibility.unknown,
        configBudget: const Duration(milliseconds: 10),
        loadBudget: const Duration(milliseconds: 80),
      );
      addTearDown(model.dispose);
      await model.load();
      late.complete(displayConfig());
      await model.load();
      expect(identical(model.config, fallback), isTrue);
      expect(configCalls, 1);
    },
  );
  test(
    'remote-all-unavailable falls back once inside one deadline and ignores late products',
    () async {
      final fallback = SubscriptionDisplayConfig(
        pageType: SubscriptionPageType.page,
        skus: [
          const SubscriptionDisplaySku(
            productId: 'fallback',
            type: DisplayProductType.subscription,
            copy: SubscriptionCopy(name: 'Fallback'),
            isDefault: true,
          ),
        ],
      );
      var calls = 0;
      final late = Completer<List<SubscriptionStoreProduct>>();
      final model = SubscriptionDisplayController(
        fallback: fallback,
        loadConfig: (_) async => displayConfig(),
        loadProducts: (_) {
          calls++;
          return calls == 1 ? Future.value([]) : late.future;
        },
        loadEligibility: (_) async => TrialEligibility.unknown,
        loadBudget: const Duration(milliseconds: 30),
      );
      addTearDown(model.dispose);
      await model.load();
      expect(calls, 2);
      expect(model.isLoading, isFalse);
      late.complete([displayProduct('fallback')]);
      await Future<void>.delayed(Duration.zero);
      expect(model.canPurchase, isFalse);
      expect(model.availableSkus, isEmpty);
    },
  );
  test('a newer load and disposal isolate old responses', () async {
    final old = Completer<List<SubscriptionStoreProduct>>();
    var calls = 0;
    final model = _model(
      loader: (_) => ++calls == 1
          ? old.future
          : Future.value([displayProduct('once', lifetime: true)]),
    );
    final first = model.load();
    await Future<void>.delayed(Duration.zero);
    await model.load();
    old.complete([displayProduct('paid')]);
    await first;
    expect(model.selectedId, 'once');
    model.dispose();
  });
  test(
    'purchase recheck does not query account eligibility for a linked trial',
    () async {
      var qualificationCalls = 0;
      final model = _model(
        eligibility: (_) async {
          qualificationCalls++;
          return TrialEligibility.ineligible;
        },
      );
      addTearDown(model.dispose);
      await model.load();
      model.toggleTrial(true);
      expect((await model.confirmPurchase())!.storeProductId, 'trial');
      expect(model.trialOn, isTrue);
      expect(model.canPurchase, isTrue);
      expect(model.selectedId, 'paid');
      expect(qualificationCalls, 0);
    },
  );
  test(
    'changed amount requires a second user confirmation with the same product ID',
    () async {
      var amount = 12.0;
      final model = _model(
        loader: (_) async => [displayProduct('paid', amount: amount)],
      );
      addTearDown(model.dispose);
      await model.load();
      amount = 15;
      expect(await model.confirmPurchase(), isNull);
      expect(model.selectedId, 'paid');
      expect((await model.confirmPurchase())!.rawPrice, 15);
    },
  );
  test(
    'independent trial purchase does not recheck account eligibility',
    () async {
      var qualificationCalls = 0;
      final model = _model(
        eligibility: (_) async {
          qualificationCalls++;
          return TrialEligibility.unknown;
        },
      );
      addTearDown(model.dispose);
      await model.load();
      model.select('independent');
      expect((await model.confirmPurchase())!.storeProductId, 'independent');
      expect(model.selectedCard!.cta, 'FREE');
      expect(qualificationCalls, 0);
    },
  );
  test('retry does not reset the presentation close delay', () async {
    final model = _model(
      config: displayConfig(closeDelay: const Duration(milliseconds: 25)),
    );
    addTearDown(model.dispose);
    await model.load();
    expect(model.closeAvailable, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await model.load();
    expect(model.closeAvailable, isTrue);
  });
}

SubscriptionDisplayController _model({
  SubscriptionDisplayConfig? config,
  List<SubscriptionStoreProduct>? products,
  DisplayProductLoader? loader,
  TrialEligibilityLoader? eligibility,
}) {
  final data =
      products ??
      [
        displayProduct('paid'),
        displayProduct('trial', trial: true),
        displayProduct('once', lifetime: true),
        displayProduct('independent', trial: true),
      ];
  return SubscriptionDisplayController(
    fallback: displayConfig(trials: false),
    loadConfig: (_) async => config ?? displayConfig(),
    loadProducts:
        loader ?? (ids) async => data.where((p) => ids.contains(p.id)).toList(),
    loadEligibility: eligibility ?? (_) async => TrialEligibility.eligible,
    loadBudget: const Duration(milliseconds: 150),
    retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
  );
}

class _Adapter implements HttpClientAdapter {
  Object? body;
  RequestOptions? last;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
