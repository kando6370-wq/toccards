import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_api.dart';

void main() {
  test(
    'purchase challenge binds the selected Product ID to the current session before StoreKit starts',
    () async {
      final adapter = _RecordingAdapter((options) {
        expect(options.path, '/entitlements/apple/purchase-challenge');
        expect(options.headers['Authorization'], 'Bearer access-token');
        expect(options.data, {'product_id': 'ios.yearly'});
        return _json(201, {
          'success': true,
          'data': {
            'application_account_token': '123e4567-e89b-42d3-a456-426614174000',
          },
        });
      });

      final token = await HttpSubscriptionEntitlementApi(
        _dio(adapter),
      ).createPurchaseChallenge(_session, productId: 'ios.yearly');

      expect(token, '123e4567-e89b-42d3-a456-426614174000');
    },
  );

  test(
    'Fresh Purchase sync sends StoreKit 2 JWS with a matching idempotency key because retries must not duplicate grants',
    () async {
      final adapter = _RecordingAdapter((options) {
        expect(options.path, '/entitlements/apple/verify');
        expect(options.headers['Authorization'], 'Bearer access-token');
        final body = Map<String, Object?>.from(options.data as Map);
        final requestId = body['request_id'];
        expect(requestId, isA<String>());
        expect(options.headers['Idempotency-Key'], requestId);
        expect(body, {
          'schema_version': 1,
          'evidence_type': 'storekit2_signed_transaction',
          'signed_transaction_info': 'apple.jws.value',
          'request_id': requestId,
        });
        return _json(200, {
          'success': true,
          'data': {'state': 'VERIFIED_ACTIVE'},
        });
      });

      await HttpSubscriptionEntitlementApi(_dio(adapter)).verifyFreshPurchase(
        _session,
        requestId: '123e4567-e89b-42d3-a456-426614174000',
        signedTransactionInfo: 'apple.jws.value',
      );
    },
  );

  test(
    'server rejection remains explicit because it must not be mistaken for a grant',
    () async {
      final adapter = _RecordingAdapter(
        (_) => _json(503, {
          'success': false,
          'error': {'code': 'VERIFICATION_UNAVAILABLE'},
        }),
      );

      await expectLater(
        HttpSubscriptionEntitlementApi(
          _dio(adapter),
        ).createPurchaseChallenge(_session, productId: 'ios.yearly'),
        throwsA(
          isA<SubscriptionEntitlementApiException>()
              .having((error) => error.code, 'code', 'VERIFICATION_UNAVAILABLE')
              .having((error) => error.isRetryable, 'isRetryable', isTrue),
        ),
      );
    },
  );

  test(
    'entitlement HTTP has one deadline and reports a retryable timeout instead of accepting a late grant',
    () async {
      final adapter = _RecordingAdapter((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return _json(200, {
          'success': true,
          'data': {'state': 'VERIFIED_ACTIVE'},
        });
      });

      await expectLater(
        HttpSubscriptionEntitlementApi(
          _dio(adapter),
          requestDeadline: const Duration(milliseconds: 20),
        ).verifyFreshPurchase(
          _session,
          requestId: '123e4567-e89b-42d3-a456-426614174000',
          signedTransactionInfo: 'apple.jws.value',
        ),
        throwsA(
          isA<SubscriptionEntitlementApiException>()
              .having(
                (error) => error.code,
                'code',
                subscriptionEntitlementTimeoutCode,
              )
              .having((error) => error.isRetryable, 'isRetryable', isTrue),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test(
    'lifecycle correction reads only the current authenticated session contract',
    () async {
      final adapter = _RecordingAdapter((options) {
        expect(options.method, 'GET');
        expect(options.path, '/entitlements/apple/lifecycle');
        expect(options.headers['Authorization'], 'Bearer access-token');
        return _json(200, {
          'success': true,
          'data': {
            'schema_version': 1,
            'purchase_chains': [
              {
                'original_transaction_id': 'original-refunded',
                'product_id': 'ios.yearly',
                'lifecycle_status': 'REVOKED',
                'state_effective_at': '2026-08-13T00:00:00.000Z',
              },
            ],
          },
        });
      });

      final lifecycle = await HttpSubscriptionEntitlementApi(
        _dio(adapter),
      ).loadCurrentSessionLifecycle(_session);

      expect(lifecycle, hasLength(1));
      expect(lifecycle.single.originalTransactionId, 'original-refunded');
      expect(lifecycle.single.isExplicitlyInactive, isTrue);
    },
  );

  test(
    'state conflict is terminal because a newer lifecycle or reused idempotency key cannot succeed on retry',
    () async {
      final adapter = _RecordingAdapter(
        (_) => _json(409, {
          'success': false,
          'error': {'code': 'STATE_CONFLICT'},
        }),
      );

      await expectLater(
        HttpSubscriptionEntitlementApi(_dio(adapter)).verifyFreshPurchase(
          _session,
          requestId: '123e4567-e89b-42d3-a456-426614174000',
          signedTransactionInfo: 'apple.jws.value',
        ),
        throwsA(
          isA<SubscriptionEntitlementApiException>()
              .having((error) => error.code, 'code', 'STATE_CONFLICT')
              .having((error) => error.isRetryable, 'isRetryable', isFalse),
        ),
      );
    },
  );

  test(
    'Restore proof signs the server canonical client data and keeps the request id as its idempotency key',
    () async {
      var calls = 0;
      final adapter = _RecordingAdapter((options) {
        calls++;
        final body = Map<String, Object?>.from(options.data as Map);
        if (calls == 1) {
          expect(options.path, '/entitlements/apple/app-attest/challenge');
          expect(body, {
            'schema_version': 1,
            'purpose': 'restore',
            'request_id': '123e4567-e89b-42d3-a456-426614174000',
            'key_id': 'apple-key-id',
            'signed_transaction_info': 'apple.jws.value',
          });
          return _json(201, {
            'success': true,
            'data': {'challenge': 'challenge-id', 'client_data': 'canonical'},
          });
        }
        expect(options.path, '/entitlements/apple/restore');
        expect(
          options.headers['Idempotency-Key'],
          '123e4567-e89b-42d3-a456-426614174000',
        );
        expect(body['assertion'], 'assertion-base64');
        return _json(200, {
          'success': true,
          'data': {'state': 'VERIFIED_ACTIVE'},
        });
      });
      final api = HttpSubscriptionEntitlementApi(_dio(adapter));
      final challenge = await api.createAppAttestChallenge(
        _session,
        purpose: 'restore',
        requestId: '123e4567-e89b-42d3-a456-426614174000',
        keyId: 'apple-key-id',
        signedTransactionInfo: 'apple.jws.value',
      );
      expect(challenge.clientData, 'canonical');
      await api.verifyRestore(
        _session,
        requestId: '123e4567-e89b-42d3-a456-426614174000',
        challenge: challenge.challenge,
        keyId: 'apple-key-id',
        assertion: 'assertion-base64',
        signedTransactionInfo: 'apple.jws.value',
      );
      expect(calls, 2);
    },
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  anonymousId: 'anon-1',
);

Dio _dio(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
  dio.httpClientAdapter = adapter;
  return dio;
}

ResponseBody _json(int statusCode, Map<String, Object?> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  const _RecordingAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => await handler(options);

  @override
  void close({bool force = false}) {}
}
