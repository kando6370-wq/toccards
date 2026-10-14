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

The verifier is mandatory. `SubscriptionClient` passes purchased or restored
evidence to it and emits the returned entitlement; this package does not make a
backend verification request itself. The host must use a trusted verification
flow and reject unverified purchase data.

Card AI currently enables this package only for iOS. Its
[`StoreKit2SubscriptionReceiptVerifier`](../../apps/flutter-app/lib/features/subscription/subscription_controller.dart)
uses StoreKit 2 verified transactions for local Premium and queues Fresh
Purchase evidence for backend synchronization. A synchronization failure does
not invalidate verified local Premium. Server Premium operations still require
a valid grant for the current live session; a client reporting local verified
Premium without that grant receives `ENTITLEMENT_SYNC_REQUIRED`. See the
[server authorization implementation](../../apps/workers-api/src/entitlements/premium-access.ts)
and the [Premium contract](../../docs/releases/v1.1.0/03-data-api/entitlement-contract.md).
