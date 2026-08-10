import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  group('configuration protects store independence', () {
    test('requires a product id for every enabled store', () {
      expect(
        () => SubscriptionConfig(
          enabledStores: {
            SubscriptionStore.appStore,
            SubscriptionStore.googlePlay,
          },
          plans: [
            SubscriptionPlanConfig(
              id: 'pro',
              entitlementId: 'premium',
              productIds: {SubscriptionStore.appStore: 'ios.pro'},
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    for (final enabledStore in SubscriptionStore.values) {
      test('${enabledStore.name} only never touches the other store', () async {
        final apple = _FakeGateway(SubscriptionStore.appStore);
        final google = _FakeGateway(SubscriptionStore.googlePlay);
        final client = _client(
          enabledStores: {enabledStore},
          gateways: [apple, google],
        );
        addTearDown(() async {
          await client.dispose();
          await apple.dispose();
          await google.dispose();
        });

        await client.initialize();
        final catalog = await client.loadProducts();

        final enabledGateway = enabledStore == SubscriptionStore.appStore
            ? apple
            : google;
        final disabledGateway = enabledStore == SubscriptionStore.appStore
            ? google
            : apple;
        expect(catalog.products.single.store, enabledStore);
        expect(enabledGateway.loadCalls, 1);
        expect(enabledGateway.hasPurchaseListener, isTrue);
        expect(disabledGateway.loadCalls, 0);
        expect(disabledGateway.hasPurchaseListener, isFalse);
      });
    }

    test('one store failure does not hide another store catalog', () async {
      final apple = _FakeGateway(
        SubscriptionStore.appStore,
        loadError: StateError('App Store unavailable'),
      );
      final google = _FakeGateway(SubscriptionStore.googlePlay);
      final client = _client(
        enabledStores: SubscriptionStore.values.toSet(),
        gateways: [apple, google],
      );
      addTearDown(() async {
        await client.dispose();
        await apple.dispose();
        await google.dispose();
      });

      await client.initialize();
      final catalog = await client.loadProducts();

      expect(catalog.products.single.store, SubscriptionStore.googlePlay);
      expect(catalog.failures.single.store, SubscriptionStore.appStore);
      expect(catalog.failures.single.code, 'product_load_failed');
    });
  });

  group('purchase lifecycle protects entitlement intent', () {
    test('completes a purchase only after trusted verification', () async {
      final apple = _FakeGateway(SubscriptionStore.appStore);
      var verificationCalls = 0;
      final client = _client(
        enabledStores: {SubscriptionStore.appStore},
        gateways: [apple],
        verify: (request) async {
          verificationCalls++;
          return SubscriptionEntitlement(
            planId: request.plan.id,
            entitlementId: request.plan.entitlementId,
            status: SubscriptionEntitlementStatus.active,
          );
        },
      );
      addTearDown(() async {
        await client.dispose();
        await apple.dispose();
      });

      await client.initialize();
      await client.loadProducts();
      await client.purchase(
        planId: 'pro',
        store: SubscriptionStore.appStore,
        applicationUserName: 'account-1',
      );
      expect(apple.lastApplicationUserName, 'account-1');

      final eventFuture = client.events.firstWhere(
        (event) => event.entitlement != null,
      );
      apple.emitPurchase(needsCompletion: true);
      final event = await eventFuture;

      expect(verificationCalls, 1);
      expect(event.entitlement!.isActive, isTrue);
      expect(apple.completeCalls, 1);
    });

    test('does not complete a purchase when verification fails', () async {
      final apple = _FakeGateway(SubscriptionStore.appStore);
      final client = _client(
        enabledStores: {SubscriptionStore.appStore},
        gateways: [apple],
        verify: (_) async => throw StateError('invalid receipt'),
      );
      addTearDown(() async {
        await client.dispose();
        await apple.dispose();
      });

      await client.initialize();
      final eventFuture = client.events.firstWhere(
        (event) => event.failure?.code == 'verification_failed',
      );
      apple.emitPurchase(needsCompletion: true);
      await eventFuture;

      expect(apple.completeCalls, 0);
    });

    test('keeps verified entitlement when store completion fails', () async {
      final apple = _FakeGateway(
        SubscriptionStore.appStore,
        completionError: StateError('completion unavailable'),
      );
      final client = _client(
        enabledStores: {SubscriptionStore.appStore},
        gateways: [apple],
      );
      addTearDown(() async {
        await client.dispose();
        await apple.dispose();
      });

      await client.initialize();
      final eventFuture = client.events.firstWhere(
        (event) => event.failure?.code == 'purchase_completion_failed',
      );
      apple.emitPurchase(needsCompletion: true);
      final event = await eventFuture;

      expect(event.entitlement!.isActive, isTrue);
      expect(apple.completeCalls, 1);
    });

    test('restore continues when one enabled store fails', () async {
      final apple = _FakeGateway(
        SubscriptionStore.appStore,
        restoreError: StateError('restore unavailable'),
      );
      final google = _FakeGateway(SubscriptionStore.googlePlay);
      final client = _client(
        enabledStores: SubscriptionStore.values.toSet(),
        gateways: [apple, google],
      );
      addTearDown(() async {
        await client.dispose();
        await apple.dispose();
        await google.dispose();
      });

      await client.initialize();
      final failures = await client.restore();

      expect(failures.single.store, SubscriptionStore.appStore);
      expect(google.restoreCalls, 1);
    });
  });
}

SubscriptionClient _client({
  required Set<SubscriptionStore> enabledStores,
  required List<_FakeGateway> gateways,
  VerifySubscriptionReceipt? verify,
}) {
  return SubscriptionClient(
    config: SubscriptionConfig(
      enabledStores: enabledStores,
      plans: [
        SubscriptionPlanConfig(
          id: 'pro',
          entitlementId: 'premium',
          productIds: {
            SubscriptionStore.appStore: 'ios.pro',
            SubscriptionStore.googlePlay: 'android.pro',
          },
        ),
      ],
    ),
    gateways: gateways,
    verifier: CallbackSubscriptionReceiptVerifier(
      verify ??
          (request) async => SubscriptionEntitlement(
            planId: request.plan.id,
            entitlementId: request.plan.entitlementId,
            status: SubscriptionEntitlementStatus.active,
          ),
    ),
  );
}

class _FakeGateway implements SubscriptionStoreGateway {
  _FakeGateway(
    this.store, {
    this.loadError,
    this.restoreError,
    this.completionError,
  });

  @override
  final SubscriptionStore store;
  final Object? loadError;
  final Object? restoreError;
  final Object? completionError;
  final _updates = StreamController<SubscriptionPurchase>.broadcast();
  int loadCalls = 0;
  int restoreCalls = 0;
  int completeCalls = 0;
  String? lastApplicationUserName;

  bool get hasPurchaseListener => _updates.hasListener;

  @override
  Stream<SubscriptionPurchase> get purchaseUpdates => _updates.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<SubscriptionProduct>> loadProducts(Set<String> productIds) async {
    loadCalls++;
    if (loadError case final error?) {
      throw error;
    }
    return productIds
        .map(
          (id) => SubscriptionProduct(
            store: store,
            storeProductId: id,
            title: 'Pro',
            description: 'Pro subscription',
            displayPrice: r'$1.99',
            rawPrice: 1.99,
            currencyCode: 'USD',
          ),
        )
        .toList();
  }

  @override
  Future<void> purchase(
    SubscriptionProduct product, {
    String? applicationUserName,
  }) async {
    lastApplicationUserName = applicationUserName;
  }

  @override
  Future<void> restore() async {
    restoreCalls++;
    if (restoreError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> completePurchase(SubscriptionPurchase purchase) async {
    completeCalls++;
    if (completionError case final error?) {
      throw error;
    }
  }

  void emitPurchase({required bool needsCompletion}) {
    _updates.add(
      SubscriptionPurchase(
        store: store,
        storeProductId: store == SubscriptionStore.appStore
            ? 'ios.pro'
            : 'android.pro',
        status: SubscriptionPurchaseStatus.purchased,
        verificationData: 'receipt',
        needsCompletion: needsCompletion,
      ),
    );
  }

  Future<void> dispose() => _updates.close();
}
