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
    final state = AppPremiumState.values
        .where((candidate) => candidate.name == value['state'])
        .firstOrNull;
    final verifiedAt = DateTime.tryParse(value['verified_at'] as String? ?? '');
    if (state == null || verifiedAt == null) return null;
    return VerifiedEntitlementCache(
      state: state,
      verifiedAt: verifiedAt,
      productId: value['product_id'] as String?,
      originalTransactionId: value['original_transaction_id'] as String?,
      expiresAt: DateTime.tryParse(value['expires_at'] as String? ?? ''),
      isLifetime: value['is_lifetime'] == true,
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
