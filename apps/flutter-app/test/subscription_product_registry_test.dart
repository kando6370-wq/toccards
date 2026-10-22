import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/features/subscription/subscription_singular_events.dart';
import 'package:kando_app/shared/attribution/app_attribution.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kando_app/features/subscription/subscription_product_registry.dart';
import 'package:kando_app/features/subscription/subscription_product_support.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_revenue_reporter.dart';
import 'package:kando_app/shared/api/api_environment.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Map<String, Object?> product(String id) => {
    'product_id': id,
    'plan_id': 'apple:$id',
    'product_type': 'subscription',
    'is_trial_product': false,
    'singular_event_name': 'card_monthlytest',
  };
  test(
    'the real controller appends newly approved products without restarting its purchase listener',
    () async {
      var ids = ['cardx.month'];
      final dio = Dio(
        BaseOptions(baseUrl: 'https://controller.example/api/v1'),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) => handler.resolve(
            Response(
              requestOptions: request,
              data: {
                'success': true,
                'data': {
                  'scope': 'development:beta.app',
                  'products': ids.map(product).toList(),
                },
              },
            ),
          ),
        ),
      );
      final registry = SubscriptionProductRegistry(
        dio,
        environment: AppEnvironment.test,
        bundleId: () async => 'beta.app',
      );
      final gateway = _RegistryGateway();
      final container = _registryContainer(registry, gateway);
      addTearDown(() async {
        container.dispose();
        dio.close();
        await gateway.updates.close();
      });
      final controller = container.read(
        subscriptionControllerProvider.notifier,
      );
      expect(
        (await controller.loadDisplayProducts({
          'cardx.month',
        })).single.storeProductId,
        'cardx.month',
      );
      expect(gateway.listeners, 1);
      ids = ['cardx.month', 'new.year'];
      expect(
        (await controller.loadDisplayProducts({
          'new.year',
        })).single.storeProductId,
        'new.year',
      );
      expect((await controller.supportedConfiguration()).supportedProductIds, {
        'cardx.week',
        'cardx.month',
        'new.year',
      });
      expect(gateway.listeners, 1);
    },
  );
  test(
    'a late registry response after controller disposal cannot start a purchase listener',
    () async {
      final pending = Completer<Response<Object?>>();
      final dio = Dio(BaseOptions(baseUrl: 'https://late.example/api/v1'));
      final started = Completer<RequestOptions>();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            started.complete(request);
            handler.resolve(await pending.future);
          },
        ),
      );
      final gateway = _RegistryGateway();
      final container = _registryContainer(
        SubscriptionProductRegistry(
          dio,
          environment: AppEnvironment.test,
          bundleId: () async => 'beta.app',
        ),
        gateway,
      );
      final controller = container.read(
        subscriptionControllerProvider.notifier,
      );
      final configuration = controller.supportedConfiguration();
      final request = await started.future;
      container.dispose();
      pending.complete(
        Response(
          requestOptions: request,
          data: {
            'success': true,
            'data': {
              'scope': 'development:beta.app',
              'products': [product('cardx.month')],
            },
          },
        ),
      );
      expect((await configuration).supportedProductIds, {'cardx.week'});
      expect(gateway.listeners, 0);
      dio.close();
      await gateway.updates.close();
    },
  );
  test(
    'a newly approved SKU is registered without changing build IDs and survives a hidden paywall and outage',
    () async {
      var products = [product('cardx.month')];
      var offline = false;
      final dio = Dio(BaseOptions(baseUrl: 'https://dev.example/api/v1'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (offline) {
              handler.reject(DioException(requestOptions: request));
              return;
            }
            handler.resolve(
              Response(
                requestOptions: request,
                data: {
                  'success': true,
                  'data': {
                    'scope': 'development:beta.app',
                    'products': products,
                  },
                },
              ),
            );
          },
        ),
      );
      addTearDown(dio.close);
      final registry = SubscriptionProductRegistry(
        dio,
        environment: AppEnvironment.test,
        bundleId: () async => 'beta.app',
      );
      final approved = await registry.load();
      final configuration = const AppSubscriptionConfiguration(
        store: SubscriptionStore.appStore,
        productIds: {'weekly': 'cardx.week'},
      ).withApprovedProducts(approved);
      expect(configuration.supportedProductIds, {'cardx.week', 'cardx.month'});
      expect(configuration.configuredProductIds, {'weekly': 'cardx.week'});
      products = [];
      expect((await registry.load()).single.productId, 'cardx.month');
      offline = true;
      final restarted = SubscriptionProductRegistry(
        dio,
        environment: AppEnvironment.test,
        bundleId: () async => 'beta.app',
      );
      expect(
        (await restarted.load()).single.singularEventName,
        'card_monthlytest',
      );
    },
  );
  test(
    'dev approvals and cached products never become prod or another Bundle approvals',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://same.example/api/v1'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) => handler.resolve(
            Response(
              requestOptions: request,
              data: {
                'success': true,
                'data': {
                  'scope': 'development:beta.app',
                  'products': [product('cardx.month')],
                },
              },
            ),
          ),
        ),
      );
      addTearDown(dio.close);
      await SubscriptionProductRegistry(
        dio,
        environment: AppEnvironment.test,
        bundleId: () async => 'beta.app',
      ).load();
      for (final registry in [
        SubscriptionProductRegistry(
          dio,
          environment: AppEnvironment.production,
          bundleId: () async => 'beta.app',
        ),
        SubscriptionProductRegistry(
          dio,
          environment: AppEnvironment.test,
          bundleId: () async => 'other.app',
        ),
      ]) {
        await expectLater(registry.load(), throwsFormatException);
      }
    },
  );
  test(
    'approved metadata cannot replace old plan identity or collide with another product',
    () {
      const base = AppSubscriptionConfiguration(
        store: SubscriptionStore.appStore,
        productIds: {'weekly': 'cardx.week'},
      );
      final same = base.withApprovedProducts(
        SupportedSubscriptionProduct.parse(jsonEncode([product('cardx.week')])),
      );
      expect(same.supportedProducts.single.planId, 'weekly');
      expect(
        () => base.withApprovedProducts(
          SupportedSubscriptionProduct.parse(
            jsonEncode([
              {...product('cardx.month'), 'plan_id': 'weekly'},
            ]),
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'dynamic revenue retry retains the approved event while unrelated unknown plans stay invalid',
    () {
      final record = {
        'transaction_id': 'tx',
        'product_id': 'cardx.month',
        'plan_type': 'apple:cardx.month',
        'value': 1.0,
        'currency': 'USD',
        'singular_event_name': 'card_monthlytest',
      };
      final restored = SubscriptionRevenueRecord.fromJson(record)!;
      expect(restored.toJson(), record);
      record.remove('singular_event_name');
      expect(SubscriptionRevenueRecord.fromJson(record), isNull);
    },
  );
}

ProviderContainer _registryContainer(
  SubscriptionProductRegistry registry,
  _RegistryGateway gateway,
) => ProviderContainer(
  overrides: [
    authControllerProvider.overrideWith(_RegistryAuth.new),
    appSubscriptionConfigurationProvider.overrideWithValue(
      const AppSubscriptionConfiguration(
        store: SubscriptionStore.appStore,
        productIds: {'weekly': 'cardx.week'},
      ),
    ),
    subscriptionProductRegistryProvider.overrideWithValue(registry),
    subscriptionStoreGatewayProvider.overrideWithValue(gateway),
    subscriptionReceiptVerifierProvider.overrideWithValue(
      CallbackSubscriptionReceiptVerifier(
        (request) async => SubscriptionEntitlement(
          planId: request.plan.id,
          entitlementId: request.plan.entitlementId,
          status: SubscriptionEntitlementStatus.active,
        ),
      ),
    ),
    subscriptionControllerProvider.overrideWith(_RegistryController.new),
    subscriptionRevenueReporterProvider.overrideWithValue(
      SubscriptionRevenueReporter(
        storage: const PreferencesSubscriptionRevenueStorage(
          keyPrefix: 'registry-test',
        ),
        sink: _UnusedRevenueSink(),
      ),
    ),
    singularSubscriptionRevenueReporterProvider.overrideWithValue(
      SingularSubscriptionRevenueReporter(
        environment: AppEnvironment.test,
        attribution: _UnusedAttribution(),
      ),
    ),
  ],
);

class _RegistryAuth extends AuthController {
  @override
  AuthState build() => const AuthState.ready(session: null);
}

class _RegistryController extends SubscriptionController {
  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async =>
      AppPremiumState.free;
}

class _RegistryGateway implements SubscriptionStoreGateway {
  _RegistryGateway() {
    updates = StreamController<SubscriptionPurchase>.broadcast(
      onListen: () => listeners++,
    );
  }
  int listeners = 0;
  late final StreamController<SubscriptionPurchase> updates;
  @override
  SubscriptionStore get store => SubscriptionStore.appStore;
  @override
  Stream<SubscriptionPurchase> get purchaseUpdates => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<SubscriptionProduct>> loadProducts(Set<String> ids) async => ids
      .map(
        (id) => SubscriptionProduct(
          store: store,
          storeProductId: id,
          title: id,
          description: '',
          displayPrice: 'USD 1',
          rawPrice: 1,
          currencyCode: 'USD',
        ),
      )
      .toList();
  @override
  Future<void> purchase(
    SubscriptionProduct product, {
    String? applicationUserName,
  }) async {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> completePurchase(SubscriptionPurchase purchase) async {}
}

class _UnusedRevenueSink implements SubscriptionRevenueSink {
  @override
  Future<void> report(SubscriptionRevenueRecord record) async {
    throw StateError('Unexpected revenue');
  }
}

class _UnusedAttribution implements AppAttributionEventReporter {
  @override
  Future<void> trackRevenue({
    required String eventName,
    required String currency,
    required double value,
    required String transactionId,
    required String productId,
  }) async {
    throw StateError('Unexpected revenue');
  }
}
