import 'package:in_app_purchase/in_app_purchase.dart';

import 'subscription_config.dart';
import 'subscription_gateway.dart';
import 'subscription_models.dart';

class InAppPurchaseSubscriptionGateway implements SubscriptionStoreGateway {
  InAppPurchaseSubscriptionGateway({
    required this.store,
    InAppPurchase? inAppPurchase,
  }) : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  @override
  final SubscriptionStore store;
  final InAppPurchase _inAppPurchase;

  @override
  Stream<SubscriptionPurchase> get purchaseUpdates => _inAppPurchase
      .purchaseStream
      .expand((purchases) => purchases.map(_toPurchase));

  @override
  Future<bool> isAvailable() => _inAppPurchase.isAvailable();

  @override
  Future<List<SubscriptionProduct>> loadProducts(Set<String> productIds) async {
    final response = await _inAppPurchase.queryProductDetails(productIds);
    if (response.error != null) {
      throw StateError(response.error!.message);
    }
    if (response.notFoundIDs.isNotEmpty) {
      throw StateError(
        'Products not found: ${response.notFoundIDs.join(', ')}',
      );
    }
    return response.productDetails.map(_toProduct).toList(growable: false);
  }

  @override
  Future<void> purchase(
    SubscriptionProduct product, {
    String? applicationUserName,
  }) async {
    final details = product.storeData;
    if (details is! ProductDetails) {
      throw ArgumentError.value(
        product.storeData,
        'product.storeData',
        'must contain ProductDetails from this gateway',
      );
    }
    final started = await _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: details,
        applicationUserName: applicationUserName,
      ),
    );
    if (!started) {
      throw StateError('The store did not start the purchase flow.');
    }
  }

  @override
  Future<void> restore() => _inAppPurchase.restorePurchases();

  @override
  Future<void> completePurchase(SubscriptionPurchase purchase) {
    final details = purchase.storeData;
    if (details is! PurchaseDetails) {
      throw ArgumentError.value(
        purchase.storeData,
        'purchase.storeData',
        'must contain PurchaseDetails from this gateway',
      );
    }
    return _inAppPurchase.completePurchase(details);
  }

  SubscriptionProduct _toProduct(ProductDetails details) => SubscriptionProduct(
    store: store,
    storeProductId: details.id,
    title: details.title,
    description: details.description,
    displayPrice: details.price,
    rawPrice: details.rawPrice,
    currencyCode: details.currencyCode,
    storeData: details,
  );

  SubscriptionPurchase _toPurchase(PurchaseDetails details) =>
      SubscriptionPurchase(
        store: store,
        storeProductId: details.productID,
        status: _toStatus(details.status),
        verificationData: details.verificationData.serverVerificationData,
        transactionId: details.purchaseID,
        transactionDate: _parseTransactionDate(details.transactionDate),
        errorCode: details.error?.code,
        errorMessage: details.error?.message,
        needsCompletion: details.pendingCompletePurchase,
        storeData: details,
      );

  static SubscriptionPurchaseStatus _toStatus(PurchaseStatus status) =>
      switch (status) {
        PurchaseStatus.pending => SubscriptionPurchaseStatus.pending,
        PurchaseStatus.purchased => SubscriptionPurchaseStatus.purchased,
        PurchaseStatus.restored => SubscriptionPurchaseStatus.restored,
        PurchaseStatus.canceled => SubscriptionPurchaseStatus.canceled,
        PurchaseStatus.error => SubscriptionPurchaseStatus.failed,
      };

  static DateTime? _parseTransactionDate(String? milliseconds) {
    if (milliseconds == null) {
      return null;
    }
    final value = int.tryParse(milliseconds);
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
}
