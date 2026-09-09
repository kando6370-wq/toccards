import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/apple_current_entitlements.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_api.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/features/subscription/subscription_sync_queue.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  test(
    'an active foreground session silently refreshes when its verified subscription reaches expiresAt',
    () async {
      final expiresAt = DateTime.now().toUtc().add(
        const Duration(milliseconds: 500),
      );
      final reader = _SequenceEntitlementReader([
        [
          AppleCurrentEntitlement(
            productId: 'com.cardai.tcg.pro.yearly',
            signedTransactionInfo: _jws({
              'productId': 'com.cardai.tcg.pro.yearly',
              'originalTransactionId': 'original-expiring',
              'transactionReason': 'PURCHASE',
              'signedDate': DateTime.now().toUtc().millisecondsSinceEpoch,
              'expiresDate': expiresAt.millisecondsSinceEpoch,
            }),
          ),
        ],
        const [],
      ]);
      final container = _container(
        queue: _TrackingSyncQueue(),
        lifecycle: const _ImmediateLifecycleApi([]),
        reader: reader,
        cache: _MemoryEntitlementCache(null),
      );
      addTearDown(container.dispose);
      final controller = container.read(
        subscriptionControllerProvider.notifier,
      );

      expect(await controller.refreshEntitlement(), AppPremiumState.premium);
      expect(reader.calls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(reader.calls, 2);
      expect(
        container.read(subscriptionControllerProvider).premiumState,
        AppPremiumState.free,
      );
    },
  );

  test(
    'a server denial keeps verified current Premium and synchronizes its missing session grant',
    () async {
      final queue = _TrackingSyncQueue();
      final lifecycle = _ImmediateLifecycleApi([
        ApplePurchaseChainLifecycle(
          originalTransactionId: 'original-active',
          productId: 'com.cardai.tcg.pro.yearly',
          lifecycleStatus: 'ACTIVE',
          stateEffectiveAt: DateTime.utc(2026, 8, 28, 10),
        ),
      ]);
      final reader = _FixedEntitlementReader([
        AppleCurrentEntitlement(
          productId: 'com.cardai.tcg.pro.yearly',
          signedTransactionInfo: _jws({
            'productId': 'com.cardai.tcg.pro.yearly',
            'originalTransactionId': 'original-active',
            'transactionReason': 'RENEWAL',
            'signedDate': DateTime.utc(2026, 8, 28, 9).millisecondsSinceEpoch,
            'expiresDate': DateTime.utc(2027).millisecondsSinceEpoch,
          }),
        ),
      ]);
      final container = _container(
        queue: queue,
        lifecycle: lifecycle,
        reader: reader,
        cache: _MemoryEntitlementCache(null),
      );
      addTearDown(container.dispose);

      final controller = container.read(
        subscriptionControllerProvider.notifier,
      );
      final first = controller.reconcileServerEntitlement();
      final second = controller.reconcileServerEntitlement();

      expect(await first, EntitlementReconciliationResult.premiumSynchronized);
      expect(await second, EntitlementReconciliationResult.premiumSynchronized);
      expect(queue.calls, 1);
      expect(reader.calls, 1);
      expect(
        container.read(subscriptionControllerProvider).premiumState,
        AppPremiumState.premium,
      );
    },
  );

  test(
    'a server denial does not downgrade cached Premium when StoreKit verification is unavailable',
    () async {
      final cache = _MemoryEntitlementCache(
        VerifiedEntitlementCache(
          state: AppPremiumState.premium,
          verifiedAt: DateTime.now().toUtc(),
          productId: 'com.cardai.tcg.pro.yearly',
          originalTransactionId: 'original-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        ),
      );
      final container = _container(
        queue: _TrackingSyncQueue(),
        lifecycle: const _ImmediateLifecycleApi([]),
        reader: const _ThrowingEntitlementReader(),
        cache: cache,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(subscriptionControllerProvider.notifier)
          .reconcileServerEntitlement();

      expect(result, EntitlementReconciliationResult.verificationUnavailable);
      expect(
        container.read(subscriptionControllerProvider).premiumState,
        AppPremiumState.premium,
      );
      expect(cache.value?.state, AppPremiumState.premium);
    },
  );

  test(
    'a server denial reconciles an empty current entitlement as Free so Premium UI can lock immediately',
    () async {
      final cache = _MemoryEntitlementCache(
        VerifiedEntitlementCache(
          state: AppPremiumState.premium,
          verifiedAt: DateTime.utc(2026, 8, 28, 10),
          productId: 'com.cardai.tcg.pro.yearly',
          originalTransactionId: 'original-1',
          expiresAt: DateTime.utc(2026, 8, 28, 11),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          appSubscriptionConfigurationProvider.overrideWithValue(
            const AppSubscriptionConfiguration(
              store: SubscriptionStore.appStore,
              productIds: {
                subscriptionYearlyPlanId: 'com.cardai.tcg.pro.yearly',
              },
            ),
          ),
          subscriptionEntitlementCacheStorageProvider.overrideWithValue(cache),
          appleLifecycleApiProvider.overrideWithValue(
            const _ImmediateLifecycleApi([]),
          ),
          appleCurrentEntitlementReaderProvider.overrideWithValue(
            _TrackingEntitlementReader(),
          ),
          subscriptionControllerProvider.overrideWith(
            _ServerSyncSubscriptionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        subscriptionControllerProvider.notifier,
      );
      final result = await controller.reconcileServerEntitlement();

      expect(result, EntitlementReconciliationResult.freeConfirmed);
      expect(
        container.read(subscriptionControllerProvider).premiumState,
        AppPremiumState.free,
      );
      expect(cache.value?.state, AppPremiumState.free);
    },
  );

  test(
    'concurrent repairs flush Fresh proof once and stop when the session grant is active',
    () async {
      final queue = _TrackingSyncQueue();
      final lifecycle = _ControlledLifecycleApi();
      final reader = _TrackingEntitlementReader();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          appSubscriptionConfigurationProvider.overrideWithValue(
            const AppSubscriptionConfiguration(
              store: SubscriptionStore.appStore,
              productIds: {
                subscriptionYearlyPlanId: 'com.cardai.tcg.pro.yearly',
              },
            ),
          ),
          subscriptionSyncQueueProvider.overrideWithValue(queue),
          appleLifecycleApiProvider.overrideWithValue(lifecycle),
          appleCurrentEntitlementReaderProvider.overrideWithValue(reader),
          subscriptionControllerProvider.overrideWith(
            _ServerSyncSubscriptionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        subscriptionControllerProvider.notifier,
      );

      final first = controller.synchronizeServerEntitlement();
      final second = controller.synchronizeServerEntitlement();
      await lifecycle.started.future;

      expect(queue.calls, 1);
      expect(lifecycle.calls, 1);
      expect(reader.calls, 0);

      lifecycle.complete(const [
        ApplePurchaseChainLifecycle(
          originalTransactionId: 'original-1',
          productId: 'com.cardai.tcg.pro.yearly',
          lifecycleStatus: 'ACTIVE',
        ),
      ]);

      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(queue.calls, 1);
      expect(lifecycle.calls, 1);
      expect(reader.calls, 0);
    },
  );
}

ProviderContainer _container({
  required SubscriptionSyncQueue queue,
  required AppleLifecycleApi lifecycle,
  required AppleCurrentEntitlementReader reader,
  required SubscriptionEntitlementCacheStorage cache,
}) {
  return ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(_ReadyAuthController.new),
      appSubscriptionConfigurationProvider.overrideWithValue(
        const AppSubscriptionConfiguration(
          store: SubscriptionStore.appStore,
          productIds: {subscriptionYearlyPlanId: 'com.cardai.tcg.pro.yearly'},
        ),
      ),
      subscriptionSyncQueueProvider.overrideWithValue(queue),
      appleLifecycleApiProvider.overrideWithValue(lifecycle),
      appleCurrentEntitlementReaderProvider.overrideWithValue(reader),
      subscriptionEntitlementCacheStorageProvider.overrideWithValue(cache),
      subscriptionControllerProvider.overrideWith(
        _ServerSyncSubscriptionController.new,
      ),
    ],
  );
}

String _jws(Map<String, Object?> payload) {
  final body = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'header.$body.signature';
}

class _ServerSyncSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.premium);
}

class _ReadyAuthController extends AuthController {
  @override
  AuthState build() => const AuthState.ready(
    session: AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'access',
      refreshToken: 'refresh',
      userId: 'user-1',
    ),
  );
}

class _TrackingSyncQueue extends SubscriptionSyncQueue {
  _TrackingSyncQueue()
    : super(storage: _UnusedSyncStorage(), api: _UnusedEntitlementApi());

  var calls = 0;

  @override
  Future<void> flush(AuthSession session) async {
    calls += 1;
  }
}

class _ControlledLifecycleApi implements AppleLifecycleApi {
  final started = Completer<void>();
  final _result = Completer<List<ApplePurchaseChainLifecycle>>();
  var calls = 0;

  @override
  Future<List<ApplePurchaseChainLifecycle>> loadCurrentSessionLifecycle(
    AuthSession session,
  ) {
    calls += 1;
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void complete(List<ApplePurchaseChainLifecycle> value) {
    _result.complete(value);
  }
}

class _ImmediateLifecycleApi implements AppleLifecycleApi {
  const _ImmediateLifecycleApi(this.value);

  final List<ApplePurchaseChainLifecycle> value;

  @override
  Future<List<ApplePurchaseChainLifecycle>> loadCurrentSessionLifecycle(
    AuthSession session,
  ) async => value;
}

class _TrackingEntitlementReader implements AppleCurrentEntitlementReader {
  var calls = 0;

  @override
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) async {
    calls += 1;
    return const [];
  }

  @override
  Future<void> synchronize() async {}
}

class _FixedEntitlementReader implements AppleCurrentEntitlementReader {
  _FixedEntitlementReader(this.value);

  final List<AppleCurrentEntitlement> value;
  var calls = 0;

  @override
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) async {
    calls += 1;
    return value;
  }

  @override
  Future<void> synchronize() async {}
}

class _SequenceEntitlementReader implements AppleCurrentEntitlementReader {
  _SequenceEntitlementReader(this.values);

  final List<List<AppleCurrentEntitlement>> values;
  var calls = 0;

  @override
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) async {
    final index = calls < values.length ? calls : values.length - 1;
    calls += 1;
    return values[index];
  }

  @override
  Future<void> synchronize() async {}
}

class _ThrowingEntitlementReader implements AppleCurrentEntitlementReader {
  const _ThrowingEntitlementReader();

  @override
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) {
    throw StateError('StoreKit unavailable');
  }

  @override
  Future<void> synchronize() async {}
}

class _MemoryEntitlementCache implements SubscriptionEntitlementCacheStorage {
  _MemoryEntitlementCache(this.value);

  VerifiedEntitlementCache? value;

  @override
  Future<VerifiedEntitlementCache?> read() async => value;

  @override
  Future<void> write(VerifiedEntitlementCache cache) async {
    value = cache;
  }
}

class _UnusedSyncStorage implements SubscriptionSyncStorage {
  @override
  Future<List<PendingSubscriptionSync>> read() async => const [];

  @override
  Future<void> write(List<PendingSubscriptionSync> entries) async {}
}

class _UnusedEntitlementApi implements SubscriptionEntitlementApi {
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
  }) => throw UnimplementedError();
}
