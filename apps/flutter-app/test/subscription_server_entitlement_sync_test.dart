import 'dart:async';

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
