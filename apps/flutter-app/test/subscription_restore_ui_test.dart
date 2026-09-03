import 'dart:async';

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
import 'package:kando_app/shared/analytics/app_analytics.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/kando_bottom_sheet_page.dart';
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
    'iOS full page reuses the sheet SKU surfaces, spacing, badges, and transition',
    (tester) async {
      final host = _RestoreTestHost();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
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

        double selectedOpacity(String planId) {
          final fade = tester.widget<FadeTransition>(
            find
                .descendant(
                  of: find.byKey(
                    Key('subscription-plan-$planId-selected-overlay'),
                  ),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          return fade.opacity.value;
        }

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
          expect(tester.getSize(surface).height, 74);
        }
        expect(
          tester.getRect(yearlySurface).top -
              tester.getRect(weeklySurface).bottom,
          22,
        );
        expect(
          tester.getRect(lifetimeSurface).top -
              tester.getRect(yearlySurface).bottom,
          22,
        );

        final selectedSurface = tester.widget<DecoratedBox>(
          find.byKey(const Key('subscription-plan-yearly-selected-surface')),
        );
        final selectedDecoration = selectedSurface.decoration as BoxDecoration;
        expect(selectedDecoration.color, const Color(0xFF38372D));
        expect(selectedDecoration.gradient, isNull);
        expect(
          (selectedDecoration.border! as Border).top.color,
          KandoColors.accent,
        );
        expect(
          find.byKey(const Key('subscription-plan-yearly-badge-blur')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('subscription-plan-lifetime-badge-blur')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('subscription-plan-lifetime')));
        await tester.pump();
        expect(selectedOpacity(subscriptionYearlyPlanId), 1);
        expect(selectedOpacity(subscriptionLifetimePlanId), 0);
        await tester.pump(const Duration(milliseconds: 140));
        expect(selectedOpacity(subscriptionYearlyPlanId), 0);
        expect(selectedOpacity(subscriptionLifetimePlanId), 0);
        await tester.pump(const Duration(milliseconds: 140));
        expect(selectedOpacity(subscriptionYearlyPlanId), 0);
        expect(selectedOpacity(subscriptionLifetimePlanId), 1);
        expect(
          host.controller.state.selectedPlanId,
          subscriptionLifetimePlanId,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

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
    'iOS sheet synchronizes SKU selection transition and keeps it in flight',
    (tester) async {
      final controller = _InFlightPurchaseController();
      final host = _RestoreTestHost(controller: controller);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(host.app);
        await tester.pumpAndSettle();
        host.router.push('/subscription?sheet=true');
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(CustomScrollView).last,
          const Offset(0, -240),
        );
        await tester.pumpAndSettle();

        double selectedOpacity(String planId) {
          final fade = tester.widget<FadeTransition>(
            find
                .descendant(
                  of: find.byKey(
                    Key('subscription-plan-$planId-selected-overlay'),
                  ),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          return fade.opacity.value;
        }

        BoxDecoration selectedDecoration(String planId) {
          final surface = tester.widget<DecoratedBox>(
            find.byKey(Key('subscription-plan-$planId-selected-surface')),
          );
          return surface.decoration as BoxDecoration;
        }

        BoxDecoration badgeDecoration(String planId) {
          final badge = tester.widget<AnimatedContainer>(
            find.byKey(Key('subscription-plan-$planId-badge-surface')),
          );
          return badge.decoration! as BoxDecoration;
        }

        void expectBadgeState(String planId, {required bool selected}) {
          final decoration = badgeDecoration(planId);
          expect(
            decoration.color,
            selected ? const Color(0x33F1FE70) : const Color(0xFF34362D),
          );
          expect(
            (decoration.border! as Border).top.color,
            selected ? const Color(0x4DF1FE70) : const Color(0x4D474836),
          );
        }

        final weeklySurface = find.byKey(
          const Key('subscription-plan-weekly-surface'),
        );
        final yearlySurface = find.byKey(
          const Key('subscription-plan-yearly-surface'),
        );
        final lifetimeSurface = find.byKey(
          const Key('subscription-plan-lifetime-surface'),
        );
        final decoration = selectedDecoration(subscriptionYearlyPlanId);
        expect((decoration.border! as Border).top.color, KandoColors.accent);
        expect(decoration.color, const Color(0xFF38372D));
        expect(decoration.gradient, isNull);
        expect(selectedOpacity(subscriptionWeeklyPlanId), 0);
        expect(selectedOpacity(subscriptionYearlyPlanId), 1);
        expect(selectedOpacity(subscriptionLifetimePlanId), 0);
        for (final surface in [weeklySurface, yearlySurface, lifetimeSurface]) {
          expect(tester.getSize(surface).height, 74);
        }
        final weeklyRect = tester.getRect(weeklySurface);
        final yearlyRect = tester.getRect(yearlySurface);
        final lifetimeRect = tester.getRect(lifetimeSurface);
        expect(yearlyRect.top - weeklyRect.bottom, 22);
        expect(lifetimeRect.top - yearlyRect.bottom, 22);
        expectBadgeState(subscriptionYearlyPlanId, selected: true);
        expectBadgeState(subscriptionLifetimePlanId, selected: false);
        expect(
          find.byKey(const Key('subscription-plan-yearly-badge-blur')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('subscription-plan-lifetime-badge-blur')),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const Key('subscription-plan-lifetime')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('subscription-plan-lifetime')));
        await tester.pump();
        expect(selectedOpacity(subscriptionYearlyPlanId), 1);
        expect(selectedOpacity(subscriptionLifetimePlanId), 0);
        await tester.pump(const Duration(milliseconds: 70));
        final fadingYearlyOpacity = selectedOpacity(subscriptionYearlyPlanId);
        expect(fadingYearlyOpacity, inExclusiveRange(0, 1));
        expect(selectedOpacity(subscriptionLifetimePlanId), 0);
        await tester.pump(const Duration(milliseconds: 70));
        expect(selectedOpacity(subscriptionYearlyPlanId), 0);
        expect(selectedOpacity(subscriptionLifetimePlanId), 0);
        await tester.pump(const Duration(milliseconds: 70));
        expect(selectedOpacity(subscriptionYearlyPlanId), 0);
        expect(
          selectedOpacity(subscriptionLifetimePlanId),
          inExclusiveRange(0, 1),
        );
        await tester.pumpAndSettle();
        expect(controller.state.selectedPlanId, subscriptionLifetimePlanId);
        expect(selectedOpacity(subscriptionYearlyPlanId), 0);
        expect(selectedOpacity(subscriptionLifetimePlanId), 1);
        expectBadgeState(subscriptionYearlyPlanId, selected: false);
        expectBadgeState(subscriptionLifetimePlanId, selected: true);

        await tester.ensureVisible(
          find.byKey(const Key('subscription-plan-yearly')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('subscription-plan-yearly')));
        await tester.pumpAndSettle();
        expect(controller.state.selectedPlanId, subscriptionYearlyPlanId);
        expect(selectedOpacity(subscriptionYearlyPlanId), 1);
        expect(selectedOpacity(subscriptionLifetimePlanId), 0);
        expectBadgeState(subscriptionYearlyPlanId, selected: true);
        expectBadgeState(subscriptionLifetimePlanId, selected: false);
        await tester.drag(
          find.byType(CustomScrollView).last,
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('subscription-purchase-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('subscription-purchase-button')));
        await tester.pump();

        expect(controller.state.isPurchasing, isTrue);
        expect(controller.state.selectedPlanId, subscriptionYearlyPlanId);
        final purchasingDecoration = selectedDecoration(
          subscriptionYearlyPlanId,
        );
        expect(
          (purchasingDecoration.border! as Border).top.color,
          KandoColors.accent,
        );
        expect(purchasingDecoration.color, const Color(0xFF38372D));
        expect(purchasingDecoration.gradient, isNull);
        expect(selectedOpacity(subscriptionYearlyPlanId), 1);
        expect(selectedOpacity(subscriptionLifetimePlanId), 0);
        expect(tester.getSize(yearlySurface).height, 74);
        expectBadgeState(subscriptionYearlyPlanId, selected: true);
        expectBadgeState(subscriptionLifetimePlanId, selected: false);
        expect(
          tester
              .widget<InkWell>(
                find.byKey(const Key('subscription-plan-yearly')),
              )
              .onTap,
          isNull,
        );
      } finally {
        controller.completePurchase();
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
      await tester.pump(const Duration(seconds: 16));
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
  }) : controller = controller ?? _RestoreTestController() {
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
        if (actions != null) profileActionsProvider.overrideWithValue(actions),
        if (analytics != null) analyticsProvider.overrideWithValue(analytics),
      ],
      child: MaterialApp.router(
        theme: buildKandoTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    );
  }

  final _RestoreTestController controller;
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
