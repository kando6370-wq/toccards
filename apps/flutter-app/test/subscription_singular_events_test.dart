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

  for (final item in [
    (
      plan: 'weekly_trial',
      product: 'weekly.trial',
      name: 'card_weekly_trialtest',
    ),
    (plan: 'yearly_pro', product: 'yearly.pro', name: 'yearly_cardtest'),
    (plan: 'monthly', product: 'cardx.month', name: 'card_monthlytest'),
  ]) {
    test(
      'dev maps ${item.product} by actual Product ID without enabling it in production',
      () {
        expect(
          singularSubscriptionSuccessEventName(
            event: _event(planId: item.plan, productId: item.product),
            environment: AppEnvironment.test,
            isFreshPurchase: true,
          ),
          item.name,
        );
        expect(
          singularSubscriptionSuccessEventName(
            event: _event(planId: item.plan, productId: item.product),
            environment: AppEnvironment.production,
            isFreshPurchase: true,
          ),
          isNull,
        );
        expect(
          singularSubscriptionSuccessEventName(
            event: _event(planId: item.plan, productId: 'unregistered.product'),
            environment: AppEnvironment.test,
            isFreshPurchase: true,
          ),
          isNull,
        );
      },
    );
  }
  test(
    'the trial Product ID determines its event even if a plan label is yearly',
    () {
      expect(
        singularSubscriptionSuccessEventName(
          event: _event(planId: 'yearly', productId: 'weekly.trial'),
          environment: AppEnvironment.test,
          isFreshPurchase: true,
        ),
        'card_weekly_trialtest',
      );
    },
  );

  for (final item in [
    (
      product: 'CardAi.weekly.trial',
      plan: 'weekly_trial',
      name: 'card_weekly_trial',
    ),
    (product: 'CardAi.monthly', plan: 'monthly', name: 'card_monthly'),
  ]) {
    test('production maps ${item.product} by actual Product ID', () {
      expect(
        singularSubscriptionSuccessEventName(
          event: _event(planId: item.plan, productId: item.product),
          environment: AppEnvironment.production,
          isFreshPurchase: true,
        ),
        item.name,
      );
    });
  }

  test('unknown plans never produce an event name', () {
    expect(
      singularSubscriptionSuccessEventName(
        event: _event(planId: 'unrecognized'),
        environment: AppEnvironment.test,
        isFreshPurchase: true,
      ),
      isNull,
    );
  });
}

SubscriptionEvent _event({
  required String planId,
  String? productId,
  SubscriptionPurchaseStatus status = SubscriptionPurchaseStatus.purchased,
  SubscriptionEntitlementStatus entitlementStatus =
      SubscriptionEntitlementStatus.active,
  SubscriptionFailure? failure,
}) {
  return SubscriptionEvent(
    purchase: SubscriptionPurchase(
      store: SubscriptionStore.appStore,
      storeProductId: productId ?? 'cardx.$planId',
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
