import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/subscription/subscription_singular_events.dart';
import 'package:kando_app/shared/api/api_environment.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  for (final testCase
      in <({AppEnvironment environment, String planId, String eventName})>[
        (
          environment: AppEnvironment.test,
          planId: 'weekly',
          eventName: 'weekly_cardtest',
        ),
        (
          environment: AppEnvironment.test,
          planId: 'yearly',
          eventName: 'yearly_cardtest',
        ),
        (
          environment: AppEnvironment.test,
          planId: 'lifetime',
          eventName: 'lifetime_cardtest',
        ),
        (
          environment: AppEnvironment.production,
          planId: 'weekly',
          eventName: 'weekly_card',
        ),
        (
          environment: AppEnvironment.production,
          planId: 'yearly',
          eventName: 'yearly_card',
        ),
        (
          environment: AppEnvironment.production,
          planId: 'lifetime',
          eventName: 'lifetime_card',
        ),
      ]) {
    test('${testCase.environment.name} ${testCase.planId} maps to '
        '${testCase.eventName}', () {
      expect(
        singularSubscriptionSuccessEventName(
          event: _event(planId: testCase.planId),
          environment: testCase.environment,
          isFreshPurchase: true,
        ),
        testCase.eventName,
      );
    });
  }

  test(
    'restore, external unlock, failures, and inactive plans do not report',
    () {
      expect(
        singularSubscriptionSuccessEventName(
          event: _event(
            planId: 'weekly',
            status: SubscriptionPurchaseStatus.restored,
          ),
          environment: AppEnvironment.test,
          isFreshPurchase: true,
        ),
        isNull,
      );
      expect(
        singularSubscriptionSuccessEventName(
          event: _event(planId: 'weekly'),
          environment: AppEnvironment.test,
          isFreshPurchase: false,
        ),
        isNull,
      );
      expect(
        singularSubscriptionSuccessEventName(
          event: _event(
            planId: 'weekly',
            failure: const SubscriptionFailure(
              code: 'verification_failed',
              message: 'failed',
            ),
          ),
          environment: AppEnvironment.test,
          isFreshPurchase: true,
        ),
        isNull,
      );
      expect(
        singularSubscriptionSuccessEventName(
          event: _event(
            planId: 'weekly',
            entitlementStatus: SubscriptionEntitlementStatus.expired,
          ),
          environment: AppEnvironment.test,
          isFreshPurchase: true,
        ),
        isNull,
      );
    },
  );

  test('unknown plans never produce an event name', () {
    expect(
      singularSubscriptionSuccessEventName(
        event: _event(planId: 'monthly'),
        environment: AppEnvironment.test,
        isFreshPurchase: true,
      ),
      isNull,
    );
  });
}

SubscriptionEvent _event({
  required String planId,
  SubscriptionPurchaseStatus status = SubscriptionPurchaseStatus.purchased,
  SubscriptionEntitlementStatus entitlementStatus =
      SubscriptionEntitlementStatus.active,
  SubscriptionFailure? failure,
}) {
  return SubscriptionEvent(
    purchase: SubscriptionPurchase(
      store: SubscriptionStore.appStore,
      storeProductId: 'cardx.$planId',
      status: status,
      verificationData: 'verified-jws',
    ),
    entitlement: SubscriptionEntitlement(
      planId: planId,
      entitlementId: 'performance_pro',
      status: entitlementStatus,
    ),
    failure: failure,
  );
}
