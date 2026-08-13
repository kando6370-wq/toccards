import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_api.dart';
import 'package:kando_app/features/subscription/subscription_sync_queue.dart';

void main() {
  test(
    'purchase evidence is durable before background verification starts',
    () async {
      final storage = _MemoryStorage();
      final api = _BlockingApi();
      final queue = SubscriptionSyncQueue(storage: storage, api: api);

      await queue.enqueueAndFlush(
        _session('session-a'),
        signedTransactionInfo: 'jws-a',
      );

      expect(storage.entries, hasLength(1));
      expect(storage.entries.single.signedTransactionInfo, 'jws-a');
      await api.started.future;
      api.complete();
      await queue.flush(_session('session-a'));
      expect(storage.entries, isEmpty);
    },
  );

  test(
    'retryable failure survives restart with the same request ID because a purchase sync must remain idempotent',
    () async {
      final storage = _MemoryStorage([
        PendingSubscriptionSync(
          sessionId: 'session-a',
          requestId: 'request-a',
          signedTransactionInfo: 'jws-a',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
      ]);
      final unavailable = _FakeApi(
        error: const SubscriptionEntitlementApiException(
          code: 'VERIFICATION_UNAVAILABLE',
          statusCode: 503,
        ),
      );
      await SubscriptionSyncQueue(
        storage: storage,
        api: unavailable,
      ).flush(_session('session-a'));

      expect(storage.entries, hasLength(1));

      final recovered = _FakeApi();
      await SubscriptionSyncQueue(
        storage: storage,
        api: recovered,
      ).flush(_session('session-a'));

      expect(recovered.requests.single.requestId, 'request-a');
      expect(recovered.requests.single.evidence, 'jws-a');
      expect(storage.entries, isEmpty);
    },
  );

  test(
    'a new session clears old evidence because Premium proof must never cross sessions',
    () async {
      final storage = _MemoryStorage([
        PendingSubscriptionSync(
          sessionId: 'session-a',
          requestId: 'request-a',
          signedTransactionInfo: 'jws-a',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
      ]);
      final api = _FakeApi();

      await SubscriptionSyncQueue(
        storage: storage,
        api: api,
      ).flush(_session('session-b'));

      expect(api.requests, isEmpty);
      expect(storage.entries, isEmpty);
    },
  );

  test(
    'terminal invalid evidence is removed so one bad transaction cannot block later syncs',
    () async {
      final storage = _MemoryStorage();
      final api = _FakeApi(
        errors: [
          const SubscriptionEntitlementApiException(
            code: 'EVIDENCE_INVALID',
            statusCode: 422,
          ),
          null,
        ],
      );
      final queue = SubscriptionSyncQueue(storage: storage, api: api);

      await queue.enqueueAndFlush(
        _session('session-a'),
        signedTransactionInfo: 'jws-invalid',
      );
      await queue.flush(_session('session-a'));
      await queue.enqueueAndFlush(
        _session('session-a'),
        signedTransactionInfo: 'jws-valid',
      );
      await queue.flush(_session('session-a'));

      expect(api.requests.map((request) => request.evidence), [
        'jws-invalid',
        'jws-valid',
      ]);
      expect(storage.entries, isEmpty);
    },
  );

  test(
    'state conflict is terminal because retrying a superseded lifecycle proof can never create a grant',
    () async {
      final storage = _MemoryStorage([
        PendingSubscriptionSync(
          sessionId: 'session-a',
          requestId: 'request-conflict',
          signedTransactionInfo: 'jws-conflict',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
        PendingSubscriptionSync(
          sessionId: 'session-a',
          requestId: 'request-current',
          signedTransactionInfo: 'jws-current',
          createdAt: DateTime.utc(2026, 8, 12),
        ),
      ]);
      final api = _FakeApi(
        errors: [
          const SubscriptionEntitlementApiException(
            code: 'STATE_CONFLICT',
            statusCode: 409,
          ),
          null,
        ],
      );

      await SubscriptionSyncQueue(
        storage: storage,
        api: api,
      ).flush(_session('session-a'));

      expect(api.requests.map((request) => request.evidence), [
        'jws-conflict',
        'jws-current',
      ]);
      expect(storage.entries, isEmpty);
    },
  );

  test('extracts only a non-empty session ID from the access token', () {
    expect(sessionIdFromAccessToken(_token('session-a')), 'session-a');
    expect(sessionIdFromAccessToken('not-a-jwt'), isNull);
    expect(sessionIdFromAccessToken(_token('')), isNull);
  });
}

class _BlockingApi implements SubscriptionEntitlementApi {
  final started = Completer<void>();
  final _completion = Completer<void>();

  void complete() => _completion.complete();

  @override
  Future<String> createPurchaseChallenge(
    AuthSession session, {
    required String productId,
  }) => throw UnimplementedError();

  @override
  Future<void> verifyFreshPurchase(
    AuthSession session, {
    required String requestId,
    required String signedTransactionInfo,
  }) async {
    if (!started.isCompleted) started.complete();
    await _completion.future;
  }
}

AuthSession _session(String sessionId) => AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: _token(sessionId),
  refreshToken: 'refresh-token',
  anonymousId: 'anon-1',
);

String _token(String sessionId) {
  final payload = base64Url.encode(
    utf8.encode(jsonEncode({'session_id': sessionId})),
  );
  return 'header.$payload.signature';
}

class _MemoryStorage implements SubscriptionSyncStorage {
  _MemoryStorage([List<PendingSubscriptionSync> initial = const []])
    : entries = List.of(initial);

  List<PendingSubscriptionSync> entries;

  @override
  Future<List<PendingSubscriptionSync>> read() async => List.of(entries);

  @override
  Future<void> write(List<PendingSubscriptionSync> entries) async {
    this.entries = List.of(entries);
  }
}

class _FakeApi implements SubscriptionEntitlementApi {
  _FakeApi({this.error, List<SubscriptionEntitlementApiException?>? errors})
    : _errors = errors ?? const [];

  final SubscriptionEntitlementApiException? error;
  final List<SubscriptionEntitlementApiException?> _errors;
  final requests = <({String requestId, String evidence})>[];

  @override
  Future<String> createPurchaseChallenge(
    AuthSession session, {
    required String productId,
  }) => throw UnimplementedError();

  @override
  Future<void> verifyFreshPurchase(
    AuthSession session, {
    required String requestId,
    required String signedTransactionInfo,
  }) async {
    requests.add((requestId: requestId, evidence: signedTransactionInfo));
    final indexedError = requests.length <= _errors.length
        ? _errors[requests.length - 1]
        : null;
    final failure = indexedError ?? error;
    if (failure != null) throw failure;
  }
}
