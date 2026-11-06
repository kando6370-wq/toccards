import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';

void main() {
  test(
    'Android free launch builds Free state without Apple or revenue side effects',
    () {
      final container = ProviderContainer(
        overrides: [
          appCommercialPolicyProvider.overrideWithValue(
            const AppCommercialPolicy(isAndroidFreeLaunch: true),
          ),
          authControllerProvider.overrideWith(
            () => _UnexpectedAuthController(),
          ),
          appSubscriptionConfigurationProvider.overrideWith(
            (ref) =>
                throw StateError('Android must not load Apple configuration.'),
          ),
          subscriptionSyncQueueProvider.overrideWith(
            (ref) =>
                throw StateError('Android must not initialize sync queue.'),
          ),
          subscriptionRevenueReporterProvider.overrideWith(
            (ref) => throw StateError(
              'Android must not initialize revenue reporter.',
            ),
          ),
          singularSubscriptionRevenueReporterProvider.overrideWith(
            (ref) => throw StateError(
              'Android must not initialize Singular revenue.',
            ),
          ),
          subscriptionStoreGatewayProvider.overrideWith(
            (ref) => throw StateError(
              'Android must not initialize StoreKit gateway.',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(subscriptionControllerProvider);

      expect(state.premiumState, AppPremiumState.free);
      expect(state.isPro, isFalse);
      expect(state.isConfigured, isFalse);
      expect(state.isLoading, isFalse);
    },
  );
}

class _UnexpectedAuthController extends AuthController {
  @override
  AuthState build() {
    throw StateError(
      'Android subscription state must not watch authentication.',
    );
  }
}
