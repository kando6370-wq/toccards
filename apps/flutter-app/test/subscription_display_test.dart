import 'dart:async';
import 'dart:convert';
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
    'linked trial switches only one position; selecting another position turns it off',
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
      model.select('paid');
      expect(model.trialOn, isTrue);
      model.toggleTrial(false);
      expect(model.selectedId, 'paid');
      expect(model.selectedCard!.cta, 'BUY');
      model.toggleTrial(true);
      model.select('once');
      expect(model.trialOn, isFalse);
      expect(model.selectedCard!.product.id, 'once');
    },
  );
  test(
    'independent unknown/ineligible trial keeps identity without marketing promises',
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
        expect(card.copy.name, 'Premium');
        expect(card.cta, 'SUBSCRIBE');
        expect(card.badge, isEmpty);
        expect(card.billingNote, isEmpty);
        expect(model.canPurchase, isTrue);
        expect(
          card.product.billingSummary.contains('Standard price'),
          eligibility == TrialEligibility.unknown,
        );
      }
    },
  );
  test(
    'unresolved qualification does not hold normal products in Loading',
    () async {
      final unknown = Completer<TrialEligibility>();
      final model = _model(eligibility: (_) => unknown.future);
      addTearDown(model.dispose);
      await model.load();
      expect(model.isLoading, isFalse);
      expect(model.canPurchase, isTrue);
      expect(model.showTrialSwitch, isFalse);
      unknown.complete(TrialEligibility.eligible);
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
    'purchase recheck never converts lost linked-trial eligibility into a paid purchase',
    () async {
      var eligibility = TrialEligibility.eligible;
      final model = _model(eligibility: (_) async => eligibility);
      addTearDown(model.dispose);
      await model.load();
      await Future<void>.delayed(Duration.zero);
      model.toggleTrial(true);
      eligibility = TrialEligibility.ineligible;
      expect(await model.confirmPurchase(), isNull);
      expect(model.trialOn, isTrue);
      expect(model.canPurchase, isFalse);
      expect(model.selectedId, 'paid');
      model.toggleTrial(false);
      expect(model.canPurchase, isTrue);
      expect((await model.confirmPurchase())!.storeProductId, 'paid');
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
    'independent trial losing eligibility updates neutral terms and requires a second click',
    () async {
      var eligibility = TrialEligibility.eligible;
      final model = _model(eligibility: (_) async => eligibility);
      addTearDown(model.dispose);
      await model.load();
      await Future<void>.delayed(Duration.zero);
      model.select('independent');
      eligibility = TrialEligibility.unknown;
      expect(await model.confirmPurchase(), isNull);
      expect(model.selectedCard!.cta, 'SUBSCRIBE');
      expect((await model.confirmPurchase())!.storeProductId, 'independent');
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
