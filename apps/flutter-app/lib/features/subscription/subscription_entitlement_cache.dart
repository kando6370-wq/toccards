import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/security/secure_storage_keys.dart';

enum AppPremiumState { unknown, free, premium }

class VerifiedEntitlementCache {
  const VerifiedEntitlementCache({
    required this.state,
    required this.verifiedAt,
    this.productId,
    this.originalTransactionId,
    this.expiresAt,
    this.isLifetime = false,
  });

  final AppPremiumState state;
  final DateTime verifiedAt;
  final String? productId;
  final String? originalTransactionId;
  final DateTime? expiresAt;
  final bool isLifetime;

  AppPremiumState effectiveState(DateTime now) {
    if (state != AppPremiumState.premium) return state;
    if (isLifetime) return AppPremiumState.premium;
    final expiry = expiresAt;
    return expiry != null && expiry.isAfter(now)
        ? AppPremiumState.premium
        : AppPremiumState.unknown;
  }

  Map<String, Object?> toJson() => {
    'state': state.name,
    'verified_at': verifiedAt.toUtc().toIso8601String(),
    'product_id': productId,
    'original_transaction_id': originalTransactionId,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'is_lifetime': isLifetime,
  };

  static VerifiedEntitlementCache? fromJson(Object? value) {
    if (value is! Map) return null;
    final verifiedAtValue = value['verified_at'];
    final productId = value['product_id'];
    final originalTransactionId = value['original_transaction_id'];
    final expiresAtValue = value['expires_at'];
    final isLifetime = value['is_lifetime'];
    if (verifiedAtValue is! String ||
        productId is! String? ||
        originalTransactionId is! String? ||
        expiresAtValue is! String? ||
        isLifetime is! bool) {
      return null;
    }
    final state = AppPremiumState.values
        .where((candidate) => candidate.name == value['state'])
        .firstOrNull;
    final verifiedAt = DateTime.tryParse(verifiedAtValue);
    final expiresAt = expiresAtValue == null
        ? null
        : DateTime.tryParse(expiresAtValue);
    if (state == null || verifiedAt == null) return null;
    if (expiresAtValue != null && expiresAt == null) return null;
    return VerifiedEntitlementCache(
      state: state,
      verifiedAt: verifiedAt,
      productId: productId,
      originalTransactionId: originalTransactionId,
      expiresAt: expiresAt,
      isLifetime: isLifetime,
    );
  }
}

abstract interface class SubscriptionEntitlementCacheStorage {
  Future<VerifiedEntitlementCache?> read();
  Future<void> write(VerifiedEntitlementCache cache);
}

class SecureSubscriptionEntitlementCacheStorage
    implements SubscriptionEntitlementCacheStorage {
  const SecureSubscriptionEntitlementCacheStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<VerifiedEntitlementCache?> read() async {
    final encoded = await _storage.read(
      key: subscriptionVerifiedEntitlementCacheStorageKey,
    );
    if (encoded == null) return null;
    try {
      return VerifiedEntitlementCache.fromJson(jsonDecode(encoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(VerifiedEntitlementCache cache) {
    return _storage.write(
      key: subscriptionVerifiedEntitlementCacheStorageKey,
      value: jsonEncode(cache.toJson()),
    );
  }
}

Map<String, Object?>? decodeStoreKitJwsPayload(String jws) {
  final parts = jws.split('.');
  if (parts.length != 3) return null;
  try {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return decoded is Map<String, Object?> ? decoded : null;
  } on Object {
    return null;
  }
}
