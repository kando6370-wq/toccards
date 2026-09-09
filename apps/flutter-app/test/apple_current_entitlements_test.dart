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
    'StoreKit synchronization is separate from entitlement reading',
    () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'syncAppStore') return null;
            expect(call.method, 'readCurrentEntitlements');
            return const <Object?>[];
          });

      final reader = const MethodChannelAppleCurrentEntitlementReader(
        channel: channel,
      );
      await reader.synchronize();
      await reader.read({'ios.yearly'});

      expect(methods, ['syncAppStore', 'readCurrentEntitlements']);
    },
  );

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
    'Restore cancellation does not reuse a current entitlement left on the device',
    () async {
      final error = PlatformException(
        code: appleRestoreCancelledErrorCode,
        details: const {'domain': 'StoreKit.StoreKitError'},
      );
      final reader = _SynchronizationFailureReader(
        error: error,
        values: const [
          AppleCurrentEntitlement(
            productId: 'ios.yearly',
            signedTransactionInfo: 'jws-yearly',
          ),
        ],
      );

      await expectLater(
        AppleSubscriptionRestorer(reader: reader).restore({'ios.yearly'}),
        throwsA(same(error)),
      );
      expect(
        reader.readCount,
        0,
        reason:
            'A cancelled account check must not restore from '
            'entitlement data left on the device.',
      );
    },
  );

  test('Restore cancellation is classified separately from failure', () {
    expect(
      isAppleRestoreCancellation(
        PlatformException(code: appleRestoreCancelledErrorCode),
      ),
      isTrue,
    );
    expect(
      isAppleRestoreCancellation(
        PlatformException(code: 'apple_restore_failed'),
      ),
      isFalse,
    );
    expect(isAppleRestoreCancellation(TimeoutException('restore')), isFalse);
  });

  test(
    'Restore keeps StoreKit system error as Failed without reading entitlements',
    () async {
      final error = PlatformException(
        code: 'apple_restore_failed',
        details: const {'domain': 'StoreKit.StoreKitError', 'code': 3},
      );
      final reader = _SynchronizationFailureReader(
        error: error,
        values: const [],
      );

      await expectLater(
        AppleSubscriptionRestorer(reader: reader).restore({'ios.yearly'}),
        throwsA(same(error)),
      );
      expect(reader.readCount, 0);
    },
  );

  test(
    'Restore does not fallback for non-system StoreKit synchronization errors',
    () async {
      final error = PlatformException(
        code: 'apple_restore_failed',
        details: const {'domain': 'StoreKit.StoreKitError', 'code': 1},
      );
      final reader = _SynchronizationFailureReader(
        error: error,
        values: const [
          AppleCurrentEntitlement(
            productId: 'ios.yearly',
            signedTransactionInfo: 'jws-yearly',
          ),
        ],
      );

      await expectLater(
        AppleSubscriptionRestorer(reader: reader).restore({'ios.yearly'}),
        throwsA(same(error)),
      );
      expect(reader.readCount, 0);
    },
  );

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
    'Restore excludes StoreKit authentication time from its deadline',
    () async {
      final reader = _PendingSynchronizationReader([
        const AppleCurrentEntitlement(
          productId: 'ios.yearly',
          signedTransactionInfo: 'jws-yearly',
        ),
      ]);
      final restore = AppleSubscriptionRestorer(
        reader: reader,
        deadline: const Duration(milliseconds: 10),
      ).restore({'ios.yearly'});
      final observed = restore.then<Object>(
        (value) => value,
        onError: (Object error, StackTrace _) => error,
      );

      final beforeAuthenticationCompletes = await Future.any<Object>([
        observed,
        Future<Object>.delayed(
          const Duration(milliseconds: 30),
          () => 'still-authenticating',
        ),
      ]);
      expect(beforeAuthenticationCompletes, 'still-authenticating');

      reader.completeSynchronization();
      final result = await observed;
      expect(result, isA<AppleRestoreResult>());
      expect((result as AppleRestoreResult).isSuccess, isTrue);
    },
  );

  test(
    'Restore enforces its deadline after StoreKit synchronization completes',
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
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) async =>
      values;

  @override
  Future<void> synchronize() async {}
}

class _PendingReader implements AppleCurrentEntitlementReader {
  final _completer = Completer<List<AppleCurrentEntitlement>>();

  void complete(List<AppleCurrentEntitlement> values) {
    _completer.complete(values);
  }

  @override
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) =>
      _completer.future;

  @override
  Future<void> synchronize() async {}
}

class _PendingSynchronizationReader implements AppleCurrentEntitlementReader {
  _PendingSynchronizationReader(this.values);

  final List<AppleCurrentEntitlement> values;
  final _synchronization = Completer<void>();

  void completeSynchronization() => _synchronization.complete();

  @override
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) async =>
      values;

  @override
  Future<void> synchronize() => _synchronization.future;
}

class _SynchronizationFailureReader implements AppleCurrentEntitlementReader {
  _SynchronizationFailureReader({required this.error, required this.values});

  final Object error;
  final List<AppleCurrentEntitlement> values;
  var readCount = 0;

  @override
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) async {
    readCount++;
    return values;
  }

  @override
  Future<void> synchronize() => Future<void>.error(error);
}
