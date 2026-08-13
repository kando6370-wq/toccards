import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_api.dart';
import 'package:kando_app/features/subscription/subscription_sync_queue.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  test(
    'a locally verified StoreKit 2 purchase activates Premium even when durable sync storage fails',
    () async {
      final verifier = StoreKit2SubscriptionReceiptVerifier(
        session: () => _session('session-a'),
        syncQueue: SubscriptionSyncQueue(
          storage: _FailingStorage(),
          api: _UnusedApi(),
        ),
      );

      final entitlement = await verifier.verify(_request());

      expect(entitlement.status, SubscriptionEntitlementStatus.active);
      expect(entitlement.entitlementId, 'performance_pro');
    },
  );
}

SubscriptionVerificationRequest _request() {
  return SubscriptionVerificationRequest(
    plan: SubscriptionPlanConfig(
      id: 'yearly',
      entitlementId: 'performance_pro',
      productIds: const {SubscriptionStore.appStore: 'ios.yearly'},
    ),
    purchase: SubscriptionPurchase(
      store: SubscriptionStore.appStore,
      storeProductId: 'ios.yearly',
      status: SubscriptionPurchaseStatus.purchased,
      verificationData: 'apple.jws.value',
      applicationUserName: '123e4567-e89b-42d3-a456-426614174000',
      storeData: SK2PurchaseDetails(
        productID: 'ios.yearly',
        purchaseID: 'transaction-1',
        verificationData: PurchaseVerificationData(
          localVerificationData: 'apple.jws.value',
          serverVerificationData: 'apple.jws.value',
          source: 'app_store',
        ),
        transactionDate: DateTime.utc(
          2026,
          8,
          12,
        ).millisecondsSinceEpoch.toString(),
        status: PurchaseStatus.purchased,
        appAccountToken: '123e4567-e89b-42d3-a456-426614174000',
      ),
    ),
  );
}

AuthSession _session(String sessionId) => AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: _token(sessionId),
  refreshToken: 'refresh-token',
  anonymousId: 'anon-1',
);

String _token(String sessionId) {
  final payload = base64Url.encode(
    utf8.encode(jsonEncode({'session_id': sessionId})),
  );
  return 'header.$payload.signature';
}

class _FailingStorage implements SubscriptionSyncStorage {
  @override
  Future<List<PendingSubscriptionSync>> read() async => const [];

  @override
  Future<void> write(List<PendingSubscriptionSync> entries) {
    throw StateError('secure storage unavailable');
  }
}

class _UnusedApi implements SubscriptionEntitlementApi {
  @override
  Future<String> createPurchaseChallenge(
    AuthSession session, {
    required String productId,
  }) => throw UnimplementedError();

  @override
  Future<void> verifyFreshPurchase(
    AuthSession session, {
    required String requestId,
    required String signedTransactionInfo,
  }) => throw UnimplementedError();
}
