import 'dart:async';

import 'package:dio/dio.dart';
import '../auth/auth_models.dart';

const subscriptionEntitlementRequestDeadline = Duration(seconds: 15);
const subscriptionEntitlementTimeoutCode = 'REQUEST_TIMEOUT';

abstract interface class SubscriptionEntitlementApi {
  Future<String> createPurchaseChallenge(
    AuthSession session, {
    required String productId,
  });

  Future<void> verifyFreshPurchase(
    AuthSession session, {
    required String requestId,
    required String signedTransactionInfo,
  });
}

abstract interface class AppleRestoreProofApi {
  Future<AppAttestChallenge> createAppAttestChallenge(
    AuthSession session, {
    required String purpose,
    required String requestId,
    required String keyId,
    String? signedTransactionInfo,
  });

  Future<void> registerAppAttestKey(
    AuthSession session, {
    required String requestId,
    required String challenge,
    required String keyId,
    required String attestation,
  });

  Future<void> verifyRestore(
    AuthSession session, {
    required String requestId,
    required String challenge,
    required String keyId,
    required String assertion,
    required String signedTransactionInfo,
  });
}

abstract interface class AppleLifecycleApi {
  Future<List<ApplePurchaseChainLifecycle>> loadCurrentSessionLifecycle(
    AuthSession session,
  );
}

class ApplePurchaseChainLifecycle {
  const ApplePurchaseChainLifecycle({
    required this.originalTransactionId,
    required this.productId,
    required this.lifecycleStatus,
    this.stateEffectiveAt,
  });

  final String originalTransactionId;
  final String productId;
  final String lifecycleStatus;
  final DateTime? stateEffectiveAt;

  bool get isExplicitlyInactive =>
      const {'BILLING_RETRY', 'EXPIRED', 'REVOKED'}.contains(lifecycleStatus);
}

class AppAttestChallenge {
  const AppAttestChallenge({required this.challenge, required this.clientData});

  final String challenge;
  final String clientData;
}

class SubscriptionEntitlementApiException implements Exception {
  const SubscriptionEntitlementApiException({
    required this.code,
    required this.statusCode,
  });

  final String? code;
  final int? statusCode;

  bool get isRetryable =>
      statusCode == null ||
      statusCode == 408 ||
      statusCode == 429 ||
      (statusCode != null && statusCode! >= 500);
}

class HttpSubscriptionEntitlementApi
    implements
        SubscriptionEntitlementApi,
        AppleRestoreProofApi,
        AppleLifecycleApi {
  const HttpSubscriptionEntitlementApi(
    this._dio, {
    this.requestDeadline = subscriptionEntitlementRequestDeadline,
  });

  final Dio _dio;
  final Duration requestDeadline;

  @override
  Future<List<ApplePurchaseChainLifecycle>> loadCurrentSessionLifecycle(
    AuthSession session,
  ) async {
    final data = await _get('/entitlements/apple/lifecycle', session);
    final values = data['purchase_chains'];
    if (values is! List) {
      throw StateError('Apple lifecycle response is invalid.');
    }
    return values
        .whereType<Map>()
        .map((value) {
          final originalTransactionId = value['original_transaction_id'];
          final productId = value['product_id'];
          final lifecycleStatus = value['lifecycle_status'];
          if (originalTransactionId is! String ||
              originalTransactionId.isEmpty ||
              productId is! String ||
              productId.isEmpty ||
              lifecycleStatus is! String ||
              lifecycleStatus.isEmpty) {
            return null;
          }
          return ApplePurchaseChainLifecycle(
            originalTransactionId: originalTransactionId,
            productId: productId,
            lifecycleStatus: lifecycleStatus,
            stateEffectiveAt: DateTime.tryParse(
              value['state_effective_at'] as String? ?? '',
            ),
          );
        })
        .whereType<ApplePurchaseChainLifecycle>()
        .toList(growable: false);
  }

  @override
  Future<String> createPurchaseChallenge(
    AuthSession session, {
    required String productId,
  }) async {
    final data = await _request(
      '/entitlements/apple/purchase-challenge',
      session,
      body: {'product_id': productId},
    );
    return _requiredString(data['application_account_token']);
  }

  @override
  Future<void> verifyFreshPurchase(
    AuthSession session, {
    required String requestId,
    required String signedTransactionInfo,
  }) async {
    await _request(
      '/entitlements/apple/verify',
      session,
      headers: {'Idempotency-Key': requestId},
      body: {
        'schema_version': 1,
        'evidence_type': 'storekit2_signed_transaction',
        'signed_transaction_info': signedTransactionInfo,
        'request_id': requestId,
      },
    );
  }

  @override
  Future<AppAttestChallenge> createAppAttestChallenge(
    AuthSession session, {
    required String purpose,
    required String requestId,
    required String keyId,
    String? signedTransactionInfo,
  }) async {
    final data = await _request(
      '/entitlements/apple/app-attest/challenge',
      session,
      body: {
        'schema_version': 1,
        'purpose': purpose,
        'request_id': requestId,
        'key_id': keyId,
        if (signedTransactionInfo != null)
          'signed_transaction_info': signedTransactionInfo,
      },
    );
    return AppAttestChallenge(
      challenge: _requiredString(data['challenge']),
      clientData: _requiredString(data['client_data']),
    );
  }

  @override
  Future<void> registerAppAttestKey(
    AuthSession session, {
    required String requestId,
    required String challenge,
    required String keyId,
    required String attestation,
  }) async {
    await _request(
      '/entitlements/apple/app-attest/register',
      session,
      body: {
        'schema_version': 1,
        'request_id': requestId,
        'challenge': challenge,
        'key_id': keyId,
        'attestation': attestation,
      },
    );
  }

  @override
  Future<void> verifyRestore(
    AuthSession session, {
    required String requestId,
    required String challenge,
    required String keyId,
    required String assertion,
    required String signedTransactionInfo,
  }) async {
    await _request(
      '/entitlements/apple/restore',
      session,
      headers: {'Idempotency-Key': requestId},
      body: {
        'schema_version': 1,
        'request_id': requestId,
        'challenge': challenge,
        'key_id': keyId,
        'assertion': assertion,
        'signed_transaction_info': signedTransactionInfo,
      },
    );
  }

  Future<Map<String, Object?>> _request(
    String path,
    AuthSession session, {
    required Map<String, Object?> body,
    Map<String, String>? headers,
  }) async {
    final response = await _withDeadline(
      (cancelToken) => _dio.post<Object?>(
        path,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            ...?headers,
          },
          validateStatus: (_) => true,
        ),
      ),
    );
    final envelope = response.data;
    if (envelope is Map && envelope['success'] == true) {
      final data = envelope['data'];
      if (data is Map) return Map<String, Object?>.from(data);
    }
    throw SubscriptionEntitlementApiException(
      code: _errorCode(envelope),
      statusCode: response.statusCode,
    );
  }

  Future<Map<String, Object?>> _get(String path, AuthSession session) async {
    final response = await _withDeadline(
      (cancelToken) => _dio.get<Object?>(
        path,
        cancelToken: cancelToken,
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
          validateStatus: (_) => true,
        ),
      ),
    );
    final envelope = response.data;
    if (envelope is Map && envelope['success'] == true) {
      final data = envelope['data'];
      if (data is Map) return Map<String, Object?>.from(data);
    }
    throw SubscriptionEntitlementApiException(
      code: _errorCode(envelope),
      statusCode: response.statusCode,
    );
  }

  Future<Response<Object?>> _withDeadline(
    Future<Response<Object?>> Function(CancelToken cancelToken) request,
  ) async {
    final cancelToken = CancelToken();
    try {
      return await request(cancelToken).timeout(
        requestDeadline,
        onTimeout: () {
          cancelToken.cancel(subscriptionEntitlementTimeoutCode);
          throw const SubscriptionEntitlementApiException(
            code: subscriptionEntitlementTimeoutCode,
            statusCode: 408,
          );
        },
      );
    } on DioException {
      if (cancelToken.isCancelled) {
        throw const SubscriptionEntitlementApiException(
          code: subscriptionEntitlementTimeoutCode,
          statusCode: 408,
        );
      }
      rethrow;
    }
  }
}

String _requiredString(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  throw StateError('Subscription entitlement response is invalid.');
}

String? _errorCode(Object? envelope) {
  if (envelope is! Map || envelope['error'] is! Map) return null;
  final value = (envelope['error'] as Map)['code'];
  return value is String && value.isNotEmpty ? value : null;
}
