import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/scan_quota_controller.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';
import 'package:kando_app/shared/scan/scan_providers.dart';

void main() {
  test(
    'expired Premium clears stale Unlimited by retrying quota with the reconciled Free state',
    () async {
      final api = _ExpiredPremiumQuotaApi();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          scanApiClientProvider.overrideWithValue(api),
          subscriptionControllerProvider.overrideWith(
            _ExpiredSubscriptionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      final quota = container.read(scanQuotaControllerProvider.notifier);
      quota.applyServerQuota(
        const ScanQuotaDto(
          access: ScanQuotaAccess.premium,
          limit: 10,
          reserved: 0,
          consumed: 10,
          remaining: 0,
          unlimited: true,
        ),
      );

      expect(await quota.refresh(), isTrue);

      expect(api.localPremiumStates, [true, false]);
      expect(container.read(scanQuotaControllerProvider).unlimited, isFalse);
      expect(container.read(scanQuotaControllerProvider).remainingScans, 0);
      expect(
        container.read(subscriptionControllerProvider).premiumState,
        AppPremiumState.free,
      );
    },
  );

  test(
    'a non-409 response cannot trigger entitlement reconciliation',
    () async {
      final api = _ExpiredPremiumQuotaApi(statusCode: 400);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          scanApiClientProvider.overrideWithValue(api),
          subscriptionControllerProvider.overrideWith(
            _UnexpectedReconciliationSubscriptionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(scanQuotaControllerProvider.notifier).refresh(),
        isFalse,
      );
      expect(api.localPremiumStates, [true]);
    },
  );
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

class _ExpiredSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.premium);

  @override
  Future<EntitlementReconciliationResult> reconcileServerEntitlement() async {
    state = state.copyWith(premiumState: AppPremiumState.free);
    return EntitlementReconciliationResult.freeConfirmed;
  }
}

class _UnexpectedReconciliationSubscriptionController
    extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.premium);

  @override
  Future<EntitlementReconciliationResult> reconcileServerEntitlement() {
    throw StateError('Non-409 responses must not reconcile entitlement.');
  }
}

class _ExpiredPremiumQuotaApi extends ScanApiClient {
  _ExpiredPremiumQuotaApi({this.statusCode = 409}) : super(Dio());

  final int statusCode;
  final localPremiumStates = <bool>[];

  @override
  Future<ScanQuotaDto> getQuota(
    AuthSession session, {
    bool localPremiumVerified = false,
  }) async {
    localPremiumStates.add(localPremiumVerified);
    if (localPremiumVerified) {
      throw ScanApiException(
        'Premium access is still syncing.',
        code: 'ENTITLEMENT_SYNC_REQUIRED',
        statusCode: statusCode,
      );
    }
    return const ScanQuotaDto(
      access: ScanQuotaAccess.free,
      limit: 10,
      reserved: 0,
      consumed: 10,
      remaining: 0,
      unlimited: false,
    );
  }
}
