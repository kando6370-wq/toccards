import 'dart:async';

import 'subscription_config.dart';
import 'subscription_gateway.dart';
import 'subscription_models.dart';

class SubscriptionClient {
  SubscriptionClient({
    required this.config,
    required Iterable<SubscriptionStoreGateway> gateways,
    required SubscriptionReceiptVerifier verifier,
  }) : _verifier = verifier,
       _gateways = _indexGateways(gateways);

  final SubscriptionConfig config;
  final SubscriptionReceiptVerifier _verifier;
  final Map<SubscriptionStore, SubscriptionStoreGateway> _gateways;
  final _events = StreamController<SubscriptionEvent>.broadcast();
  final _subscriptions = <StreamSubscription<SubscriptionPurchase>>[];
  final _products = <String, SubscriptionProduct>{};
  bool _initialized = false;
  bool _disposed = false;

  Stream<SubscriptionEvent> get events => _events.stream;

  Future<void> initialize() async {
    _ensureNotDisposed();
    if (_initialized) {
      return;
    }
    _initialized = true;
    for (final store in config.enabledStores) {
      final gateway = _gateways[store];
      if (gateway == null) {
        continue;
      }
      _subscriptions.add(
        gateway.purchaseUpdates.listen(
          (purchase) => unawaited(_handlePurchase(purchase)),
          onError: (Object error) {
            _emitFailure(
              SubscriptionFailure(
                code: 'purchase_updates_failed',
                message: 'Purchase update stream failed.',
                store: store,
                cause: error,
              ),
            );
          },
        ),
      );
    }
  }

  Future<SubscriptionCatalog> loadProducts() async {
    _ensureReady();
    final products = <SubscriptionProduct>[];
    final failures = <SubscriptionFailure>[];

    for (final store in config.enabledStores) {
      final gateway = _gateways[store];
      if (gateway == null) {
        failures.add(
          SubscriptionFailure(
            code: 'gateway_not_registered',
            message: 'No gateway registered for ${store.name}.',
            store: store,
          ),
        );
        continue;
      }
      try {
        if (!await gateway.isAvailable()) {
          failures.add(
            SubscriptionFailure(
              code: 'store_unavailable',
              message: '${store.name} is not available.',
              store: store,
            ),
          );
          continue;
        }
        final loaded = await gateway.loadProducts(config.productIdsFor(store));
        for (final product in loaded) {
          _products[_productKey(store, product.storeProductId)] = product;
        }
        products.addAll(loaded);
      } catch (error) {
        failures.add(
          SubscriptionFailure(
            code: 'product_load_failed',
            message: 'Failed to load products from ${store.name}.',
            store: store,
            cause: error,
          ),
        );
      }
    }

    return SubscriptionCatalog(
      products: List.unmodifiable(products),
      failures: List.unmodifiable(failures),
    );
  }

  Future<void> purchase({
    required String planId,
    required SubscriptionStore store,
    String? applicationUserName,
  }) async {
    _ensureReady();
    if (!config.enabledStores.contains(store)) {
      throw StateError('${store.name} is not enabled.');
    }
    final gateway = _requireGateway(store);
    final plan = config.planById(planId);
    final productId = plan.productIdFor(store);
    final product = _products[_productKey(store, productId)];
    if (product == null) {
      throw StateError('Product $productId has not been loaded.');
    }
    await gateway.purchase(product, applicationUserName: applicationUserName);
  }

  Future<List<SubscriptionFailure>> restore({SubscriptionStore? store}) async {
    _ensureReady();
    final stores = store == null ? config.enabledStores : {store};
    final failures = <SubscriptionFailure>[];
    for (final currentStore in stores) {
      if (!config.enabledStores.contains(currentStore)) {
        failures.add(
          SubscriptionFailure(
            code: 'store_not_enabled',
            message: '${currentStore.name} is not enabled.',
            store: currentStore,
          ),
        );
        continue;
      }
      final gateway = _gateways[currentStore];
      if (gateway == null) {
        failures.add(
          SubscriptionFailure(
            code: 'gateway_not_registered',
            message: 'No gateway registered for ${currentStore.name}.',
            store: currentStore,
          ),
        );
        continue;
      }
      try {
        await gateway.restore();
      } catch (error) {
        failures.add(
          SubscriptionFailure(
            code: 'restore_failed',
            message: 'Failed to restore purchases from ${currentStore.name}.',
            store: currentStore,
            cause: error,
          ),
        );
      }
    }
    return List.unmodifiable(failures);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _events.close();
  }

  Future<void> _handlePurchase(SubscriptionPurchase purchase) async {
    final plan = config.planByProductId(
      purchase.store,
      purchase.storeProductId,
    );
    if (plan == null) {
      _events.add(
        SubscriptionEvent(
          purchase: purchase,
          failure: SubscriptionFailure(
            code: 'unknown_product',
            message: 'Purchase does not match a configured product.',
            store: purchase.store,
          ),
        ),
      );
      return;
    }

    if (purchase.status == SubscriptionPurchaseStatus.failed) {
      _events.add(
        SubscriptionEvent(
          purchase: purchase,
          plan: plan,
          failure: SubscriptionFailure(
            code: purchase.errorCode ?? 'purchase_failed',
            message: purchase.errorMessage ?? 'Purchase failed.',
            store: purchase.store,
          ),
        ),
      );
      return;
    }
    if (purchase.status != SubscriptionPurchaseStatus.purchased &&
        purchase.status != SubscriptionPurchaseStatus.restored) {
      _events.add(SubscriptionEvent(purchase: purchase, plan: plan));
      return;
    }

    final SubscriptionEntitlement entitlement;
    try {
      entitlement = await _verifier.verify(
        SubscriptionVerificationRequest(plan: plan, purchase: purchase),
      );
    } catch (error) {
      _events.add(
        SubscriptionEvent(
          purchase: purchase,
          plan: plan,
          failure: SubscriptionFailure(
            code: 'verification_failed',
            message: 'Purchase verification failed.',
            store: purchase.store,
            cause: error,
          ),
        ),
      );
      return;
    }

    if (purchase.needsCompletion) {
      try {
        await _requireGateway(purchase.store).completePurchase(purchase);
      } catch (error) {
        _events.add(
          SubscriptionEvent(
            purchase: purchase,
            plan: plan,
            entitlement: entitlement,
            failure: SubscriptionFailure(
              code: 'purchase_completion_failed',
              message: 'Verified purchase could not be completed.',
              store: purchase.store,
              cause: error,
            ),
          ),
        );
        return;
      }
    }
    _events.add(
      SubscriptionEvent(
        purchase: purchase,
        plan: plan,
        entitlement: entitlement,
      ),
    );
  }

  void _emitFailure(SubscriptionFailure failure) {
    _events.add(SubscriptionEvent(failure: failure));
  }

  SubscriptionStoreGateway _requireGateway(SubscriptionStore store) {
    final gateway = _gateways[store];
    if (gateway == null) {
      throw StateError('No gateway registered for ${store.name}.');
    }
    return gateway;
  }

  void _ensureReady() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw StateError('SubscriptionClient.initialize() must be called first.');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('SubscriptionClient has been disposed.');
    }
  }

  static Map<SubscriptionStore, SubscriptionStoreGateway> _indexGateways(
    Iterable<SubscriptionStoreGateway> gateways,
  ) {
    final indexed = <SubscriptionStore, SubscriptionStoreGateway>{};
    for (final gateway in gateways) {
      if (indexed.containsKey(gateway.store)) {
        throw ArgumentError('Duplicate gateway for ${gateway.store.name}.');
      }
      indexed[gateway.store] = gateway;
    }
    return Map.unmodifiable(indexed);
  }

  static String _productKey(SubscriptionStore store, String productId) =>
      '${store.name}:$productId';
}
