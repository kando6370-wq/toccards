import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:subscription_core/subscription_core.dart';

import '../../shared/analytics/app_analytics.dart';

class SubscriptionRevenueRecord {
  const SubscriptionRevenueRecord({
    required this.transactionId,
    required this.productId,
    required this.planType,
    required this.value,
    required this.currency,
  });

  final String transactionId;
  final String productId;
  final String planType;
  final double value;
  final String currency;

  Map<String, Object> toJson() => {
    'transaction_id': transactionId,
    'product_id': productId,
    'plan_type': planType,
    'value': value,
    'currency': currency,
  };

  static SubscriptionRevenueRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final transactionId = value['transaction_id'];
    final productId = value['product_id'];
    final planType = value['plan_type'];
    final amount = value['value'];
    final currency = value['currency'];
    if (transactionId is! String ||
        transactionId.isEmpty ||
        productId is! String ||
        productId.isEmpty ||
        planType is! String ||
        planType.isEmpty ||
        amount is! num ||
        !amount.isFinite ||
        currency is! String ||
        currency.isEmpty) {
      return null;
    }
    return SubscriptionRevenueRecord(
      transactionId: transactionId,
      productId: productId,
      planType: planType,
      value: amount.toDouble(),
      currency: currency,
    );
  }
}

abstract interface class SubscriptionRevenueStorage {
  Future<Set<String>> readReportedTransactionIds();
  Future<Map<String, SubscriptionRevenueRecord>> readPending();
  Future<void> write({
    required Set<String> reportedTransactionIds,
    required Map<String, SubscriptionRevenueRecord> pending,
  });
}

class PreferencesSubscriptionRevenueStorage
    implements SubscriptionRevenueStorage {
  const PreferencesSubscriptionRevenueStorage();

  static const _reportedKey = 'subscription.revenue.reported_transaction_ids';
  static const _pendingKey = 'subscription.revenue.pending';

  @override
  Future<Set<String>> readReportedTransactionIds() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences
            .getStringList(_reportedKey)
            ?.where((transactionId) => transactionId.trim().isNotEmpty)
            .toSet() ??
        <String>{};
  }

  @override
  Future<Map<String, SubscriptionRevenueRecord>> readPending() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_pendingKey);
    if (encoded == null) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return {};
      final pending = <String, SubscriptionRevenueRecord>{};
      for (final entry in decoded.entries) {
        final record = SubscriptionRevenueRecord.fromJson(entry.value);
        if (entry.key is String &&
            record != null &&
            entry.key == record.transactionId) {
          pending[entry.key as String] = record;
        }
      }
      return pending;
    } on FormatException {
      return {};
    }
  }

  @override
  Future<void> write({
    required Set<String> reportedTransactionIds,
    required Map<String, SubscriptionRevenueRecord> pending,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _reportedKey,
      reportedTransactionIds.toList(growable: false)..sort(),
    );
    await preferences.setString(
      _pendingKey,
      jsonEncode(pending.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }
}

abstract interface class SubscriptionRevenueSink {
  Future<void> report(SubscriptionRevenueRecord record);
}

class AnalyticsSubscriptionRevenueSink implements SubscriptionRevenueSink {
  const AnalyticsSubscriptionRevenueSink(this._analytics);

  final AppAnalytics _analytics;

  @override
  Future<void> report(SubscriptionRevenueRecord record) {
    return _analytics.logVerifiedApplePurchase(
      transactionId: record.transactionId,
      productId: record.productId,
      planType: record.planType,
      value: record.value,
      currency: record.currency,
    );
  }
}

class SubscriptionRevenueReporter {
  SubscriptionRevenueReporter({
    required SubscriptionRevenueStorage storage,
    required SubscriptionRevenueSink sink,
  }) : _storage = storage,
       _sink = sink;

  final SubscriptionRevenueStorage _storage;
  final SubscriptionRevenueSink _sink;
  Future<void> _tail = Future.value();

  Future<void> enqueueVerifiedPurchase(SubscriptionEvent event) {
    final record = _recordFromEvent(event);
    if (record == null) return Future.value();
    return _serial(() async {
      final reported = await _storage.readReportedTransactionIds();
      if (reported.contains(record.transactionId)) return;
      final pending = await _storage.readPending();
      pending[record.transactionId] = record;
      await _storage.write(reportedTransactionIds: reported, pending: pending);
      await _report(record, reported: reported, pending: pending);
    });
  }

  Future<void> flush() => _serial(() async {
    final reported = await _storage.readReportedTransactionIds();
    final pending = await _storage.readPending();
    var changed = false;
    for (final record in pending.values.toList(growable: false)) {
      if (reported.contains(record.transactionId)) {
        pending.remove(record.transactionId);
        changed = true;
        continue;
      }
      try {
        await _report(record, reported: reported, pending: pending);
      } on Object {
        // Analytics retries must never block App startup or purchase access.
      }
    }
    if (changed) {
      await _storage.write(reportedTransactionIds: reported, pending: pending);
    }
  });

  Future<void> _report(
    SubscriptionRevenueRecord record, {
    required Set<String> reported,
    required Map<String, SubscriptionRevenueRecord> pending,
  }) async {
    await _sink.report(record);
    reported.add(record.transactionId);
    pending.remove(record.transactionId);
    await _storage.write(reportedTransactionIds: reported, pending: pending);
  }

  Future<void> _serial(Future<void> Function() operation) {
    final result = _tail.then((_) => operation(), onError: (_) => operation());
    _tail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  static SubscriptionRevenueRecord? _recordFromEvent(SubscriptionEvent event) {
    final purchase = event.purchase;
    final plan = event.plan;
    if (purchase == null ||
        purchase.store != SubscriptionStore.appStore ||
        purchase.status != SubscriptionPurchaseStatus.purchased ||
        event.entitlement?.isActive != true ||
        event.failure != null ||
        plan == null) {
      return null;
    }
    final payload = _decodeJwsPayload(purchase.verificationData);
    final transactionId = payload?['transactionId'];
    final productId = payload?['productId'];
    final price = payload?['price'];
    final currency = payload?['currency'];
    if (transactionId is! String ||
        transactionId.isEmpty ||
        transactionId != purchase.transactionId ||
        productId is! String ||
        productId != purchase.storeProductId ||
        price is! num ||
        price < 0 ||
        currency is! String ||
        currency.isEmpty) {
      return null;
    }
    return SubscriptionRevenueRecord(
      transactionId: transactionId,
      productId: productId,
      planType: plan.id,
      value: price.toDouble() / 1000,
      currency: currency.toUpperCase(),
    );
  }

  static Map<String, Object?>? _decodeJwsPayload(String jws) {
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
}
