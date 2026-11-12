import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  test('forwards App Store product loading and purchase parameters', () async {
    final platform = _FakePurchasePlatform();
    addTearDown(platform.dispose);
    final gateway = InAppPurchaseSubscriptionGateway(
      store: SubscriptionStore.appStore,
      inAppPurchase: platform,
    );

    final products = await gateway.loadProducts({'ios.yearly'});
    expect(products.single.store, SubscriptionStore.appStore);
    expect(products.single.storeProductId, 'ios.yearly');
    expect(products.single.displayPrice, r'$19.99');

    await gateway.purchase(
      products.single,
      applicationUserName: '123e4567-e89b-42d3-a456-426614174000',
    );
    expect(platform.lastPurchaseParam!.productDetails.id, 'ios.yearly');
    expect(
      platform.lastPurchaseParam!.applicationUserName,
      '123e4567-e89b-42d3-a456-426614174000',
    );
  });

  test(
    'preserves StoreKit 2 purchase evidence, restore, and completion',
    () async {
      final platform = _FakePurchasePlatform();
      final gateway = InAppPurchaseSubscriptionGateway(
        store: SubscriptionStore.appStore,
        inAppPurchase: platform,
      );
      addTearDown(platform.dispose);

      final update = gateway.purchaseUpdates.first;
      final details = SK2PurchaseDetails(
        productID: 'ios.yearly',
        purchaseID: 'transaction-1',
        verificationData: PurchaseVerificationData(
          localVerificationData: 'local',
          serverVerificationData: 'signed-transaction',
          source: 'app_store',
        ),
        transactionDate: DateTime.utc(
          2026,
          11,
          10,
        ).millisecondsSinceEpoch.toString(),
        status: PurchaseStatus.purchased,
        appAccountToken: '123e4567-e89b-42d3-a456-426614174000',
      );
      platform.emit(details);

      final purchase = await update;
      expect(purchase.verificationData, 'signed-transaction');
      expect(purchase.transactionId, 'transaction-1');
      expect(purchase.transactionDate, DateTime.utc(2026, 11, 10));
      expect(
        purchase.applicationUserName,
        '123e4567-e89b-42d3-a456-426614174000',
      );
      expect(purchase.needsCompletion, isTrue);

      await gateway.restore();
      await gateway.completePurchase(purchase);
      expect(platform.restoreCalls, 1);
      expect(identical(platform.completedPurchase, details), isTrue);
    },
  );

  test('does not silently register Google Play billing', () {
    expect(
      () =>
          InAppPurchaseSubscriptionGateway(store: SubscriptionStore.googlePlay),
      throwsUnsupportedError,
    );
  });
}

class _FakePurchasePlatform extends InAppPurchasePlatform {
  final _updates = StreamController<List<PurchaseDetails>>.broadcast();
  PurchaseParam? lastPurchaseParam;
  PurchaseDetails? completedPurchase;
  int restoreCalls = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _updates.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: identifiers
          .map(
            (id) => ProductDetails(
              id: id,
              title: 'Yearly',
              description: 'Annual subscription',
              price: r'$19.99',
              rawPrice: 19.99,
              currencyCode: 'USD',
            ),
          )
          .toList(growable: false),
      notFoundIDs: const [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    lastPurchaseParam = purchaseParam;
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completedPurchase = purchase;
  }

  void emit(PurchaseDetails purchase) => _updates.add([purchase]);

  Future<void> dispose() => _updates.close();
}
