import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/features/profile/profile_actions.dart';
import 'package:kando_app/features/subscription/apple_current_entitlements.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_analytics.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/features/subscription/subscription_page.dart';
import 'package:kando_app/features/subscription/subscription_display_controller.dart';
import 'package:kando_app/features/subscription/subscription_display_config.dart';
import 'package:kando_app/features/subscription/subscription_display_providers.dart';
import 'package:kando_app/features/subscription/subscription_product_support.dart';
import 'package:kando_app/features/subscription/subscription_store_product.dart';
import 'subscription_display_fixtures.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';
import 'package:kando_app/shared/ui/kando_bottom_sheet_page.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  testWidgets(
    'onboarding subscription view reports the guide analytics scene',
    (tester) async {
      final events = <(String, Map<String, Object?>)>[];
      final analytics = AppAnalytics.recording(
        (event, properties) => events.add((event, properties)),
      );
      final host = _RestoreTestHost(analytics: analytics);
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription?source=onboarding');
      await tester.pumpAndSettle();

      expect(
        events.where((entry) => entry.$1 == 'subscribe_view').map((e) => e.$2),
        [containsPair('Scene', 'guide')],
      );
    },
  );

  testWidgets(
    'subscription click reports selected SKU price currency and Scene',
    (tester) async {
      final events = <(String, Map<String, Object?>)>[];
      final analytics = AppAnalytics.recording(
        (event, properties) => events.add((event, properties)),
      );
      final host = _RestoreTestHost(
        analytics: analytics,
        controller: _AnalyticsPurchaseController(),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription?source=onboarding');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('subscription-purchase-button')),
      );
      await tester.tap(find.byKey(const Key('subscription-purchase-button')));
      await tester.pump();

      final click = events.singleWhere((entry) => entry.$1 == 'sub_click').$2;
      expect(click, containsPair('plan', 'yearly.product'));
      expect(click, containsPair('currency', 'USD'));
      expect(click, containsPair('price', 49.99));
      expect(click, containsPair('Scene', 'guide'));
    },
  );

  test('Restore outcome recalculates only from the latest verified result', () {
    expect(
      resolvePremiumStateAfterRestore(
        AppPremiumState.premium,
        AppleRestoreResult.notFound,
      ),
      AppPremiumState.free,
    );
    expect(
      resolvePremiumStateAfterRestore(
        AppPremiumState.free,
        AppleRestoreResult.success('verified-jws'),
      ),
      AppPremiumState.premium,
    );
    expect(
      resolvePremiumStateAfterRestore(AppPremiumState.premium, null),
      AppPremiumState.premium,
      reason: 'Restore failure or timeout must preserve the prior truth.',
    );
  });

  test('Restore cancellation does not emit a result dialog event', () {
    expect(
      subscriptionRestoreFailureEvent(
        PlatformException(code: appleRestoreCancelledErrorCode),
      ),
      isNull,
    );
    expect(
      subscriptionRestoreFailureEvent(
        PlatformException(code: 'apple_restore_failed'),
      ),
      SubscriptionResultEvent.restoreFailed,
    );
    expect(
      subscriptionRestoreFailureEvent(TimeoutException('restore')),
      SubscriptionResultEvent.restoreFailed,
    );
  });

  test('one configured SKU keeps the remaining StoreKit catalog usable', () {
    const configuration = AppSubscriptionConfiguration(
      store: SubscriptionStore.appStore,
      productIds: {
        subscriptionWeeklyPlanId: 'weekly.product',
        subscriptionYearlyPlanId: '',
        subscriptionLifetimePlanId: '',
      },
    );

    expect(configuration.isConfigured, isTrue);
    expect(configuration.configuredProductIds, {
      subscriptionWeeklyPlanId: 'weekly.product',
    });
  });

  test(
    'loaded StoreKit products must match the current purchase environment',
    () {
      const configuration = AppSubscriptionConfiguration(
        store: SubscriptionStore.appStore,
        productIds: {
          subscriptionWeeklyPlanId: 'weekly.product',
          subscriptionYearlyPlanId: 'yearly.product',
        },
      );
      const loaded = SubscriptionState(
        isConfigured: true,
        displayPrices: {
          subscriptionWeeklyPlanId: r'$4.99',
          subscriptionYearlyPlanId: r'$49.99',
        },
        analyticsProducts: {
          subscriptionWeeklyPlanId: SubscriptionProductAnalytics(
            sku: 'weekly.product',
            currency: 'USD',
            price: 4.99,
          ),
          subscriptionYearlyPlanId: SubscriptionProductAnalytics(
            sku: 'yearly.product',
            currency: 'USD',
            price: 49.99,
          ),
        },
        availablePlanIds: {subscriptionWeeklyPlanId, subscriptionYearlyPlanId},
      );

      expect(loaded.hasLoadedProductsFor(configuration), isTrue);
      expect(
        loaded.hasLoadedProductsFor(
          const AppSubscriptionConfiguration(
            store: SubscriptionStore.appStore,
            productIds: {
              subscriptionWeeklyPlanId: 'weekly.product.v2',
              subscriptionYearlyPlanId: 'yearly.product',
            },
          ),
        ),
        isFalse,
      );
      expect(
        loaded
            .copyWith(availablePlanIds: const {subscriptionWeeklyPlanId})
            .hasLoadedProductsFor(configuration),
        isFalse,
      );
      expect(
        subscriptionPurchaseEnvironmentChanged(
          loaded: 'appStore:USA',
          current: 'appStore:CAN',
        ),
        isTrue,
      );
      expect(
        subscriptionPurchaseEnvironmentChanged(
          loaded: 'appStore:USA',
          current: null,
        ),
        isFalse,
        reason: 'A failed storefront read must not invalidate loaded products.',
      );
    },
  );

  test('USD fallback prices require a configured App Store catalog', () {
    expect(
      const SubscriptionState().displayPriceFor(subscriptionWeeklyPlanId),
      'Unavailable',
    );
    expect(
      const SubscriptionState(
        isConfigured: true,
      ).displayPriceFor(subscriptionWeeklyPlanId),
      r'$3.99',
    );
    expect(
      const SubscriptionState(
        isConfigured: true,
        displayPrices: {subscriptionWeeklyPlanId: r'CA$4.99'},
      ).displayPriceFor(subscriptionWeeklyPlanId),
      r'CA$4.99',
    );
  });

  test(
    'Android keeps subscription sales disabled because v1.1 has no Google Play proof contract',
    () {
      final configuration = AppSubscriptionConfiguration.fromEnvironment(
        platform: TargetPlatform.android,
      );

      expect(configuration.store, isNull);
      expect(configuration.configuredProductIds, isEmpty);
      expect(configuration.isConfigured, isFalse);
    },
  );

  group('subscription purchase feedback', () {
    test('maps known StoreKit start failures to specific messages', () {
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(code: 'storekit_duplicate_product_object'),
        ),
        subscriptionDuplicatePurchaseMessage,
      );
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(
            code: 'storekit2_purchase_error',
            message: 'ASDErrorDomain Code=509 No active account',
          ),
        ),
        subscriptionAppStoreAccountMessage,
      );
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(code: 'storekit2_failed_to_fetch_product'),
        ),
        subscriptionProductUnavailableMessage,
      );
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(code: 'Error Domain=StoreKit.StoreKitError Code=3'),
        ),
        subscriptionAppStoreTemporaryMessage,
      );
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(
            code: 'storekit2_purchase_error',
            details: const {'domain': 'StoreKit.StoreKitError', 'code': 3},
          ),
        ),
        subscriptionAppStoreTemporaryMessage,
      );
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(code: 'Error Domain=SKErrorDomain Code=4'),
        ),
        subscriptionPurchasesDisabledMessage,
      );
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(code: 'future_storekit_error'),
        ),
        contains('future_storekit_error'),
      );
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(
            code: 'Error Domain=FutureStoreError Code=42 details',
          ),
        ),
        contains('FutureStoreError_42'),
      );
      expect(
        subscriptionPurchaseStartErrorMessage(
          PlatformException(
            code: 'storekit2_purchase_error',
            details: const {'domain': 'FutureStoreError', 'code': 42},
          ),
        ),
        contains('FutureStoreError_42'),
      );
    });

    test('maps purchase events without a generic fallback', () {
      expect(
        subscriptionPurchaseFeedbackMessage(
          const SubscriptionEvent(
            failure: SubscriptionFailure(
              code: 'verification_failed',
              message: 'Purchase verification failed.',
            ),
          ),
        ),
        subscriptionPurchaseVerificationMessage,
      );
      expect(
        subscriptionPurchaseFeedbackMessage(
          const SubscriptionEvent(
            purchase: SubscriptionPurchase(
              store: SubscriptionStore.appStore,
              storeProductId: 'weekly.product',
              status: SubscriptionPurchaseStatus.failed,
              verificationData: '',
              errorCode: 'purchase_error',
            ),
            failure: SubscriptionFailure(
              code: 'purchase_error',
              message: 'Purchase failed.',
            ),
          ),
        ),
        contains('purchase_error'),
      );
      expect(
        subscriptionPurchaseFeedbackMessage(
          const SubscriptionEvent(
            purchase: SubscriptionPurchase(
              store: SubscriptionStore.appStore,
              storeProductId: 'weekly.product',
              status: SubscriptionPurchaseStatus.canceled,
              verificationData: '',
            ),
          ),
        ),
        subscriptionPurchaseCanceledMessage,
      );
    });
  });

  test(
    'product loading retries three transient failures within one deadline',
    () async {
      var attempts = 0;

      final loaded = await loadSubscriptionProductsWithRetry(
        () async {
          attempts += 1;
          if (attempts < 4) throw StateError('temporary StoreKit failure');
          return true;
        },
        deadline: const Duration(seconds: 1),
        retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
      );

      expect(loaded, isTrue);
      expect(attempts, 4);
    },
  );

  test(
    'product loading stops at its shared deadline and ignores a late result',
    () async {
      final pending = Completer<bool>();
      var attempts = 0;

      final loaded = loadSubscriptionProductsWithRetry(
        () {
          attempts += 1;
          return pending.future;
        },
        deadline: const Duration(milliseconds: 10),
        retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
      );

      await expectLater(loaded, completion(isFalse));
      expect(attempts, 1);
      pending.complete(true);
    },
  );

  test(
    'product loading stops retrying after its page context is closed',
    () async {
      var contextActive = true;
      var attempts = 0;

      final loaded = loadSubscriptionProductsWithRetry(
        () async {
          attempts += 1;
          contextActive = false;
          return false;
        },
        shouldContinue: () => contextActive,
        retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
      );

      await expectLater(loaded, completion(isFalse));
      expect(attempts, 1);
    },
  );

  testWidgets('Terms keeps Full Subscription Page plan and source context', (
    tester,
  ) async {
    final actions = _RecordingProfileActions();
    final host = _RestoreTestHost(actions: actions);
    await tester.pumpWidget(host.app);
    await tester.pumpAndSettle();

    host.router.push('/subscription?source=source');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subscription-plan-weekly')));
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Terms of Use'));
    await tester.tap(find.text('Terms of Use'));
    await tester.pump();

    expect(actions.termsOpenCount, 1);
    expect(find.byType(SubscriptionPage), findsOneWidget);
    expect(host.controller.state.selectedPlanId, subscriptionWeeklyPlanId);
  });

  testWidgets('Privacy keeps Paywall plan and underlying source context', (
    tester,
  ) async {
    final actions = _RecordingProfileActions();
    final host = _RestoreTestHost(actions: actions);
    await tester.pumpWidget(host.app);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-state')), 'kept');

    host.router.push('/subscription?sheet=true&source=source');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subscription-plan-weekly')));
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Privacy Policy'));
    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();

    expect(actions.privacyOpenCount, 1);
    expect(find.byType(SubscriptionPage), findsOneWidget);
    expect(host.controller.state.selectedPlanId, subscriptionWeeklyPlanId);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Source Page'), findsOneWidget);
    expect(find.text('kept'), findsOneWidget);
  });

  testWidgets('subscription sheet handle drag closes to its source', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetPadding);
    final host = _RestoreTestHost();
    await tester.pumpWidget(host.app);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-state')), 'kept');

    host.router.push('/subscription?sheet=true&source=source');
    await tester.pumpAndSettle();
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester
          .getSize(find.byKey(const Key('subscription-sheet-surface')))
          .height,
      lessThanOrEqualTo(viewportHeight * subscriptionSheetHeightFactor),
    );
    final topSafeArea = tester.view.padding.top / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byKey(const Key('subscription-sheet-handle'))).top,
      greaterThanOrEqualTo(topSafeArea),
    );
    await tester.drag(
      find.byKey(const Key('subscription-sheet-handle')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SubscriptionPage), findsNothing);
    expect(find.text('Source Page'), findsOneWidget);
    expect(find.text('kept'), findsOneWidget);
  });

  testWidgets(
    'a new subscription presentation resets the selected plan to yearly',
    (tester) async {
      final host = _RestoreTestHost();
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription?source=cold_start');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('subscription-plan-weekly')));
      await tester.pumpAndSettle();
      expect(host.controller.state.selectedPlanId, subscriptionWeeklyPlanId);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      host.router.push('/subscription?sheet=true&source=home');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionPage), findsOneWidget);
      expect(host.controller.state.selectedPlanId, subscriptionYearlyPlanId);
      expect(
        find.descendant(
          of: find.byKey(const Key('subscription-plan-yearly')),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a mounted subscription page keeps its loaded StoreKit products across foreground resumes',
    (tester) async {
      final controller = _ProductRefreshController();
      final host = _RestoreTestHost(controller: controller);
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();
      expect(controller.productRefreshCount, 1);
      expect(controller.productRefreshLoadingModes, [true]);

      _sendAppToBackground(tester);
      _returnAppToForeground(tester);
      await tester.pump();

      expect(controller.productRefreshCount, 1);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      _sendAppToBackground(tester);
      _returnAppToForeground(tester);
      await tester.pump();

      expect(controller.productRefreshCount, 1);

      host.router.push('/subscription');
      await tester.pumpAndSettle();

      expect(controller.productRefreshCount, 2);
      expect(controller.productRefreshLoadingModes, [true, true]);
    },
  );

  testWidgets(
    'returning to a mounted subscription page retries StoreKit products when its catalog is incomplete',
    (tester) async {
      final controller = _ProductRefreshController(hasLoadedProducts: false);
      final host = _RestoreTestHost(controller: controller);
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();
      expect(controller.productRefreshCount, 1);
      expect(controller.productRefreshLoadingModes, [true]);

      _sendAppToBackground(tester);
      _returnAppToForeground(tester);
      await tester.pump();

      expect(controller.productRefreshCount, 2);
      expect(controller.productRefreshLoadingModes, [true, false]);
      expect(controller.state.isLoading, isFalse);
    },
  );

  testWidgets(
    'Restore Success returns to its source with restore copy and never opens Purchase Success',
    (tester) async {
      final host = _RestoreTestHost();
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();
      expect(find.text('Choose Your Plan'), findsOneWidget);

      host.controller.emit(SubscriptionResultEvent.restoreSuccess, isPro: true);
      await tester.pump();

      expect(find.text('Source Page'), findsOneWidget);
      expect(find.text('Premium restored'), findsOneWidget);
      expect(find.text("You're Premium!"), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'Restore Not Found keeps Subscription Page open and refreshes the message independently from failure',
    (tester) async {
      final host = _RestoreTestHost();
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();
      host.controller.emit(SubscriptionResultEvent.restoreNotFound);
      await tester.pump();

      expect(find.text('Choose Your Plan'), findsOneWidget);
      expect(find.text('No subscription found'), findsOneWidget);
      expect(find.text('Restore failed'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'Restore Failed keeps Subscription Page and requires OK before retrying',
    (tester) async {
      final host = _RestoreTestHost();
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();
      host.controller.emit(SubscriptionResultEvent.restoreFailed);
      await tester.pumpAndSettle();

      expect(find.text('Choose Your Plan'), findsOneWidget);
      expect(find.text('Restore failed'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again later.'),
        findsOneWidget,
      );
      expect(find.text('OK'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Restore failed'), findsNothing);
      expect(find.text('Choose Your Plan'), findsOneWidget);
    },
  );

  testWidgets(
    'missing StoreKit products use USD fallback prices without replacing the first available selection',
    (tester) async {
      final host = _RestoreTestHost(controller: _PartialCatalogController());
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('subscription-plan-yearly')),
          matching: find.text(r'$49.99'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('subscription-plan-lifetime')),
          matching: find.text(r'$79.99'),
        ),
        findsOneWidget,
      );
      expect(find.text(r'$4.99'), findsOneWidget);
      expect(find.text('Unavailable'), findsNothing);
      await tester.tap(
        find.byKey(const Key('subscription-plan-yearly')),
        warnIfMissed: false,
      );
      expect(host.controller.state.selectedPlanId, subscriptionWeeklyPlanId);
      expect(host.controller.state.unavailablePlanIds, {
        subscriptionYearlyPlanId,
        subscriptionLifetimePlanId,
      });
    },
  );

  testWidgets(
    'all unavailable products show USD fallbacks without a StoreKit selection',
    (tester) async {
      final host = _RestoreTestHost(
        controller: _UnavailableCatalogController(),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.text(r'$3.99'), findsOneWidget);
      expect(find.text(r'$49.99'), findsOneWidget);
      expect(find.text(r'$79.99'), findsOneWidget);
      expect(find.text('Unavailable'), findsNothing);
      expect(host.controller.state.availablePlanIds, isEmpty);
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      final purchase = tester.widget<FilledButton>(
        find.byKey(const Key('subscription-purchase-button')),
      );
      expect(purchase.onPressed, isNotNull);
    },
  );

  testWidgets(
    'iOS configured page keeps actual price, selection and billing summary in sync',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final host = _RestoreTestHost();
        await tester.pumpWidget(host.app);
        await tester.pumpAndSettle();
        host.router.push('/subscription');
        await tester.pumpAndSettle();
        expect(host.display!.selectedId, 'yearly.product');
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView).last,
              matching: find.byType(Scrollable),
            )
            .last;
        await tester.scrollUntilVisible(
          find.byKey(const Key('subscription-config-product-yearly.product')),
          160,
          scrollable: scrollable,
        );
        expect(find.text('Yearly'), findsOneWidget);
        final weekly = find.byKey(
          const Key('subscription-config-product-weekly.product'),
        );
        await tester.scrollUntilVisible(weekly, -160, scrollable: scrollable);
        await tester.tap(weekly);
        await tester.pumpAndSettle();
        expect(host.display!.selectedId, 'weekly.product');
        expect(host.display!.selectedCard!.product.product.rawPrice, 3.99);
        await tester.ensureVisible(
          find.byKey(const Key('subscription-billing-summary')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('subscription-billing-summary')),
              )
              .data,
          contains('every 1 week'),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final sheet in [false, true]) {
    testWidgets(
      'custom billing copy replaces the summary above purchase ${sheet ? 'modal' : 'page'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        try {
          final host = _RestoreTestHost(
            includeTrial: true,
            displayConfiguration: SubscriptionDisplayConfig(
              pageType: sheet
                  ? SubscriptionPageType.modal
                  : SubscriptionPageType.page,
              trialEnabled: true,
              trialToggleText: 'Enable Free Trial',
              skus: const [
                SubscriptionDisplaySku(
                  productId: 'weekly.product',
                  type: DisplayProductType.subscription,
                  isDefault: true,
                  copy: SubscriptionCopy(
                    name: 'Weekly',
                    billingNote: 'Weekly charge: {price}',
                    autoBillingNote: false,
                  ),
                  trial: SubscriptionTrial(
                    productId: 'weekly.trial',
                    copy: SubscriptionCopy(
                      name: 'Weekly trial',
                      billingNote: 'Trial first, then {price}',
                      autoBillingNote: false,
                    ),
                  ),
                ),
                SubscriptionDisplaySku(
                  productId: 'yearly.product',
                  type: DisplayProductType.subscription,
                  copy: SubscriptionCopy(name: 'Yearly'),
                ),
              ],
            ),
          );
          await tester.pumpWidget(host.app);
          await tester.pumpAndSettle();
          host.router.push('/subscription${sheet ? '?sheet=true' : ''}');
          await tester.pumpAndSettle();

          final purchase = find.byKey(
            const Key('subscription-purchase-button'),
          );
          final customNote = find.byKey(
            const Key('subscription-billing-custom-note'),
          );
          final summary = find.byKey(const Key('subscription-billing-summary'));
          expect(host.display!.selectedCard!.product.id, 'weekly.product');
          expect(
            tester.widget<Text>(customNote).data,
            'Weekly charge: USD 3.99',
          );
          expect(summary, findsNothing);
          expect(
            tester.getRect(customNote).bottom,
            lessThanOrEqualTo(tester.getRect(purchase).top),
          );

          await tester.tap(find.byKey(const Key('subscription-trial-switch')));
          await tester.pumpAndSettle();
          expect(host.display!.selectedCard!.product.id, 'weekly.trial');
          expect(
            tester.widget<Text>(customNote).data,
            'Trial first, then USD 3.99',
          );
          expect(find.text('Weekly charge: USD 3.99'), findsNothing);
          expect(summary, findsNothing);
          expect(
            tester.getRect(customNote).bottom,
            lessThanOrEqualTo(tester.getRect(purchase).top),
          );

          final yearly = find.byKey(
            const Key('subscription-config-product-yearly.product'),
          );
          await tester.ensureVisible(yearly);
          await tester.tap(yearly);
          await tester.pumpAndSettle();
          expect(host.display!.selectedCard!.product.id, 'yearly.product');
          expect(customNote, findsNothing);
          expect(tester.widget<Text>(summary).data, contains('every 1 year'));
          expect(
            tester.getRect(summary).bottom,
            lessThanOrEqualTo(tester.getRect(purchase).top),
          );
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets('empty custom billing copy leaves no note above purchase', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final host = _RestoreTestHost(
        displayConfiguration: SubscriptionDisplayConfig(
          pageType: SubscriptionPageType.page,
          skus: const [
            SubscriptionDisplaySku(
              productId: 'weekly.product',
              type: DisplayProductType.subscription,
              isDefault: true,
              copy: SubscriptionCopy(name: 'Weekly', autoBillingNote: false),
            ),
          ],
        ),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      host.router.push('/subscription');
      await tester.pumpAndSettle();

      expect(host.display!.selectedCard!.product.id, 'weekly.product');
      expect(
        find.byKey(const Key('subscription-billing-custom-note')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('subscription-billing-summary')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('subscription-purchase-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final eligibility in TrialEligibility.values) {
    testWidgets(
      'independent trial custom copy does not wait for $eligibility eligibility',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final host = _RestoreTestHost(
            includeTrial: true,
            trialEligibility: Future<TrialEligibility>.value(eligibility),
            displayConfiguration: SubscriptionDisplayConfig(
              pageType: SubscriptionPageType.page,
              skus: const [
                SubscriptionDisplaySku(
                  productId: 'weekly.trial',
                  type: DisplayProductType.subscription,
                  isDefault: true,
                  copy: SubscriptionCopy(
                    name: 'Trial',
                    autoBillingNote: false,
                    billingNote: 'Start free, then {price}',
                  ),
                ),
              ],
            ),
          );
          await tester.pumpWidget(host.app);
          await tester.pumpAndSettle();
          host.router.push('/subscription');
          await tester.pumpAndSettle();

          expect(host.display!.selectedCard!.product.id, 'weekly.trial');
          final custom = find.byKey(
            const Key('subscription-billing-custom-note'),
          );
          expect(tester.widget<Text>(custom).data, 'Start free, then USD 3.99');
          expect(
            find.byKey(const Key('subscription-billing-summary')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets('configured paywall follows the Figma two-plan layout', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    try {
      final host = _RestoreTestHost(
        displayConfiguration: SubscriptionDisplayConfig(
          pageType: SubscriptionPageType.page,
          skus: [
            SubscriptionDisplaySku(
              productId: 'weekly.product',
              type: DisplayProductType.subscription,
              copy: SubscriptionCopy(
                name: 'Weekly',
                subtitle: 'Every week',
                priceNote: 'new per week',
              ),
            ),
            SubscriptionDisplaySku(
              productId: 'yearly.product',
              type: DisplayProductType.subscription,
              isDefault: true,
              weeklyReference: true,
              copy: SubscriptionCopy(
                name: 'Yearly',
                subtitle: 'Every year',
                priceNote: 'new per year',
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      host.router.push('/subscription');
      await tester.pumpAndSettle();

      final weekly = find.byKey(
        const Key('subscription-config-product-weekly.product'),
      );
      final yearly = find.byKey(
        const Key('subscription-config-product-yearly.product'),
      );
      expect(tester.getSize(weekly).height, 74);
      expect(tester.getSize(yearly).height, 74);
      expect(tester.getRect(yearly).top - tester.getRect(weekly).bottom, 20);
      expect(
        find.descendant(of: weekly, matching: find.text('new per week')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: weekly, matching: find.text('per week')),
        findsNothing,
      );
      expect(
        find.descendant(of: yearly, matching: find.text('USD 2.77 per week')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: yearly, matching: find.text('per year')),
        findsNothing,
      );
      expect(find.byKey(const Key('subscription-trial-switch')), findsNothing);
      expect(find.text('NO PAYMENT NOW'), findsNothing);
      expect(find.text('CANCEL ANYTIME'), findsNothing);
      final purchase = find.byKey(const Key('subscription-purchase-button'));
      expect(tester.getSize(purchase).width, 350);
      expect(tester.getSize(purchase).height, 56);
      final buttonText = tester.widget<Text>(
        find.descendant(of: purchase, matching: find.byType(Text)),
      );
      expect(buttonText.style?.fontSize, 16);
      expect(buttonText.style?.fontWeight, FontWeight.w600);
      expect(buttonText.style?.height, 24 / 16);
      expect(
        tester.getRect(find.text('Terms of Use')).top -
            tester.getRect(purchase).bottom,
        closeTo(16, 1),
      );
      expect(tester.getRect(find.text('Terms of Use')).bottom, closeTo(828, 1));
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final sheet in [false, true]) {
    for (final width in [390.0, 320.0]) {
      testWidgets(
        'configured actual, weekly and weekly-only prices fit ${sheet ? 'modal' : 'page'} at $width',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          try {
            final host = _RestoreTestHost(
              useNewFallback: true,
              displayConfiguration: SubscriptionDisplayConfig(
                pageType: sheet
                    ? SubscriptionPageType.modal
                    : SubscriptionPageType.page,
                skus: const [
                  SubscriptionDisplaySku(
                    productId: 'weekly.trial',
                    type: DisplayProductType.subscription,
                    isDefault: true,
                    copy: SubscriptionCopy(
                      name: 'Weekly Trial',
                      priceNote: 'Actual price note',
                    ),
                  ),
                  SubscriptionDisplaySku(
                    productId: 'yearly.pro',
                    type: DisplayProductType.subscription,
                    weeklyReference: true,
                    weeklyOnly: true,
                    copy: SubscriptionCopy(
                      name: 'Unlimited Yearly',
                      badge: 'SAVE 81%',
                      priceNote: 'Ignored yearly note',
                    ),
                  ),
                  SubscriptionDisplaySku(
                    productId: 'cardx.month',
                    type: DisplayProductType.subscription,
                    weeklyReference: true,
                    copy: SubscriptionCopy(
                      name: 'Unlimited Monthly',
                      badge: 'MOST POPULAR',
                      priceNote: 'Ignored monthly note',
                    ),
                  ),
                ],
              ),
            );
            await tester.pumpWidget(host.app);
            await tester.pumpAndSettle();
            host.router.push('/subscription${sheet ? '?sheet=true' : ''}');
            await tester.pumpAndSettle();

            Finder price(String id) =>
                find.byKey(Key('subscription-config-product-$id-price'));
            Finder caption(String id) => find.byKey(
              Key('subscription-config-product-$id-price-caption'),
            );
            for (final entry in [
              ('weekly.trial', r'US$4.99', 'Actual price note'),
              ('yearly.pro', r'US$0.96', 'per week'),
              ('cardx.month', r'US$12.99', r'US$3.00 per week'),
            ]) {
              final id = entry.$1;
              final card = find.byKey(Key('subscription-config-product-$id'));
              await tester.scrollUntilVisible(
                card,
                150,
                scrollable: find.descendant(
                  of: find.byType(CustomScrollView).last,
                  matching: find.byType(Scrollable),
                ),
              );
              expect(
                find.descendant(of: price(id), matching: find.text(entry.$2)),
                findsOneWidget,
              );
              expect(
                find.descendant(of: caption(id), matching: find.text(entry.$3)),
                findsOneWidget,
              );
              final priceRect = tester.getRect(price(id));
              final captionRect = tester.getRect(caption(id));
              final cardRect = tester.getRect(card);
              expect(captionRect.top, greaterThanOrEqualTo(priceRect.bottom));
              expect(captionRect.left, greaterThanOrEqualTo(priceRect.left));
              expect(captionRect.right, lessThanOrEqualTo(cardRect.right - 8));
              if (id != 'weekly.trial') {
                final badge = find.byKey(
                  Key('subscription-plan-$id-badge-surface'),
                );
                expect(tester.getRect(badge).bottom, lessThan(priceRect.top));
              }
            }
            expect(find.text('Ignored yearly note'), findsNothing);
            expect(find.text('Ignored monthly note'), findsNothing);
            expect(find.textContaining('Approx.'), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }

  testWidgets('weekly-only linked trial keeps Then on its weekly amount', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    try {
      final host = _RestoreTestHost(
        includeTrial: true,
        displayConfiguration: SubscriptionDisplayConfig(
          pageType: SubscriptionPageType.page,
          trialEnabled: true,
          trialToggleText: 'Enable Free Trial',
          skus: const [
            SubscriptionDisplaySku(
              productId: 'weekly.product',
              type: DisplayProductType.subscription,
              isDefault: true,
              weeklyReference: true,
              weeklyOnly: true,
              copy: SubscriptionCopy(name: 'Weekly'),
              trial: SubscriptionTrial(
                productId: 'weekly.trial',
                copy: SubscriptionCopy(name: 'Weekly Trial'),
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      host.router.push('/subscription');
      await tester.pumpAndSettle();
      final price = find.byKey(
        const Key('subscription-config-product-weekly.product-price'),
      );
      final caption = find.byKey(
        const Key('subscription-config-product-weekly.product-price-caption'),
      );
      expect(
        find.descendant(of: price, matching: find.text('USD 2.77')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('subscription-trial-switch')));
      await tester.pumpAndSettle();
      expect(host.display!.selectedCard!.product.id, 'weekly.trial');
      expect(
        find.descendant(of: price, matching: find.text('Then USD 2.77')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: caption, matching: find.text('per week')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final sheet in [false, true]) {
    testWidgets(
      'hidden linked trial removes only card prices ${sheet ? 'modal' : 'page'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        try {
          final host = _RestoreTestHost(
            includeTrial: true,
            displayConfiguration: SubscriptionDisplayConfig(
              pageType: sheet
                  ? SubscriptionPageType.modal
                  : SubscriptionPageType.page,
              trialEnabled: true,
              trialToggleText: 'Enable Free Trial',
              skus: const [
                SubscriptionDisplaySku(
                  productId: 'weekly.product',
                  type: DisplayProductType.subscription,
                  isDefault: true,
                  weeklyReference: true,
                  copy: SubscriptionCopy(
                    name: 'Base',
                    priceNote: 'Base price note',
                  ),
                  trial: SubscriptionTrial(
                    productId: 'weekly.trial',
                    weeklyReference: false,
                    hidePrice: true,
                    copy: SubscriptionCopy(
                      name: 'Trial',
                      badge: 'Free trial',
                      priceNote: 'Trial price note',
                      cta: 'TRY FREE',
                    ),
                  ),
                ),
              ],
            ),
          );
          await tester.pumpWidget(host.app);
          await tester.pumpAndSettle();
          host.router.push('/subscription${sheet ? '?sheet=true' : ''}');
          await tester.pumpAndSettle();

          final card = find.byKey(
            const Key('subscription-config-product-weekly.product'),
          );
          const price = Key('subscription-config-product-weekly.product-price');
          const caption = Key(
            'subscription-config-product-weekly.product-price-caption',
          );
          expect(find.byKey(price), findsOneWidget);
          expect(find.byKey(caption), findsOneWidget);
          expect(
            find.descendant(of: card, matching: find.text('USD 2.77 per week')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const Key('subscription-trial-switch')));
          await tester.pumpAndSettle();
          expect(host.display!.selectedCard!.product.id, 'weekly.trial');
          expect(find.byKey(price), findsNothing);
          expect(find.byKey(caption), findsNothing);
          expect(
            find.descendant(of: card, matching: find.text('USD 2.77 per week')),
            findsNothing,
          );
          expect(find.text('Trial price note'), findsNothing);
          expect(find.text('TRY FREE'), findsOneWidget);
          expect(
            find.byKey(const Key('subscription-billing-summary')),
            findsOneWidget,
          );
          expect(
            tester.getRect(find.text('Trial')).top,
            greaterThanOrEqualTo(
              tester
                  .getRect(
                    find.byKey(
                      const Key(
                        'subscription-plan-weekly.product-badge-surface',
                      ),
                    ),
                  )
                  .bottom,
            ),
          );
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'linked trial can restore card prices ${sheet ? 'modal' : 'page'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        try {
          final host = _RestoreTestHost(
            includeTrial: true,
            displayConfiguration: SubscriptionDisplayConfig(
              pageType: sheet
                  ? SubscriptionPageType.modal
                  : SubscriptionPageType.page,
              trialEnabled: true,
              trialToggleText: 'Enable Free Trial',
              skus: const [
                SubscriptionDisplaySku(
                  productId: 'weekly.product',
                  type: DisplayProductType.subscription,
                  isDefault: true,
                  weeklyReference: true,
                  hidePrice: true,
                  copy: SubscriptionCopy(
                    name: 'Base',
                    priceNote: 'Base price note',
                  ),
                  trial: SubscriptionTrial(
                    productId: 'weekly.trial',
                    weeklyReference: true,
                    hidePrice: false,
                    copy: SubscriptionCopy(
                      name: 'Trial',
                      priceNote: 'Trial price note',
                    ),
                  ),
                ),
              ],
            ),
          );
          await tester.pumpWidget(host.app);
          await tester.pumpAndSettle();
          host.router.push('/subscription${sheet ? '?sheet=true' : ''}');
          await tester.pumpAndSettle();

          final card = find.byKey(
            const Key('subscription-config-product-weekly.product'),
          );
          const price = Key('subscription-config-product-weekly.product-price');
          const caption = Key(
            'subscription-config-product-weekly.product-price-caption',
          );
          expect(find.byKey(price), findsNothing);
          expect(find.byKey(caption), findsNothing);
          await tester.tap(find.byKey(const Key('subscription-trial-switch')));
          await tester.pumpAndSettle();

          expect(host.display!.selectedCard!.product.id, 'weekly.trial');
          expect(find.byKey(price), findsOneWidget);
          expect(find.byKey(caption), findsOneWidget);
          expect(
            find.descendant(of: card, matching: find.text('USD 3.99')),
            findsOneWidget,
          );
          expect(find.text('Trial price note'), findsNothing);
          expect(
            find.descendant(of: card, matching: find.text('USD 2.77 per week')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets('fallback paywall keeps StoreKit period captions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    try {
      final host = _RestoreTestHost(remoteDisplayConfiguration: false);
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      host.router.push('/subscription');
      await tester.pumpAndSettle();

      final weekly = find.byKey(
        const Key('subscription-config-product-weekly.product'),
      );
      expect(
        find.descendant(of: weekly, matching: find.text('per week')),
        findsOneWidget,
      );
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Scrollable),
          )
          .last;
      final lifetime = find.byKey(
        const Key('subscription-config-product-lifetime.product'),
      );
      await tester.scrollUntilVisible(lifetime, 200, scrollable: scrollable);
      expect(
        find.descendant(of: lifetime, matching: find.text('one-time purchase')),
        findsOneWidget,
      );
      expect(host.display!.usesRemoteConfiguration, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'local subscription fallback shows StoreKit prices and verified trial copy',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      try {
        final trialEligibility = Completer<TrialEligibility>();
        final host = _RestoreTestHost(
          useNewFallback: true,
          trialEligibility: trialEligibility.future,
        );
        await tester.pumpWidget(host.app);
        await tester.pumpAndSettle();
        host.router.push('/subscription');
        await tester.pumpAndSettle();

        expect(host.display!.selectedId, 'weekly.trial');
        expect(find.text('Premium'), findsNothing);
        expect(find.text('3-Day Free'), findsOneWidget);
        expect(find.text('Unlimited Yearly'), findsOneWidget);
        expect(find.text('Unlimited Monthly'), findsOneWidget);
        expect(find.text('save 81%'), findsOneWidget);
        expect(find.text('Most Popular'), findsOneWidget);
        expect(find.text('Try For Free'), findsOneWidget);
        expect(find.text('CANCEL ANYTIME'), findsNothing);
        expect(find.text('NO PAYMENT NOW'), findsOneWidget);
        final auxiliary = tester.widget<Text>(find.text('NO PAYMENT NOW'));
        expect(auxiliary.style?.fontSize, 14);
        expect(auxiliary.style?.color, Colors.white);
        expect(
          tester.getRect(find.text('NO PAYMENT NOW')).top -
              tester.getRect(find.text('Terms of Use')).bottom,
          closeTo(4, 1),
        );
        expect(
          find.byKey(const Key('subscription-billing-summary')),
          findsNothing,
        );

        final cards = [
          for (final id in ['weekly.trial', 'yearly.pro', 'cardx.month'])
            find.byKey(Key('subscription-config-product-$id')),
        ];
        expect(
          tester.getRect(cards[0]).top,
          lessThan(tester.getRect(cards[1]).top),
        );
        expect(
          tester.getRect(cards[1]).top,
          lessThan(tester.getRect(cards[2]).top),
        );
        for (final id in ['weekly.trial', 'yearly.pro', 'cardx.month']) {
          final card = find.byKey(Key('subscription-config-product-$id'));
          expect(
            find.descendant(of: card, matching: find.text('per week')),
            findsOneWidget,
          );
        }
        expect(find.text(r'Only US$49.99 per year'), findsOneWidget);
        expect(find.text(r'Only US$12.99 per month'), findsOneWidget);
        Finder price(String id) => find.descendant(
          of: find.byKey(Key('subscription-config-product-$id-price')),
          matching: find.byType(Text),
        );
        expect(
          tester.widget<Text>(price('weekly.trial')).data,
          r'Then US$4.99',
        );
        expect(tester.widget<Text>(price('yearly.pro')).data, r'US$0.96');
        expect(tester.widget<Text>(price('cardx.month')).data, r'US$3.25');

        trialEligibility.complete(TrialEligibility.ineligible);
        await tester.pumpAndSettle();
        expect(find.text('Premium'), findsNothing);
        expect(find.text('3-Day Free'), findsOneWidget);
        expect(find.text('Try For Free'), findsOneWidget);
        expect(find.text('NO PAYMENT NOW'), findsOneWidget);
        expect(find.text('CANCEL ANYTIME'), findsNothing);
        expect(
          tester.widget<Text>(price('weekly.trial')).data,
          r'Then US$4.99',
        );

        await tester.tap(
          find.byKey(const Key('subscription-config-product-yearly.pro')),
        );
        await tester.pumpAndSettle();
        expect(find.text('SUBSCRIBE'), findsOneWidget);
        expect(find.text('CANCEL ANYTIME'), findsOneWidget);
        expect(find.text('NO PAYMENT NOW'), findsNothing);
        expect(tester.widget<Text>(price('yearly.pro')).data, r'US$0.96');
        await tester.tap(
          find.byKey(const Key('subscription-config-product-cardx.month')),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(price('cardx.month')).data, r'US$3.25');
        expect(find.text('SUBSCRIBE'), findsOneWidget);
        expect(find.text('CANCEL ANYTIME'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final sheet in [false, true]) {
    testWidgets(
      'offline ${sheet ? 'modal' : 'page'} can select and submit a plan',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        try {
          var connected = false;
          final productRequests = <Set<String>>[];
          final purchaseController = _RecordingDisplayPurchaseController();
          final host = _RestoreTestHost(
            controller: purchaseController,
            useNewFallback: true,
            displayRetryDelays: const [],
            productLoader: (ids) async {
              productRequests.add(ids);
              if (!connected) return const [];
              return [
                if (ids.contains('weekly.trial'))
                  displayProduct(
                    'weekly.trial',
                    trial: true,
                    unit: 'day',
                    value: 7,
                    amount: 5.99,
                    displayPrice: r'US$5.99',
                    omitWeeklyPrice: true,
                  ),
                if (ids.contains('yearly.pro'))
                  displayProduct(
                    'yearly.pro',
                    unit: 'year',
                    amount: 59.99,
                    displayPrice: r'US$59.99',
                    weeklyPrice: r'US$1.15',
                  ),
                if (ids.contains('cardx.month'))
                  displayProduct(
                    'cardx.month',
                    unit: 'month',
                    amount: 13.99,
                    displayPrice: r'US$13.99',
                    weeklyPrice: r'US$3.23',
                    fourWeekPrice: r'US$3.50',
                  ),
              ];
            },
          );
          await tester.pumpWidget(host.app);
          await tester.pumpAndSettle();
          host.router.push('/subscription${sheet ? '?sheet=true' : ''}');
          await tester.pumpAndSettle();

          expect(host.display!.showOfflineFallback, isTrue);
          expect(host.display!.canPurchase, isFalse);
          expect(host.display!.canAttemptFallbackPurchase, isTrue);
          expect(host.display!.selectedId, 'weekly.trial');
          expect(host.display!.products, isEmpty);
          for (final entry in [
            ('weekly.trial', r'US$4.99'),
            ('yearly.pro', r'US$0.96'),
            ('cardx.month', r'US$3.25'),
          ]) {
            final card = find.byKey(
              Key('subscription-offline-product-${entry.$1}'),
            );
            expect(card, findsOneWidget);
            expect(
              find.descendant(of: card, matching: find.text(entry.$2)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: card, matching: find.text('per week')),
              findsOneWidget,
            );
          }
          expect(find.text(r'Only US$49.99 per year'), findsOneWidget);
          expect(find.text(r'Only US$12.99 per month'), findsOneWidget);
          expect(find.text('save 81%'), findsOneWidget);
          expect(find.text('Most Popular'), findsOneWidget);
          expect(
            find.byKey(const Key('subscription-offline-price-notice')),
            findsNothing,
          );
          expect(find.text(r'Then US$4.99'), findsNothing);
          expect(find.text('TRY FOR FREE'), findsNothing);
          expect(find.text('Try For Free'), findsOneWidget);
          expect(find.text('NO PAYMENT NOW'), findsOneWidget);
          expect(find.text('CANCEL ANYTIME'), findsNothing);
          expect(
            tester.getRect(find.text('NO PAYMENT NOW')).top -
                tester.getRect(find.text('Terms of Use')).bottom,
            closeTo(4, 1),
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('subscription-purchase-button')),
                )
                .onPressed,
            isNotNull,
          );
          expect(find.text('SUBSCRIBE'), findsNothing);
          expect(find.byType(KandoTopToast), findsNothing);

          final monthly = find.byKey(
            const Key('subscription-offline-product-cardx.month'),
          );
          await tester.ensureVisible(monthly);
          await tester.tap(monthly);
          await tester.pumpAndSettle();
          expect(host.display!.selectedId, 'cardx.month');
          expect(find.text('SUBSCRIBE'), findsOneWidget);
          expect(find.text('Try For Free'), findsNothing);
          expect(find.text('CANCEL ANYTIME'), findsOneWidget);
          expect(find.text('NO PAYMENT NOW'), findsNothing);

          final yearly = find.byKey(
            const Key('subscription-offline-product-yearly.pro'),
          );
          await tester.ensureVisible(yearly);
          await tester.tap(yearly);
          await tester.pumpAndSettle();
          expect(host.display!.selectedId, 'yearly.pro');
          expect(find.text('SUBSCRIBE'), findsOneWidget);
          expect(find.text('Try For Free'), findsNothing);
          expect(find.text('CANCEL ANYTIME'), findsOneWidget);
          expect(find.text('NO PAYMENT NOW'), findsNothing);
          final yearlyTile = tester.widget<Container>(
            find.descendant(of: yearly, matching: find.byType(Container)).first,
          );
          expect(
            (yearlyTile.decoration as BoxDecoration).border!.top.color,
            KandoColors.accent,
          );

          final purchase = find.byKey(
            const Key('subscription-purchase-button'),
          );
          await tester.tap(purchase);
          await tester.pumpAndSettle();
          expect(productRequests.last, {'yearly.pro'});
          expect(purchaseController.submittedIds, isEmpty);
          expect(host.display!.showOfflineFallback, isTrue);
          expect(find.byType(KandoTopToast), findsOneWidget);

          connected = true;
          await tester.tap(purchase);
          await tester.pumpAndSettle();
          expect(productRequests.last, {'yearly.pro'});
          expect(purchaseController.submittedIds, ['yearly.pro']);
          expect(purchaseController.confirmedIds, ['yearly.pro']);

          expect(host.display!.showOfflineFallback, isFalse);
          expect(host.display!.canPurchase, isTrue);
          expect(
            find.byKey(const Key('subscription-offline-price-notice')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('subscription-offline-product-weekly.trial')),
            findsNothing,
          );
          final realYearly = find.byKey(
            const Key('subscription-config-product-yearly.pro'),
          );
          await tester.ensureVisible(realYearly);
          expect(
            find.descendant(of: realYearly, matching: find.text(r'US$1.15')),
            findsOneWidget,
          );
          expect(find.text(r'Only US$59.99 per year'), findsOneWidget);
          await tester.pump(const Duration(seconds: 5));
          expect(find.byType(KandoTopToast), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets('configured badges clear prices and previous rows', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    try {
      final host = _RestoreTestHost(
        includeTrial: true,
        displayConfiguration: SubscriptionDisplayConfig(
          pageType: SubscriptionPageType.page,
          trialEnabled: true,
          trialToggleText: 'Enable Free Trial',
          skus: const [
            SubscriptionDisplaySku(
              productId: 'weekly.product',
              type: DisplayProductType.subscription,
              isDefault: true,
              copy: SubscriptionCopy(
                name: 'Weekly',
                subtitle:
                    'Weekly detail wraps across multiple lines in this card',
                badge: 'new Weekly',
              ),
              trial: SubscriptionTrial(
                productId: 'weekly.trial',
                copy: SubscriptionCopy(
                  name: 'Weekly trial',
                  badge: 'new Free trial',
                  priceNote: 'new then per week',
                ),
              ),
            ),
            SubscriptionDisplaySku(
              productId: 'yearly.product',
              type: DisplayProductType.subscription,
              copy: SubscriptionCopy(
                name: 'Yearly',
                badge: 'new Best value',
                priceNote: 'per year',
              ),
            ),
            SubscriptionDisplaySku(
              productId: 'lifetime.product',
              type: DisplayProductType.nonConsumable,
              copy: SubscriptionCopy(
                name: 'Lifetime',
                subtitle: '   ',
                badge: 'new One-time',
                priceNote: 'new one-time purchase',
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      host.router.push('/subscription');
      await tester.pumpAndSettle();

      final trialSwitch = find.byKey(const Key('subscription-trial-switch'));
      final cards = [
        for (final id in [
          'weekly.product',
          'yearly.product',
          'lifetime.product',
        ])
          find.byKey(Key('subscription-config-product-$id')),
      ];
      final badges = [
        for (final id in [
          'weekly.product',
          'yearly.product',
          'lifetime.product',
        ])
          find.byKey(Key('subscription-plan-$id-badge-surface')),
      ];
      final prices = [
        for (final id in [
          'weekly.product',
          'yearly.product',
          'lifetime.product',
        ])
          find.byKey(Key('subscription-config-product-$id-price')),
      ];

      expect(
        find.byKey(
          const Key('subscription-config-product-weekly.product-price-caption'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: cards.first, matching: find.text('per week')),
        findsNothing,
      );
      expect(
        find.descendant(of: cards[1], matching: find.text('per year')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cards[2],
          matching: find.text('new one-time purchase'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.text('Yearly')).center.dy,
        closeTo(tester.getRect(cards[1]).center.dy, 1),
      );
      expect(
        tester.getRect(find.text('Lifetime')).center.dy,
        closeTo(tester.getRect(cards[2]).center.dy, 1),
      );
      expect(find.text('   '), findsNothing);
      for (final id in [
        'weekly.product',
        'yearly.product',
        'lifetime.product',
      ]) {
        expect(
          tester
              .getRect(find.byKey(Key('subscription-config-product-$id-radio')))
              .center
              .dy,
          closeTo(
            tester
                .getRect(find.byKey(Key('subscription-config-product-$id')))
                .center
                .dy,
            1,
          ),
        );
      }
      expect(
        find.descendant(of: cards[2], matching: find.text('one-time purchase')),
        findsNothing,
      );
      expect(
        tester.getRect(badges.first).top - tester.getRect(trialSwitch).bottom,
        9,
      );
      for (var index = 0; index < cards.length; index++) {
        expect(
          tester.getRect(badges[index]).bottom,
          lessThanOrEqualTo(tester.getRect(prices[index]).top),
        );
        if (index > 0) {
          expect(
            tester.getRect(cards[index]).top -
                tester.getRect(cards[index - 1]).bottom,
            20,
          );
          expect(
            tester.getRect(badges[index]).top,
            greaterThan(tester.getRect(cards[index - 1]).bottom),
          );
        }
      }
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'configured badge selection changes without an intermediate tint',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      try {
        final host = _RestoreTestHost(
          disableAnimations: false,
          displayConfiguration: SubscriptionDisplayConfig(
            pageType: SubscriptionPageType.page,
            skus: const [
              SubscriptionDisplaySku(
                productId: 'weekly.product',
                type: DisplayProductType.subscription,
                isDefault: true,
                copy: SubscriptionCopy(name: 'Weekly', badge: 'Weekly'),
              ),
              SubscriptionDisplaySku(
                productId: 'yearly.product',
                type: DisplayProductType.subscription,
                copy: SubscriptionCopy(name: 'Yearly', badge: 'Yearly'),
              ),
            ],
          ),
        );
        await tester.pumpWidget(host.app);
        await tester.pumpAndSettle();
        host.router.push('/subscription');
        await tester.pumpAndSettle();

        final weeklyBadge = find.byKey(
          const Key('subscription-plan-weekly.product-badge-surface'),
        );
        final yearlyBadge = find.byKey(
          const Key('subscription-plan-yearly.product-badge-surface'),
        );
        (Color, Color) badgeColors(Finder finder) {
          final decoration =
              tester.widget<Container>(finder).decoration! as BoxDecoration;
          return (decoration.color!, (decoration.border! as Border).top.color);
        }

        expect(badgeColors(weeklyBadge), (
          const Color(0x33F1FE70),
          const Color(0x4DF1FE70),
        ));
        expect(badgeColors(yearlyBadge), (
          const Color(0xFF34362D),
          const Color(0x4D474836),
        ));
        await tester.tap(
          find.byKey(const Key('subscription-config-product-yearly.product')),
        );
        await tester.pump();
        expect(badgeColors(weeklyBadge), (
          const Color(0xFF34362D),
          const Color(0x4D474836),
        ));
        expect(badgeColors(yearlyBadge), (
          const Color(0x33F1FE70),
          const Color(0x4DF1FE70),
        ));
        await tester.pump(const Duration(milliseconds: 70));
        expect(badgeColors(weeklyBadge), (
          const Color(0xFF34362D),
          const Color(0x4D474836),
        ));
        expect(badgeColors(yearlyBadge), (
          const Color(0x33F1FE70),
          const Color(0x4DF1FE70),
        ));
        expect(tester.takeException(), isNull);
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('trial list stays active when another plan is selected', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    try {
      final host = _RestoreTestHost(
        includeTrial: true,
        displayConfiguration: SubscriptionDisplayConfig(
          pageType: SubscriptionPageType.page,
          trialEnabled: true,
          trialToggleText: 'Enable Free Trial',
          skus: [
            SubscriptionDisplaySku(
              productId: 'weekly.product',
              type: DisplayProductType.subscription,
              copy: SubscriptionCopy(name: 'Base'),
              trial: SubscriptionTrial(
                productId: 'weekly.trial',
                copy: SubscriptionCopy(name: 'Trial', cta: 'Try for Free'),
              ),
            ),
            SubscriptionDisplaySku(
              productId: 'yearly.product',
              type: DisplayProductType.subscription,
              isDefault: true,
              copy: SubscriptionCopy(name: 'Yearly'),
            ),
          ],
        ),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      host.router.push('/subscription');
      await tester.pumpAndSettle();

      final trialSwitch = find.byKey(const Key('subscription-trial-switch'));
      final weekly = find.byKey(
        const Key('subscription-config-product-weekly.product'),
      );
      final yearly = find.byKey(
        const Key('subscription-config-product-yearly.product'),
      );
      expect(
        tester.getRect(trialSwitch).bottom,
        lessThan(tester.getRect(weekly).top),
      );
      await tester.tap(trialSwitch);
      await tester.pumpAndSettle();
      expect(host.display!.trialOn, isTrue);
      expect(host.display!.selectedCard!.product.id, 'weekly.trial');
      expect(find.text('Trial'), findsOneWidget);
      expect(find.text('Base'), findsNothing);
      expect(find.text('Try for Free'), findsOneWidget);
      expect(tester.getSize(weekly).height, 74);

      await tester.tap(yearly);
      await tester.pumpAndSettle();
      expect(host.display!.trialOn, isTrue);
      expect(host.display!.selectedId, 'yearly.product');
      expect(find.text('Trial'), findsOneWidget);
      expect(find.text('Base'), findsNothing);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'three plans with trial keep purchase visible above the safe area',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      try {
        final host = _RestoreTestHost(
          includeTrial: true,
          displayConfiguration: SubscriptionDisplayConfig(
            pageType: SubscriptionPageType.page,
            trialEnabled: true,
            trialToggleText: 'Enable Free Trial',
            skus: [
              SubscriptionDisplaySku(
                productId: 'weekly.product',
                type: DisplayProductType.subscription,
                copy: SubscriptionCopy(name: 'Weekly'),
                trial: SubscriptionTrial(
                  productId: 'weekly.trial',
                  copy: SubscriptionCopy(name: 'Weekly', cta: 'Try for Free'),
                ),
              ),
              SubscriptionDisplaySku(
                productId: 'yearly.product',
                type: DisplayProductType.subscription,
                isDefault: true,
                copy: SubscriptionCopy(name: 'Yearly'),
              ),
              SubscriptionDisplaySku(
                productId: 'lifetime.product',
                type: DisplayProductType.nonConsumable,
                copy: SubscriptionCopy(
                  name: 'Lifetime',
                  priceNote: 'new one-time purchase',
                ),
              ),
            ],
          ),
        );
        await tester.pumpWidget(host.app);
        await tester.pumpAndSettle();
        host.router.push('/subscription');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('subscription-trial-switch')),
          findsOneWidget,
        );
        expect(host.display!.availableSkus, hasLength(3));
        final purchase = find.byKey(const Key('subscription-purchase-button'));
        final initialPurchaseRect = tester.getRect(purchase);
        expect(initialPurchaseRect.top, greaterThanOrEqualTo(47));
        expect(initialPurchaseRect.bottom, lessThanOrEqualTo(810));
        expect(
          tester.getRect(find.text('Terms of Use')).bottom,
          closeTo(828, 1),
        );
        expect(tester.widget<FilledButton>(purchase).onPressed, isNotNull);

        await tester.drag(
          find.byType(CustomScrollView).last,
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();

        final lifetime = find.byKey(
          const Key('subscription-config-product-lifetime.product'),
        );
        expect(lifetime, findsOneWidget);
        expect(
          find.descendant(
            of: lifetime,
            matching: find.text('new one-time purchase'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: lifetime,
            matching: find.text('one-time purchase'),
          ),
          findsNothing,
        );
        expect(tester.getRect(lifetime).top, greaterThanOrEqualTo(47));
        expect(
          tester.getRect(lifetime).bottom,
          lessThanOrEqualTo(tester.getRect(purchase).top),
        );
        expect(tester.getRect(purchase), initialPurchaseRect);
        await tester.tap(lifetime);
        await tester.pumpAndSettle();
        expect(host.display!.selectedId, 'lifetime.product');
        expect(tester.takeException(), isNull);
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'configured copy wraps and close delay also blocks sheet dragging',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        final config = SubscriptionDisplayConfig(
          pageType: SubscriptionPageType.modal,
          closeDelay: const Duration(seconds: 45),
          skus: [
            SubscriptionDisplaySku(
              productId: 'yearly.product',
              type: DisplayProductType.subscription,
              isDefault: true,
              copy: SubscriptionCopy(
                name: '订阅' * 50,
                subtitle: 'Details ' * 35,
                cta: '订阅' * 50,
                billingNote: 'Disclosure ' * 40,
                autoBillingNote: false,
              ),
            ),
          ],
        );
        final host = _RestoreTestHost(displayConfiguration: config);
        await tester.pumpWidget(host.app);
        await tester.pumpAndSettle();
        host.router.push('/subscription?sheet=true');
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close'), findsNothing);
        await tester.drag(
          find.byKey(const Key('subscription-sheet-handle')),
          const Offset(0, 150),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SubscriptionPage), findsOneWidget);
        final purchase = find.byKey(const Key('subscription-purchase-button'));
        await tester.scrollUntilVisible(
          purchase,
          250,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView).last,
                matching: find.byType(Scrollable),
              )
              .last,
        );
        expect(tester.getSize(purchase).height, greaterThan(56));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('three-plan sheet keeps purchase clear of the safe area', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    try {
      final host = _RestoreTestHost(
        includeTrial: true,
        displayConfiguration: SubscriptionDisplayConfig(
          pageType: SubscriptionPageType.modal,
          trialEnabled: true,
          trialToggleText: 'Enable Free Trial',
          skus: [
            SubscriptionDisplaySku(
              productId: 'weekly.product',
              type: DisplayProductType.subscription,
              copy: SubscriptionCopy(name: 'Weekly'),
              trial: SubscriptionTrial(
                productId: 'weekly.trial',
                copy: SubscriptionCopy(name: 'Weekly'),
              ),
            ),
            SubscriptionDisplaySku(
              productId: 'yearly.product',
              type: DisplayProductType.subscription,
              isDefault: true,
              copy: SubscriptionCopy(name: 'Yearly'),
            ),
            SubscriptionDisplaySku(
              productId: 'lifetime.product',
              type: DisplayProductType.nonConsumable,
              copy: SubscriptionCopy(name: 'Lifetime'),
            ),
          ],
        ),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      host.router.push('/subscription?sheet=true');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('subscription-trial-switch')),
        findsOneWidget,
      );
      final purchase = find.byKey(const Key('subscription-purchase-button'));
      final initialPurchaseRect = tester.getRect(purchase);
      expect(initialPurchaseRect.bottom, lessThanOrEqualTo(810));

      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      final lifetime = find.byKey(
        const Key('subscription-config-product-lifetime.product'),
      );
      expect(lifetime, findsOneWidget);
      expect(
        tester.getRect(lifetime).bottom,
        lessThanOrEqualTo(tester.getRect(purchase).top),
      );
      expect(tester.getRect(purchase), initialPurchaseRect);
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android full page keeps the existing SKU presentation', (
    tester,
  ) async {
    final host = _RestoreTestHost();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      host.router.push('/subscription');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      final weeklySurface = find.byKey(
        const Key('subscription-plan-weekly-surface'),
      );
      final yearlySurface = find.byKey(
        const Key('subscription-plan-yearly-surface'),
      );
      final lifetimeSurface = find.byKey(
        const Key('subscription-plan-lifetime-surface'),
      );
      for (final surface in [weeklySurface, yearlySurface, lifetimeSurface]) {
        expect(tester.widget<AnimatedContainer>(surface), isNotNull);
        expect(tester.getSize(surface).height, 76);
      }
      expect(
        tester.getRect(yearlySurface).top -
            tester.getRect(weeklySurface).bottom,
        12,
      );
      expect(
        tester.getRect(lifetimeSurface).top -
            tester.getRect(yearlySurface).bottom,
        12,
      );
      expect(
        find.byKey(const Key('subscription-plan-yearly-selected-overlay')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('subscription-plan-yearly-badge-blur')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'iOS configured sheet freezes selection and hands off the exact chosen product during purchase',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final controller = _InFlightPurchaseController();
        final host = _RestoreTestHost(controller: controller);
        await tester.pumpWidget(host.app);
        await tester.pumpAndSettle();
        host.router.push('/subscription?sheet=true');
        await tester.pumpAndSettle();
        final lifetime = find.byKey(
          const Key('subscription-config-product-lifetime.product'),
        );
        await tester.scrollUntilVisible(
          lifetime,
          180,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView).last,
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.tap(lifetime);
        await tester.pumpAndSettle();
        final purchase = find.byKey(const Key('subscription-purchase-button'));
        await tester.scrollUntilVisible(
          purchase,
          180,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView).last,
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.tap(purchase);
        await tester.pump();
        await tester.pump();
        expect(controller.state.isPurchasing, isTrue);
        expect(controller.state.selectedPlanId, subscriptionLifetimePlanId);
        expect(host.display!.selectedCard!.product.id, 'lifetime.product');
        final weekly = find.byKey(
          const Key('subscription-config-product-weekly.product'),
        );
        await tester.scrollUntilVisible(
          weekly,
          -180,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView).last,
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(weekly);
        await tester.pump();
        expect(host.display!.selectedId, 'lifetime.product');
        controller.completePurchase();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Purchase Pending disables purchase and restore while Close remains available',
    (tester) async {
      final host = _RestoreTestHost(controller: _PendingPurchaseController());
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text('Restore'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );

      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      final purchase = tester.widget<FilledButton>(
        find.byKey(const Key('subscription-purchase-button')),
      );
      expect(purchase.onPressed, isNull);

      await host.controller.purchase();
      await host.controller.purchase();
      await tester.pump(const Duration(seconds: 26));
      expect(host.controller.state.isPurchasePending, isTrue);
      expect(host.controller.state.errorMessage, isNull);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Source Page'), findsOneWidget);
    },
  );

  testWidgets('subscription errors stay visible for five seconds', (
    tester,
  ) async {
    final host = _RestoreTestHost();
    await tester.pumpWidget(host.app);
    await tester.pumpAndSettle();

    host.router.push('/subscription');
    await tester.pumpAndSettle();
    host.controller.showError(subscriptionPurchaseCanceledMessage);
    await tester.pump();

    expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
    expect(find.text(subscriptionPurchaseCanceledMessage), findsOneWidget);
    expect(
      tester.widget<KandoTopToast>(find.byType(KandoTopToast)).type,
      KandoTopToastType.warning,
    );

    await tester.pump(const Duration(milliseconds: 4900));
    expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
  });

  for (final source in ['home', 'search', 'collection', 'profile', 'scan']) {
    testWidgets(
      '$source purchase keeps its source through Success and Start Exploring',
      (tester) async {
        final host = _RestoreTestHost(initialLocation: '/$source');
        await tester.pumpWidget(host.app);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(Key('$source-state')), 'kept');

        host.router.push(
          subscriptionPageLocation(
            source: source,
            entrySource: source == 'scan'
                ? 'scan_pro_card'
                : 'top_subscription_entry',
          ),
        );
        await tester.pumpAndSettle();
        host.controller.emit(
          SubscriptionResultEvent.purchaseSuccess,
          isPro: true,
        );
        await tester.pumpAndSettle();

        expect(find.text("You're Premium!"), findsOneWidget);
        final startExploring = find.byKey(
          const Key('subscription-success-continue'),
        );
        await tester.ensureVisible(startExploring);
        await tester.pump();
        await tester.tap(startExploring);
        await tester.pumpAndSettle();

        expect(find.text('${_capitalized(source)} Page'), findsOneWidget);
        expect(find.text('kept'), findsOneWidget);
        expect(find.text('Choose Your Plan'), findsNothing);
        expect(find.text("You're Premium!"), findsNothing);
        expect(host.router.canPop(), isFalse);
      },
    );
  }

  testWidgets('cold-start purchase Success continues to Home', (tester) async {
    final host = _RestoreTestHost();
    await tester.pumpWidget(host.app);
    await tester.pumpAndSettle();

    host.router.push('/subscription?source=cold_start');
    await tester.pumpAndSettle();
    host.controller.emit(SubscriptionResultEvent.purchaseSuccess, isPro: true);
    await tester.pumpAndSettle();

    final startExploring = find.byKey(
      const Key('subscription-success-continue'),
    );
    await tester.ensureVisible(startExploring);
    await tester.tap(startExploring);
    await tester.pumpAndSettle();

    expect(find.text('Home Page'), findsOneWidget);
    expect(find.text('Choose Your Plan'), findsNothing);
    expect(find.text("You're Premium!"), findsNothing);
    expect(host.router.canPop(), isFalse);
  });

  testWidgets(
    'Repeated premium events do not dismiss the purchase Success page',
    (tester) async {
      final host = _RestoreTestHost(initialLocation: '/profile');
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription?source=profile');
      await tester.pumpAndSettle();
      host.controller.emit(
        SubscriptionResultEvent.purchaseSuccess,
        isPro: true,
      );
      await tester.pumpAndSettle();
      expect(find.text("You're Premium!"), findsOneWidget);

      host.controller.emit(
        SubscriptionResultEvent.externalPremium,
        isPro: true,
      );
      await tester.pumpAndSettle();
      host.controller.emit(
        SubscriptionResultEvent.externalPremium,
        isPro: true,
      );
      await tester.pumpAndSettle();

      expect(find.text("You're Premium!"), findsOneWidget);
      expect(find.text('Choose Your Plan'), findsNothing);
      expect(find.text('Profile Page'), findsNothing);

      final startExploring = find.byKey(
        const Key('subscription-success-continue'),
      );
      await tester.ensureVisible(startExploring);
      await tester.tap(startExploring);
      await tester.pumpAndSettle();

      expect(find.text('Profile Page'), findsOneWidget);
      expect(find.text("You're Premium!"), findsNothing);
      expect(find.text('Choose Your Plan'), findsNothing);
    },
  );
}

void _sendAppToBackground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _returnAppToForeground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

const _testSubscriptionConfiguration = AppSubscriptionConfiguration(
  store: SubscriptionStore.appStore,
  productIds: {
    subscriptionWeeklyPlanId: 'weekly.product',
    subscriptionYearlyPlanId: 'yearly.product',
    subscriptionLifetimePlanId: 'lifetime.product',
  },
);

String _capitalized(String value) =>
    '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

class _RestoreTestHost {
  _RestoreTestHost({
    _RestoreTestController? controller,
    ProfileActions? actions,
    AppAnalytics? analytics,
    String initialLocation = '/source',
    SubscriptionDisplayConfig? displayConfiguration,
    bool includeTrial = false,
    bool useNewFallback = false,
    Future<TrialEligibility>? trialEligibility,
    bool? remoteDisplayConfiguration,
    bool disableAnimations = true,
    DisplayProductLoader? productLoader,
    List<Duration>? displayRetryDelays,
  }) : controller = controller ?? _RestoreTestController() {
    final usesRemoteDisplayConfiguration =
        remoteDisplayConfiguration ?? displayConfiguration != null;
    router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/source',
          builder: (_, _) => const Scaffold(
            body: Column(
              children: [
                Text('Source Page'),
                TextField(key: Key('source-state')),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/subscription',
          pageBuilder: (_, state) {
            final sheet = state.uri.queryParameters['sheet'] == 'true';
            final page = SubscriptionPage(
              sheet: sheet,
              source: state.uri.queryParameters['source'],
              entrySource: state.uri.queryParameters['entry_source'],
              analyticsScene: state.uri.queryParameters['scene'],
            );
            if (sheet) {
              return KandoBottomSheetPage<SubscriptionPaywallResult>(
                key: state.pageKey,
                barrierColor: const Color(0x99000000),
                isDismissible: false,
                enableDrag: defaultTargetPlatform != TargetPlatform.iOS,
                useSafeArea: true,
                heightFactor: subscriptionSheetHeightFactor,
                child: page,
              );
            }
            return MaterialPage<void>(key: state.pageKey, child: page);
          },
        ),
        GoRoute(
          path: '/subscription/success',
          builder: (_, state) => SubscriptionSuccessPage(
            source: state.uri.queryParameters['source'],
            entrySource: state.uri.queryParameters['entry_source'],
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const _SourceStatePage(source: 'home'),
        ),
        GoRoute(
          path: '/search',
          builder: (_, _) => const _SourceStatePage(source: 'search'),
        ),
        GoRoute(
          path: '/collection',
          builder: (_, _) => const _SourceStatePage(source: 'collection'),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => const _SourceStatePage(source: 'profile'),
        ),
        GoRoute(
          path: '/scan',
          builder: (_, _) => const _SourceStatePage(source: 'scan'),
        ),
      ],
    );
    app = ProviderScope(
      overrides: [
        subscriptionControllerProvider.overrideWith(() => this.controller),
        subscriptionDisplayFactoryProvider.overrideWithValue((type) {
          final configuration = useNewFallback
              ? AppSubscriptionConfiguration(
                  store: SubscriptionStore.appStore,
                  productIds: const {
                    subscriptionWeeklyPlanId: 'weekly.product',
                    subscriptionYearlyPlanId: 'yearly.product',
                    subscriptionLifetimePlanId: 'lifetime.product',
                  },
                  additionalProducts: SupportedSubscriptionProduct.parse(
                    '[{"plan_id":"weekly_trial","product_id":"weekly.trial","product_type":"subscription","is_trial_product":true},{"plan_id":"yearly_pro","product_id":"yearly.pro","product_type":"subscription","is_trial_product":false},{"plan_id":"monthly","product_id":"cardx.month","product_type":"subscription","is_trial_product":false}]',
                  ),
                )
              : _testSubscriptionConfiguration;
          final config =
              displayConfiguration ??
              legacySubscriptionFallback(configuration, type);
          display = SubscriptionDisplayController(
            fallback: config,
            retryDelays:
                displayRetryDelays ??
                const [
                  Duration(seconds: 1),
                  Duration(seconds: 3),
                  Duration(seconds: 8),
                ],
            loadConfig: (_) async =>
                usesRemoteDisplayConfiguration ? config : null,
            loadProducts:
                productLoader ??
                (ids) async => [
                  if (useNewFallback && ids.contains('weekly.trial'))
                    displayProduct(
                      'weekly.trial',
                      trial: true,
                      unit: 'day',
                      value: 7,
                      amount: 4.99,
                      displayPrice: r'US$4.99',
                      omitWeeklyPrice: true,
                    ),
                  if (useNewFallback && ids.contains('yearly.pro'))
                    displayProduct(
                      'yearly.pro',
                      unit: 'year',
                      amount: 49.99,
                      displayPrice: r'US$49.99',
                      weeklyPrice: r'US$0.96',
                    ),
                  if (useNewFallback && ids.contains('cardx.month'))
                    displayProduct(
                      'cardx.month',
                      unit: 'month',
                      amount: 12.99,
                      displayPrice: r'US$12.99',
                      weeklyPrice: r'US$3.00',
                      fourWeekPrice: r'US$3.25',
                    ),
                  if (includeTrial && ids.contains('weekly.trial'))
                    displayProduct(
                      'weekly.trial',
                      trial: true,
                      eligibility: TrialEligibility.eligible,
                      unit: 'week',
                      amount: 3.99,
                    ),
                  for (final entry
                      in _testSubscriptionConfiguration.productIds.entries)
                    if (ids.contains(entry.value))
                      displayProduct(
                        entry.value,
                        lifetime: entry.key == subscriptionLifetimePlanId,
                        unit: entry.key == subscriptionWeeklyPlanId
                            ? 'week'
                            : 'year',
                        amount: entry.key == subscriptionWeeklyPlanId
                            ? 3.99
                            : entry.key == subscriptionYearlyPlanId
                            ? 49.99
                            : 79.99,
                      ),
                ],
            loadEligibility: (_) async => trialEligibility != null
                ? await trialEligibility
                : useNewFallback || includeTrial
                ? TrialEligibility.eligible
                : throw StateError('These fixture products have no trial'),
          );
          return display!;
        }),
        if (actions != null) profileActionsProvider.overrideWithValue(actions),
        if (analytics != null) analyticsProvider.overrideWithValue(analytics),
      ],
      child: MaterialApp.router(
        theme: buildKandoTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
      ),
    );
  }

  final _RestoreTestController controller;
  SubscriptionDisplayController? display;
  late final GoRouter router;
  late final Widget app;
}

class _SourceStatePage extends StatelessWidget {
  const _SourceStatePage({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('${_capitalized(source)} Page'),
          TextField(key: Key('$source-state')),
        ],
      ),
    );
  }
}

class _RecordingProfileActions implements ProfileActions {
  int termsOpenCount = 0;
  int privacyOpenCount = 0;

  @override
  Future<void> openTerms() async {
    termsOpenCount += 1;
  }

  @override
  Future<void> openPrivacy() async {
    privacyOpenCount += 1;
  }

  @override
  Future<void> requestScore() async {}

  @override
  Future<void> shareWithFriends({Rect? sharePositionOrigin}) async {}
}

class _PartialCatalogController extends _RestoreTestController {
  @override
  SubscriptionState build() => const SubscriptionState(
    selectedPlanId: subscriptionWeeklyPlanId,
    isConfigured: true,
    displayPrices: {subscriptionWeeklyPlanId: r'$4.99'},
    availablePlanIds: {subscriptionWeeklyPlanId},
    unavailablePlanIds: {subscriptionYearlyPlanId, subscriptionLifetimePlanId},
  );
}

class _PendingPurchaseController extends _RestoreTestController {
  @override
  SubscriptionState build() => const SubscriptionState(
    isConfigured: true,
    displayPrices: {subscriptionYearlyPlanId: r'$49.99'},
    availablePlanIds: {subscriptionYearlyPlanId},
    isPurchasePending: true,
  );
}

class _InFlightPurchaseController extends _RestoreTestController {
  final _purchaseCompleter = Completer<void>();

  @override
  Future<void> purchase() async {
    state = state.copyWith(isPurchasing: true);
    await _purchaseCompleter.future;
  }

  void completePurchase() {
    if (!_purchaseCompleter.isCompleted) {
      _purchaseCompleter.complete();
    }
  }
}

class _AnalyticsPurchaseController extends _RestoreTestController {
  @override
  Future<void> purchase() async {}
}

class _UnavailableCatalogController extends _RestoreTestController {
  @override
  SubscriptionState build() => const SubscriptionState(
    selectedPlanId: subscriptionYearlyPlanId,
    isConfigured: true,
    unavailablePlanIds: {
      subscriptionWeeklyPlanId,
      subscriptionYearlyPlanId,
      subscriptionLifetimePlanId,
    },
  );
}

class _ProductRefreshController extends _RestoreTestController {
  _ProductRefreshController({this.hasLoadedProducts = true});

  final bool hasLoadedProducts;
  var productRefreshCount = 0;
  final productRefreshLoadingModes = <bool>[];

  @override
  SubscriptionState build() => hasLoadedProducts
      ? super.build()
      : const SubscriptionState(
          isConfigured: true,
          unavailablePlanIds: {
            subscriptionWeeklyPlanId,
            subscriptionYearlyPlanId,
            subscriptionLifetimePlanId,
          },
        );

  @override
  Future<void> refreshProducts({
    required bool Function() isContextActive,
    bool force = false,
    bool showLoading = true,
  }) async {
    if (!isContextActive()) return;
    if (!force && state.hasLoadedProductsFor(_testSubscriptionConfiguration)) {
      return;
    }
    productRefreshCount += 1;
    productRefreshLoadingModes.add(showLoading);
  }
}

class _RestoreTestController extends SubscriptionController {
  @override
  Future<void> purchaseDisplayProduct(
    SubscriptionProduct selected, {
    required String scene,
    required Future<SubscriptionProduct?> Function() confirm,
  }) async {
    final product = await confirm();
    if (product == null) return;
    final planId = _testSubscriptionConfiguration.productIds.entries
        .firstWhere((entry) => entry.value == product.storeProductId)
        .key;
    state = state.copyWith(selectedPlanId: planId);
    await purchase();
  }

  @override
  SubscriptionState build() => const SubscriptionState(
    isConfigured: true,
    displayPrices: {
      subscriptionWeeklyPlanId: r'$4.99',
      subscriptionYearlyPlanId: r'$49.99',
      subscriptionLifetimePlanId: r'$79.99',
    },
    analyticsProducts: {
      subscriptionWeeklyPlanId: SubscriptionProductAnalytics(
        sku: 'weekly.product',
        currency: 'USD',
        price: 4.99,
      ),
      subscriptionYearlyPlanId: SubscriptionProductAnalytics(
        sku: 'yearly.product',
        currency: 'USD',
        price: 49.99,
      ),
      subscriptionLifetimePlanId: SubscriptionProductAnalytics(
        sku: 'lifetime.product',
        currency: 'USD',
        price: 79.99,
      ),
    },
    availablePlanIds: {
      subscriptionWeeklyPlanId,
      subscriptionYearlyPlanId,
      subscriptionLifetimePlanId,
    },
  );

  void emit(SubscriptionResultEvent event, {bool isPro = false}) {
    state = state.copyWith(
      isPro: isPro,
      resultEvent: event,
      resultEventCount: state.resultEventCount + 1,
      restoreSource: SubscriptionRestoreSource.subscriptionPage,
    );
  }

  void showError(String message) {
    state = state.copyWith(errorMessage: message);
  }
}

class _RecordingDisplayPurchaseController extends _RestoreTestController {
  final submittedIds = <String>[];
  final confirmedIds = <String>[];

  @override
  Future<void> purchaseDisplayProduct(
    SubscriptionProduct selected, {
    required String scene,
    required Future<SubscriptionProduct?> Function() confirm,
  }) async {
    submittedIds.add(selected.storeProductId);
    final confirmed = await confirm();
    if (confirmed != null) confirmedIds.add(confirmed.storeProductId);
  }
}
