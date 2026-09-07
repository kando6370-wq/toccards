import 'subscription_config.dart';
import 'subscription_models.dart';

abstract interface class SubscriptionStoreGateway {
  SubscriptionStore get store;

  Stream<SubscriptionPurchase> get purchaseUpdates;

  Future<bool> isAvailable();

  Future<List<SubscriptionProduct>> loadProducts(Set<String> productIds);

  Future<void> purchase(
    SubscriptionProduct product, {
    String? applicationUserName,
  });

  Future<void> restore();

  Future<void> completePurchase(SubscriptionPurchase purchase);
}

abstract interface class SubscriptionReceiptVerifier {
  Future<SubscriptionEntitlement> verify(
    SubscriptionVerificationRequest request,
  );
}

typedef VerifySubscriptionReceipt =
    Future<SubscriptionEntitlement> Function(
      SubscriptionVerificationRequest request,
    );

class CallbackSubscriptionReceiptVerifier
    implements SubscriptionReceiptVerifier {
  const CallbackSubscriptionReceiptVerifier(this._verify);

  final VerifySubscriptionReceipt _verify;

  @override
  Future<SubscriptionEntitlement> verify(
    SubscriptionVerificationRequest request,
  ) => _verify(request);
}
