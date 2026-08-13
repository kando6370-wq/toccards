import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/subscription/apple_current_entitlements.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'com.cardai.tcg/apple-current-entitlements-test',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'current entitlement bridge keeps only complete Apple evidence because Restore must not infer Premium from malformed rows',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'readCurrentEntitlements');
            expect(call.arguments, {
              'product_ids': ['ios.yearly'],
            });
            return [
              {
                'product_id': 'ios.yearly',
                'signed_transaction_info': 'jws-yearly',
              },
              {'product_id': 'ios.weekly'},
              {'signed_transaction_info': 'jws-missing-product'},
            ];
          });

      final values = await const MethodChannelAppleCurrentEntitlementReader(
        channel: channel,
      ).read({'ios.yearly'});

      expect(values, hasLength(1));
      expect(values.single.productId, 'ios.yearly');
      expect(values.single.signedTransactionInfo, 'jws-yearly');
    },
  );

  test('Restore Success requires a configured Premium Product ID', () async {
    final result = await AppleSubscriptionRestorer(
      reader: _Reader([
        const AppleCurrentEntitlement(
          productId: 'ios.yearly',
          signedTransactionInfo: 'jws-yearly',
        ),
      ]),
    ).restore({'ios.yearly'});

    expect(result.isSuccess, isTrue);
    expect(result.signedTransactionInfo, 'jws-yearly');
  });

  test(
    'Restore Not Found is distinct from failure when Apple returns no current Premium entitlement',
    () async {
      final result = await AppleSubscriptionRestorer(
        reader: _Reader(const []),
      ).restore({'ios.yearly'});

      expect(result, AppleRestoreResult.notFound);
    },
  );

  test(
    'Restore enforces its deadline because late Apple results must not keep the container blocked',
    () async {
      final reader = _PendingReader();
      final restore = AppleSubscriptionRestorer(
        reader: reader,
        deadline: const Duration(milliseconds: 10),
      ).restore({'ios.yearly'});

      await expectLater(restore, throwsA(isA<TimeoutException>()));
      reader.complete(const [
        AppleCurrentEntitlement(
          productId: 'ios.yearly',
          signedTransactionInfo: 'late-jws',
        ),
      ]);
    },
  );

  test(
    'server lifecycle removes only the inactive known chain because another Apple entitlement still keeps Premium',
    () {
      final corrected = applyAppleLifecycleCorrections(
        [
          AppleCurrentEntitlement(
            productId: 'ios.yearly',
            signedTransactionInfo: _jws(
              'original-refunded',
              DateTime.utc(2026, 8, 12),
            ),
          ),
          AppleCurrentEntitlement(
            productId: 'ios.lifetime',
            signedTransactionInfo: _jws(
              'original-lifetime',
              DateTime.utc(2026, 8, 12),
            ),
          ),
        ],
        [
          ApplePurchaseChainLifecycle(
            originalTransactionId: 'original-refunded',
            productId: 'ios.yearly',
            lifecycleStatus: 'REVOKED',
            stateEffectiveAt: DateTime.utc(2026, 8, 13),
          ),
        ],
      );

      expect(corrected.map((item) => item.productId), ['ios.lifetime']);
    },
  );

  test(
    'unavailable server lifecycle keeps Apple verified evidence because network failure cannot downgrade Premium',
    () {
      final entitlements = [
        AppleCurrentEntitlement(
          productId: 'ios.yearly',
          signedTransactionInfo: _jws(
            'original-active',
            DateTime.utc(2026, 8, 13),
          ),
        ),
      ];

      expect(applyAppleLifecycleCorrections(entitlements, null), entitlements);
    },
  );

  test(
    'older server invalidation cannot override newer StoreKit evidence on the same purchase chain',
    () {
      final entitlement = AppleCurrentEntitlement(
        productId: 'ios.yearly',
        signedTransactionInfo: _jws(
          'original-renewed',
          DateTime.utc(2026, 8, 13),
        ),
      );

      expect(
        applyAppleLifecycleCorrections(
          [entitlement],
          [
            ApplePurchaseChainLifecycle(
              originalTransactionId: 'original-renewed',
              productId: 'ios.yearly',
              lifecycleStatus: 'EXPIRED',
              stateEffectiveAt: DateTime.utc(2026, 8, 12),
            ),
          ],
        ),
        [entitlement],
      );
    },
  );

  test(
    'active server lifecycle cannot grant Premium without a current Apple entitlement',
    () {
      expect(
        applyAppleLifecycleCorrections(const [], [
          ApplePurchaseChainLifecycle(
            originalTransactionId: 'original-server-only',
            productId: 'ios.yearly',
            lifecycleStatus: 'ACTIVE',
            stateEffectiveAt: DateTime.utc(2026, 8, 13),
          ),
        ]),
        isEmpty,
      );
    },
  );
}

String _jws(String originalTransactionId, DateTime signedAt) {
  final payload = base64Url.encode(
    utf8.encode(
      '{"originalTransactionId":"$originalTransactionId",'
      '"signedDate":${signedAt.millisecondsSinceEpoch}}',
    ),
  );
  return 'header.$payload.signature';
}

class _Reader implements AppleCurrentEntitlementReader {
  const _Reader(this.values);

  final List<AppleCurrentEntitlement> values;

  @override
  Future<List<AppleCurrentEntitlement>> read(
    Set<String> productIds, {
    bool synchronize = false,
  }) async => values;
}

class _PendingReader implements AppleCurrentEntitlementReader {
  final _completer = Completer<List<AppleCurrentEntitlement>>();

  void complete(List<AppleCurrentEntitlement> values) {
    _completer.complete(values);
  }

  @override
  Future<List<AppleCurrentEntitlement>> read(
    Set<String> productIds, {
    bool synchronize = false,
  }) => _completer.future;
}
