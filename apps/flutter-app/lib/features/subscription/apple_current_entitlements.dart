import 'package:flutter/services.dart';

class AppleCurrentEntitlement {
  const AppleCurrentEntitlement({
    required this.productId,
    required this.signedTransactionInfo,
  });

  final String productId;
  final String signedTransactionInfo;
}

abstract interface class AppleCurrentEntitlementReader {
  Future<List<AppleCurrentEntitlement>> read(
    Set<String> productIds, {
    bool synchronize = false,
  });
}

class MethodChannelAppleCurrentEntitlementReader
    implements AppleCurrentEntitlementReader {
  const MethodChannelAppleCurrentEntitlementReader({
    MethodChannel channel = const MethodChannel(
      'com.cardai.tcg/apple-current-entitlements',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<List<AppleCurrentEntitlement>> read(
    Set<String> productIds, {
    bool synchronize = false,
  }) async {
    final values = await _channel.invokeListMethod<Object?>(
      synchronize ? 'syncCurrentEntitlements' : 'readCurrentEntitlements',
      {'product_ids': productIds.toList(growable: false)},
    );
    if (values == null) return const [];
    return values
        .whereType<Map>()
        .map((value) {
          final productId = value['product_id'];
          final evidence = value['signed_transaction_info'];
          if (productId is! String ||
              productId.isEmpty ||
              evidence is! String ||
              evidence.isEmpty) {
            return null;
          }
          return AppleCurrentEntitlement(
            productId: productId,
            signedTransactionInfo: evidence,
          );
        })
        .whereType<AppleCurrentEntitlement>()
        .toList(growable: false);
  }
}

class AppleRestoreResult {
  const AppleRestoreResult._({this.signedTransactionInfo});

  static const notFound = AppleRestoreResult._();

  factory AppleRestoreResult.success(String signedTransactionInfo) =>
      AppleRestoreResult._(signedTransactionInfo: signedTransactionInfo);

  final String? signedTransactionInfo;

  bool get isSuccess => signedTransactionInfo != null;
}

class AppleSubscriptionRestorer {
  const AppleSubscriptionRestorer({
    required AppleCurrentEntitlementReader reader,
    this.deadline = const Duration(seconds: 15),
  }) : _reader = reader;

  final AppleCurrentEntitlementReader _reader;
  final Duration deadline;

  Future<AppleRestoreResult> restore(Set<String> premiumProductIds) async {
    final entitlements = await _reader
        .read(premiumProductIds, synchronize: true)
        .timeout(deadline);
    for (final entitlement in entitlements) {
      if (premiumProductIds.contains(entitlement.productId)) {
        return AppleRestoreResult.success(entitlement.signedTransactionInfo);
      }
    }
    return AppleRestoreResult.notFound;
  }
}
