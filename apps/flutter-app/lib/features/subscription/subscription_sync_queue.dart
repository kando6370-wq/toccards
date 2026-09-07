import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../shared/security/secure_storage_keys.dart';
import '../auth/auth_models.dart';
import 'subscription_entitlement_api.dart';

class PendingSubscriptionSync {
  const PendingSubscriptionSync({
    required this.sessionId,
    required this.requestId,
    required this.signedTransactionInfo,
    required this.createdAt,
  });

  final String sessionId;
  final String requestId;
  final String signedTransactionInfo;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'request_id': requestId,
    'signed_transaction_info': signedTransactionInfo,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  static PendingSubscriptionSync? fromJson(Map<String, Object?> value) {
    final sessionId = _nonEmptyString(value['session_id']);
    final requestId = _nonEmptyString(value['request_id']);
    final evidence = _nonEmptyString(value['signed_transaction_info']);
    final createdAt = DateTime.tryParse(
      _nonEmptyString(value['created_at']) ?? '',
    );
    if (sessionId == null ||
        requestId == null ||
        evidence == null ||
        createdAt == null) {
      return null;
    }
    return PendingSubscriptionSync(
      sessionId: sessionId,
      requestId: requestId,
      signedTransactionInfo: evidence,
      createdAt: createdAt.toUtc(),
    );
  }
}

abstract interface class SubscriptionSyncStorage {
  Future<List<PendingSubscriptionSync>> read();
  Future<void> write(List<PendingSubscriptionSync> entries);
}

class SecureSubscriptionSyncStorage implements SubscriptionSyncStorage {
  const SecureSubscriptionSyncStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<List<PendingSubscriptionSync>> read() async {
    final encoded = await _storage.read(
      key: subscriptionPendingAppleVerificationStorageKey,
    );
    if (encoded == null) return const [];
    try {
      final value = jsonDecode(encoded);
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map(
            (item) => PendingSubscriptionSync.fromJson(
              Map<String, Object?>.from(item),
            ),
          )
          .whereType<PendingSubscriptionSync>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> write(List<PendingSubscriptionSync> entries) {
    if (entries.isEmpty) {
      return _storage.delete(
        key: subscriptionPendingAppleVerificationStorageKey,
      );
    }
    return _storage.write(
      key: subscriptionPendingAppleVerificationStorageKey,
      value: jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}

class SubscriptionSyncQueue {
  SubscriptionSyncQueue({
    required SubscriptionSyncStorage storage,
    required SubscriptionEntitlementApi api,
    DateTime Function()? now,
  }) : _storage = storage,
       _api = api,
       _now = now ?? DateTime.now;

  static const _maxEntries = 20;
  final SubscriptionSyncStorage _storage;
  final SubscriptionEntitlementApi _api;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  Future<void> enqueueAndFlush(
    AuthSession session, {
    required String signedTransactionInfo,
  }) {
    return _serialize(() async {
      final sessionId = sessionIdFromAccessToken(session.accessToken);
      if (sessionId == null) return;
      final entries = await _entriesForSession(sessionId);
      if (!entries.any(
        (entry) => entry.signedTransactionInfo == signedTransactionInfo,
      )) {
        entries.add(
          PendingSubscriptionSync(
            sessionId: sessionId,
            requestId: const Uuid().v4(),
            signedTransactionInfo: signedTransactionInfo,
            createdAt: _now().toUtc(),
          ),
        );
      }
      await _storage.write(
        entries.length <= _maxEntries
            ? entries
            : entries.sublist(entries.length - _maxEntries),
      );
      unawaited(_serialize(() => _flush(session, sessionId)));
    });
  }

  Future<void> flush(AuthSession session) {
    return _serialize(() async {
      final sessionId = sessionIdFromAccessToken(session.accessToken);
      if (sessionId == null) {
        await _storage.write(const []);
        return;
      }
      await _flush(session, sessionId);
    });
  }

  Future<void> _flush(AuthSession session, String sessionId) async {
    final entries = await _entriesForSession(sessionId);
    while (entries.isNotEmpty) {
      final entry = entries.first;
      try {
        await _api.verifyFreshPurchase(
          session,
          requestId: entry.requestId,
          signedTransactionInfo: entry.signedTransactionInfo,
        );
        entries.removeAt(0);
        await _storage.write(entries);
      } on SubscriptionEntitlementApiException catch (error) {
        if (!error.isRetryable) {
          entries.removeAt(0);
          await _storage.write(entries);
          continue;
        }
        return;
      } on Exception {
        return;
      }
    }
  }

  Future<List<PendingSubscriptionSync>> _entriesForSession(
    String sessionId,
  ) async {
    final entries = (await _storage.read())
        .where((entry) => entry.sessionId == sessionId)
        .toList();
    await _storage.write(entries);
    return entries;
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.catchError((Object _) {});
    return result;
  }
}

String? sessionIdFromAccessToken(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    return _nonEmptyString(payload['session_id']);
  } on FormatException {
    return null;
  }
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
