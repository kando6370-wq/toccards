import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/subscription/apple_current_entitlements.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';

void main() {
  test('active renewable cache may temporarily preserve Premium', () {
    final now = DateTime.utc(2026, 8, 12);
    final cache = VerifiedEntitlementCache(
      state: AppPremiumState.premium,
      verifiedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(days: 1)),
    );

    expect(cache.effectiveState(now), AppPremiumState.premium);
  });

  test(
    'expired renewable cache becomes Unknown when StoreKit is unavailable',
    () {
      final now = DateTime.utc(2026, 8, 12);
      final cache = VerifiedEntitlementCache(
        state: AppPremiumState.premium,
        verifiedAt: now.subtract(const Duration(days: 8)),
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );

      expect(cache.effectiveState(now), AppPremiumState.unknown);
    },
  );

  test('verified Lifetime cache may temporarily preserve Premium', () {
    final now = DateTime.utc(2026, 8, 12);
    final cache = VerifiedEntitlementCache(
      state: AppPremiumState.premium,
      verifiedAt: now.subtract(const Duration(days: 100)),
      isLifetime: true,
    );

    expect(cache.effectiveState(now), AppPremiumState.premium);
  });

  test(
    'restart cache contains only verified entitlement facts because old paywalls, Restore UI, and blocked actions must not resume',
    () {
      final cache = VerifiedEntitlementCache(
        state: AppPremiumState.premium,
        verifiedAt: DateTime.utc(2026, 8, 12),
        productId: 'apple.yearly',
        originalTransactionId: 'purchase-chain',
        expiresAt: DateTime.utc(2027, 8, 12),
      );

      expect(cache.toJson().keys, {
        'state',
        'verified_at',
        'product_id',
        'original_transaction_id',
        'expires_at',
        'is_lifetime',
      });
    },
  );

  test('StoreKit JWS decoder rejects malformed evidence', () {
    expect(decodeStoreKitJwsPayload('not-a-jws'), isNull);
    expect(decodeStoreKitJwsPayload(_jws({'productId': 'apple.yearly'})), {
      'productId': 'apple.yearly',
    });
  });

  test(
    'entitlement refresh ignores malformed rows and preserves Lifetime over renewable ordering',
    () {
      final selected = selectBestVerifiedEntitlementCache(
        [
          const AppleCurrentEntitlement(
            productId: 'apple.weekly',
            signedTransactionInfo: 'malformed',
          ),
          AppleCurrentEntitlement(
            productId: 'apple.yearly',
            signedTransactionInfo: _jws({
              'productId': 'apple.yearly',
              'expiresDate': DateTime.utc(2027).millisecondsSinceEpoch,
            }),
          ),
          AppleCurrentEntitlement(
            productId: 'apple.lifetime',
            signedTransactionInfo: _jws({
              'productId': 'apple.lifetime',
              'originalTransactionId': 'lifetime-chain',
            }),
          ),
        ],
        lifetimeProductId: 'apple.lifetime',
        verifiedAt: DateTime.utc(2026, 8, 12),
      );

      expect(selected?.productId, 'apple.lifetime');
      expect(selected?.originalTransactionId, 'lifetime-chain');
      expect(selected?.isLifetime, isTrue);
    },
  );

  test('latest renewable expiry is cached when no Lifetime is active', () {
    final selected = selectBestVerifiedEntitlementCache(
      [
        AppleCurrentEntitlement(
          productId: 'apple.weekly',
          signedTransactionInfo: _jws({
            'productId': 'apple.weekly',
            'expiresDate': DateTime.utc(2026, 8, 20).millisecondsSinceEpoch,
          }),
        ),
        AppleCurrentEntitlement(
          productId: 'apple.yearly',
          signedTransactionInfo: _jws({
            'productId': 'apple.yearly',
            'expiresDate': DateTime.utc(2027, 8, 12).millisecondsSinceEpoch,
          }),
        ),
      ],
      lifetimeProductId: 'apple.lifetime',
      verifiedAt: DateTime.utc(2026, 8, 12),
    );

    expect(selected?.productId, 'apple.yearly');
    expect(selected?.expiresAt, DateTime.utc(2027, 8, 12));
  });
}

String _jws(Map<String, Object> payload) {
  final header = base64Url.encode(utf8.encode('{}')).replaceAll('=', '');
  final body = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return '$header.$body.signature';
}
