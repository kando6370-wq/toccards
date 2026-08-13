import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/features/profile/profile_actions.dart';
import 'package:kando_app/features/subscription/apple_current_entitlements.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/features/subscription/subscription_page.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
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

  testWidgets(
    'returning to a mounted subscription container refreshes StoreKit products only while it remains open',
    (tester) async {
      final controller = _ProductRefreshController();
      final host = _RestoreTestHost(controller: controller);
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();
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
      expect(find.text('OK'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Restore failed'), findsNothing);
      expect(find.text('Choose Your Plan'), findsOneWidget);
    },
  );

  testWidgets(
    'missing StoreKit products show Unavailable and cannot replace the first available selection',
    (tester) async {
      final host = _RestoreTestHost(controller: _PartialCatalogController());
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('subscription-plan-yearly')),
          matching: find.text('Unavailable'),
        ),
        findsOneWidget,
      );
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
    'all unavailable products keep Subscribe available without a selected SKU',
    (tester) async {
      final host = _RestoreTestHost(
        controller: _UnavailableCatalogController(),
      );
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();

      host.router.push('/subscription');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.text('Unavailable'), findsNWidgets(3));
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

  testWidgets(
    'Profile purchase keeps its source through Success and Start Exploring',
    (tester) async {
      final host = _RestoreTestHost(initialLocation: '/profile');
      await tester.pumpWidget(host.app);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-state')), 'kept');

      host.router.push('/subscription?source=profile');
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

      expect(find.text('Profile Page'), findsOneWidget);
      expect(find.text('kept'), findsOneWidget);
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

class _RestoreTestHost {
  _RestoreTestHost({
    _RestoreTestController? controller,
    ProfileActions? actions,
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
          builder: (_, state) => SubscriptionPage(
            sheet: state.uri.queryParameters['sheet'] == 'true',
            source: state.uri.queryParameters['source'],
          ),
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
          builder: (_, _) => const Scaffold(body: Text('Home Page')),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Scaffold(
            body: Column(
              children: [
                Text('Profile Page'),
                TextField(key: Key('profile-state')),
              ],
            ),
          ),
        ),
      ],
    );
    app = ProviderScope(
      overrides: [
        subscriptionControllerProvider.overrideWith(() => this.controller),
        if (actions != null) profileActionsProvider.overrideWithValue(actions),
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
  var productRefreshCount = 0;

  @override
  Future<void> refreshProducts() async {
    productRefreshCount += 1;
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
}
