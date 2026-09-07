# subscription_core

Reusable subscription business logic for Flutter applications using App Store
In-App Purchase (StoreKit) and Google Play Billing.

The package keeps product configuration, purchase orchestration, receipt
verification, and entitlement delivery independent from application UI and
business entities. An enabled store can fail without preventing another store
from loading products or restoring purchases.

## Configuration

```dart
final config = SubscriptionConfig(
  enabledStores: {currentStore},
  plans: [
    SubscriptionPlanConfig(
      id: 'pro_monthly',
      entitlementId: 'pro',
      productIds: {
        SubscriptionStore.appStore: 'com.example.pro.monthly',
        SubscriptionStore.googlePlay: 'pro_monthly',
      },
    ),
  ],
);

final client = SubscriptionClient(
  config: config,
  gateways: [
    InAppPurchaseSubscriptionGateway(store: currentStore),
  ],
  verifier: CallbackSubscriptionReceiptVerifier((request) async {
    // Send request.purchase.verificationData to a trusted backend.
    return verifyWithBackend(request);
  }),
);

await client.initialize();
final catalog = await client.loadProducts();
```

Set `enabledStores` to only the store available in the current runtime, and
register one `InAppPurchaseSubscriptionGateway` for that store. A project may
keep both product IDs in shared plan configuration while enabling App Store in
the iOS build and Google Play in the Android build. The core also accepts
multiple custom gateways; catalog and restore failures are returned per store.

The verifier is mandatory. Client-side purchase data must not grant an
entitlement without trusted server verification.
