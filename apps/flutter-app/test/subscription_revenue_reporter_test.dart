import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/subscription/subscription_revenue_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'verified Apple purchase reports StoreKit transaction value once',
    () async {
      final storage = _MemoryRevenueStorage();
      final sink = _RecordingRevenueSink();
      final reporter = SubscriptionRevenueReporter(
        storage: storage,
        sink: sink,
      );
      final event = _event();

      await reporter.enqueueVerifiedPurchase(event);
      await reporter.enqueueVerifiedPurchase(event);

      expect(sink.records, hasLength(1));
      expect(sink.records.single.transactionId, 'transaction-1');
      expect(sink.records.single.productId, 'apple.yearly');
      expect(sink.records.single.planType, 'yearly');
      expect(sink.records.single.value, 49.99);
      expect(sink.records.single.currency, 'USD');
      expect(storage.reported, {'transaction-1'});
      expect(storage.pending, isEmpty);
    },
  );

  test(
    'failed analytics remains pending and retries without changing entitlement',
    () async {
      final storage = _MemoryRevenueStorage();
      final sink = _RecordingRevenueSink(failuresRemaining: 1);
      final reporter = SubscriptionRevenueReporter(
        storage: storage,
        sink: sink,
      );

      await expectLater(
        reporter.enqueueVerifiedPurchase(_event()),
        throwsStateError,
      );
      expect(storage.pending, contains('transaction-1'));
      expect(storage.reported, isEmpty);

      await reporter.flush();

      expect(sink.records, hasLength(1));
      expect(storage.pending, isEmpty);
      expect(storage.reported, {'transaction-1'});
    },
  );

  test(
    'Restore, Pending, and unverified purchases never report revenue',
    () async {
      final storage = _MemoryRevenueStorage();
      final sink = _RecordingRevenueSink();
      final reporter = SubscriptionRevenueReporter(
        storage: storage,
        sink: sink,
      );

      await reporter.enqueueVerifiedPurchase(
        _event(status: SubscriptionPurchaseStatus.restored),
      );
      await reporter.enqueueVerifiedPurchase(
        _event(status: SubscriptionPurchaseStatus.pending, entitlement: null),
      );
      await reporter.enqueueVerifiedPurchase(
        _event(
          failure: const SubscriptionFailure(
            code: 'verification_failed',
            message: 'unverified',
            store: SubscriptionStore.appStore,
          ),
        ),
      );

      expect(sink.records, isEmpty);
      expect(storage.pending, isEmpty);
      expect(storage.reported, isEmpty);
    },
  );

  test(
    'missing signed StoreKit price does not fall back to prototype price',
    () async {
      final storage = _MemoryRevenueStorage();
      final sink = _RecordingRevenueSink();
      final reporter = SubscriptionRevenueReporter(
        storage: storage,
        sink: sink,
      );

      await reporter.enqueueVerifiedPurchase(_event(includePrice: false));

      expect(sink.records, isEmpty);
    },
  );

  test(
    'corrupted Revenue storage cannot bypass transaction idempotency or report a non-finite amount',
    () async {
      SharedPreferences.setMockInitialValues({
        'subscription.revenue.reported_transaction_ids': [
          '',
          'transaction-reported',
        ],
        'subscription.revenue.pending': jsonEncode({
          'wrong-map-key': _recordJson(transactionId: 'transaction-wrong'),
          'transaction-valid': _recordJson(transactionId: 'transaction-valid'),
        }),
      });
      const storage = PreferencesSubscriptionRevenueStorage();

      expect(await storage.readReportedTransactionIds(), {
        'transaction-reported',
      });
      expect((await storage.readPending()).keys, {'transaction-valid'});
      expect(
        SubscriptionRevenueRecord.fromJson({
          ..._recordJson(transactionId: 'transaction-infinite'),
          'value': double.infinity,
        }),
        isNull,
      );
    },
  );
}

Map<String, Object> _recordJson({required String transactionId}) => {
  'transaction_id': transactionId,
  'product_id': 'apple.yearly',
  'plan_type': 'yearly',
  'value': 49.99,
  'currency': 'USD',
};

SubscriptionEvent _event({
  SubscriptionPurchaseStatus status = SubscriptionPurchaseStatus.purchased,
  SubscriptionEntitlement? entitlement = const SubscriptionEntitlement(
    planId: 'yearly',
    entitlementId: 'performance_pro',
    status: SubscriptionEntitlementStatus.active,
  ),
  SubscriptionFailure? failure,
  bool includePrice = true,
}) {
  final payload = <String, Object>{
    'transactionId': 'transaction-1',
    'productId': 'apple.yearly',
    if (includePrice) 'price': 49990,
    'currency': 'usd',
  };
  return SubscriptionEvent(
    purchase: SubscriptionPurchase(
      store: SubscriptionStore.appStore,
      storeProductId: 'apple.yearly',
      status: status,
      verificationData: _jws(payload),
      transactionId: 'transaction-1',
    ),
    plan: SubscriptionPlanConfig(
      id: 'yearly',
      entitlementId: 'performance_pro',
      productIds: {SubscriptionStore.appStore: 'apple.yearly'},
    ),
    entitlement: entitlement,
    failure: failure,
  );
}

String _jws(Map<String, Object> payload) {
  final header = base64Url.encode(utf8.encode('{}')).replaceAll('=', '');
  final body = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return '$header.$body.signature';
}

class _MemoryRevenueStorage implements SubscriptionRevenueStorage {
  Set<String> reported = {};
  Map<String, SubscriptionRevenueRecord> pending = {};

  @override
  Future<Map<String, SubscriptionRevenueRecord>> readPending() async => {
    ...pending,
  };

  @override
  Future<Set<String>> readReportedTransactionIds() async => {...reported};

  @override
  Future<void> write({
    required Set<String> reportedTransactionIds,
    required Map<String, SubscriptionRevenueRecord> pending,
  }) async {
    reported = {...reportedTransactionIds};
    this.pending = {...pending};
  }
}

class _RecordingRevenueSink implements SubscriptionRevenueSink {
  _RecordingRevenueSink({this.failuresRemaining = 0});

  int failuresRemaining;
  final records = <SubscriptionRevenueRecord>[];

  @override
  Future<void> report(SubscriptionRevenueRecord record) async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('Firebase unavailable');
    }
    records.add(record);
  }
}
