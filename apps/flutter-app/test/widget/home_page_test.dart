import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kando_app/app/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/home/home_performance_controller.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/features/home/trending_today_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/pagination/pagination.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/premium_locked_panel.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/in_memory_portfolio_amount_hidden_storage.dart';
import '../support/home_fixture_asset_bundle.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_collection_repository.dart';
import '../support/mock_home_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  testWidgets(
    'Performance tab reports each actual entry without rebuild duplicates',
    (tester) async {
      final events = <String>[];
      final firebaseEvents = <String>[];
      final analytics = AppAnalytics.recording(
        (event, _) => events.add(event),
        onFirebaseEvent: (event, _) => firebaseEvents.add(event),
      );
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _FreeHomeSubscriptionController.new,
          null,
          analytics,
        ),
      );
      await tester.pumpAndSettle();
      await _waitForHomeAuth(tester);

      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pump();
      await tester.pump();
      expect(
        events.where((event) => event == AnalyticsEvent.homePerformanceView),
        hasLength(1),
      );

      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pump();
      expect(
        events.where((event) => event == AnalyticsEvent.homePerformanceView),
        hasLength(1),
      );

      await tester.tap(find.byKey(const Key('home-overview-tab')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pump();
      expect(
        events.where((event) => event == AnalyticsEvent.homePerformanceView),
        hasLength(2),
      );
      expect(
        firebaseEvents.where(
          (event) => event == AnalyticsEvent.homePerformanceView,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'Figma Home card test fixture stays out of runtime assets and decodes at its design source aspect ratio',
    () async {
      expect(File(homeCardFixturePath).existsSync(), isTrue);
      expect(File(homeCardFixtureAsset).existsSync(), isFalse);

      final data = await homeFixtureAssetBundle.load(homeCardFixtureAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      addTearDown(() {
        frame.image.dispose();
        codec.dispose();
      });

      expect(frame.image.width, 980);
      expect(frame.image.height, 1367);
    },
  );

  testWidgets('Figma Home card image emits a renderable Flutter image frame', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    final context = tester.element(find.byType(SizedBox).first);
    final stream = AssetImage(
      homeCardFixtureAsset,
      bundle: homeFixtureAssetBundle,
    ).resolve(createLocalImageConfiguration(context));
    final loaded = Completer<void>();
    final listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!loaded.isCompleted) {
          loaded.complete();
        }
      },
      onError: (error, stackTrace) {
        if (!loaded.isCompleted) {
          loaded.completeError(error, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    addTearDown(() => stream.removeListener(listener));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(loaded.isCompleted, isTrue);
  });

  testWidgets('v1.1 PRD normal Home renders at the 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader('Fraunces')..addFont(
          rootBundle.load('assets/fonts/Baskerville-BaskervilleSemiBold.ttf'),
        ))
        .load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
          subscriptionControllerProvider.overrideWith(
            _FreeHomeSubscriptionController.new,
          ),
        ],
        child: DefaultAssetBundle(
          bundle: homeFixtureAssetBundle,
          child: MaterialApp(
            theme: buildKandoTheme(),
            home: const RepaintBoundary(
              key: Key('home-figma-golden'),
              child: HomePage(),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('home-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_home_normal_131_21335_390x844.png',
      ),
    );
  });

  testWidgets('v1.1 PRD partial Home failure renders at the 390x844 baseline', (
    tester,
  ) async {
    final repository = _SuccessfulThenFailingHomeRepository();
    await (FontLoader('Fraunces')..addFont(
          rootBundle.load('assets/fonts/Baskerville-BaskervilleSemiBold.ttf'),
        ))
        .load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(repository),
          subscriptionControllerProvider.overrideWith(
            _FreeHomeSubscriptionController.new,
          ),
        ],
        child: DefaultAssetBundle(
          bundle: homeFixtureAssetBundle,
          child: MaterialApp(
            theme: buildKandoTheme(),
            home: const RepaintBoundary(
              key: Key('home-failure-figma-golden'),
              child: HomePage(),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    _refreshHome(tester);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('home-failure-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_home_failure_131_21496_390x844.png',
      ),
    );
  });

  testWidgets('Home shows the M4-1 dashboard information hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    expect(find.text('Overview'), findsOneWidget);
    final modeTabs = find.byKey(const Key('home-mode-tabs'));
    final premiumEntry = find.byKey(const Key('home-premium-top-entry'));
    expect(tester.getSize(modeTabs).height, 42);
    expect(tester.getSize(modeTabs).width, 194);
    expect(tester.getSize(premiumEntry), const Size(32, 32));
    expect(
      tester.getRect(premiumEntry).left - tester.getRect(modeTabs).right,
      8,
    );
    final modeTabsRect = tester.getRect(modeTabs);
    final premiumEntryRect = tester.getRect(premiumEntry);
    await tester.tap(find.text('Performance'));
    await tester.pump();
    expect(tester.getRect(modeTabs), modeTabsRect);
    expect(tester.getRect(premiumEntry), premiumEntryRect);
    await tester.tap(find.text('Overview'));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Overview')).style?.fontSize, 16);
    expect(tester.widget<Text>(find.text('Overview')).style?.height, 24 / 16);
    expect(tester.widget<Text>(find.text('Performance')).style?.fontSize, 12);
    expect(
      tester.widget<Text>(find.text('Performance')).style?.height,
      16 / 12,
    );
    expect(find.byKey(const Key('home-overview-icon')), findsNothing);
    expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
    expect(find.text('PORTFOLIO'), findsOneWidget);
    expect(find.byKey(const Key('home-pull-to-refresh')), findsOneWidget);
    expect(find.text('PORTDOLIO'), findsNothing);
    expect(find.text('Main'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SvgPicture &&
            widget.bytesLoader is SvgAssetLoader &&
            (widget.bytesLoader as SvgAssetLoader).assetName ==
                'assets/home/folder_switch.svg',
      ),
      findsOneWidget,
    );
    expect(find.text(r'$12,450.80'), findsOneWidget);
    expect(find.text('1D'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('15D'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('3M'), findsOneWidget);
    expect(find.text('1Y'), findsOneWidget);
    final oneYearProBadge = find.byKey(
      const Key('home-chart-range-1y-pro-badge'),
    );
    expect(oneYearProBadge, findsOneWidget);
    expect(
      find.descendant(of: oneYearProBadge, matching: find.text('PRO')),
      findsOneWidget,
    );
    expect(tester.getSize(oneYearProBadge), const Size(35, 20));
    expect(
      tester.getRect(oneYearProBadge).left -
          tester.getRect(find.text('1Y')).right,
      4,
    );
    expect(
      find.ancestor(
        of: oneYearProBadge,
        matching: find.byKey(const Key('home-chart-range-1y')),
      ),
      findsOneWidget,
    );
    expect(find.text('6M'), findsNothing);
    expect(find.text('MAX'), findsNothing);
    expect(find.text('Most Valuable'), findsOneWidget);
    expect(find.text('Pikachu'), findsWidgets);
    expect(find.byKey(const Key('home-most-valuable-list')), findsOneWidget);
    expect(
      find.byKey(const Key('home-most-valuable-card-main-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-most-valuable-card-main-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-most-valuable-card-main-2')),
      findsOneWidget,
    );
    expect(find.text('Trending Today'), findsOneWidget);
    expect(find.text('Ragavan, Nimble Pilferer'), findsOneWidget);
    expect(find.text('+12.34%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-performance-tab')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('Overview')).style?.fontSize, 12);
    expect(tester.widget<Text>(find.text('Performance')).style?.fontSize, 16);
  });

  testWidgets(
    'free users see a locked Performance view because portfolio gains are a Pro entitlement',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-performance-locked')), findsOneWidget);
      expect(find.text('Portfolio Performance'), findsOneWidget);
      expect(find.text('Unlock Performance'), findsOneWidget);
      expect(find.text('Most Valuable'), findsNothing);
      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(
        find.byKey(const Key('home-performance-partial-info')),
        findsNothing,
      );

      final panel = find.byKey(const Key('home-performance-locked'));
      final preview = find.byKey(
        const Key('kando-premium-locked-panel-preview'),
      );
      final content = find.byKey(
        const Key('kando-premium-locked-panel-content'),
      );
      final button = find.byKey(const Key('home-unlock-performance'));
      final panelSize = tester.getSize(panel);
      expect(panelSize, const Size(760, 427));
      expect(tester.getSize(preview), panelSize);
      expect(tester.getSize(content), Size(panelSize.width - 66, 222));
      expect(tester.getSize(button), Size(panelSize.width - 66, 36));
      expect(
        tester.getTopLeft(content) - tester.getTopLeft(panel),
        const Offset(33, 63),
      );
      expect(
        find.descendant(of: preview, matching: find.text('Total Paid')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('Market Value')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('Profit / Loss')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('Return')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.byKey(
            const Key('kando-premium-locked-panel-preview-chart'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: preview,
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: preview, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );

      final panelStack = tester.widget<Stack>(
        find.descendant(of: panel, matching: find.byType(Stack)).first,
      );
      expect(panelStack.children.first, isA<ExcludeSemantics>());
      expect(panelStack.children.last, isA<BackdropFilter>());

      final topMetrics = find.byKey(
        const Key('kando-premium-locked-panel-preview-metrics-top'),
      );
      final bottomMetrics = find.byKey(
        const Key('kando-premium-locked-panel-preview-metrics-bottom'),
      );
      final chartPanel = find.byKey(
        const Key('kando-premium-locked-panel-preview-chart-panel'),
      );
      expect(tester.getSize(topMetrics).height, 94);
      expect(tester.getSize(bottomMetrics).height, 94);
      expect(tester.getSize(chartPanel).height, 190);
      final previewTop = tester.getTopLeft(preview).dy;
      expect(tester.getTopLeft(bottomMetrics).dy - previewTop, 106);
      expect(tester.getTopLeft(chartPanel).dy - previewTop, 212);

      final iconAssets = find
          .descendant(of: panel, matching: find.byType(SvgPicture))
          .evaluate()
          .map((element) => element.widget as SvgPicture)
          .map((picture) => (picture.bytesLoader as SvgAssetLoader).assetName)
          .toList();
      expect(iconAssets, [
        'assets/home/performance_locked_lock.svg',
        'assets/home/performance_locked_leading.svg',
        'assets/home/performance_locked_arrow.svg',
      ]);
    },
  );

  testWidgets(
    'Figma locked Performance panel renders at the 350x427 baseline',
    (tester) async {
      await (FontLoader('Fraunces')..addFont(
            rootBundle.load('assets/fonts/Baskerville-BaskervilleSemiBold.ttf'),
          ))
          .load();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(350, 427);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildKandoTheme(),
          home: RepaintBoundary(
            key: const Key('home-performance-locked-golden'),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-1.05, -1.15),
                  radius: 1.15,
                  colors: [
                    Color(0xFF3A4019),
                    Color(0xFF1F2110),
                    KandoColors.ink,
                  ],
                  stops: [0, .36, 1],
                ),
              ),
              child: KandoPremiumLockedPanel(
                key: const Key('responsive-premium-locked-panel'),
                title: 'Portfolio Performance',
                message:
                    'Unlock total paid, profit and loss,\n'
                    'return, longer\n'
                    'history, and change explanations.',
                buttonLabel: 'Unlock Performance',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const Key('home-performance-locked-golden')),
        matchesGoldenFile(
          'goldens/rendered/'
          'figma_home_performance_locked_1892_7057_350x427.png',
        ),
      );

      tester.view.physicalSize = const Size(430, 427);
      await tester.pump();
      expect(
        tester.getSize(
          find.byKey(const Key('responsive-premium-locked-panel')),
        ),
        const Size(430, 427),
      );
      expect(
        tester.getSize(
          find.byKey(const Key('kando-premium-locked-panel-content')),
        ),
        const Size(364, 222),
      );
    },
  );

  testWidgets('free users can tap the 1Y PRO badge to open Premium', (
    tester,
  ) async {
    final portfolioManagement = _TestPortfolioManagementApi();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomePage()),
        GoRoute(
          path: '/subscription',
          builder: (context, state) =>
              const Scaffold(key: Key('home-1y-subscription-target')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
          collectionRepositoryProvider.overrideWithValue(
            _HomeCollectionRepository(portfolioManagement),
          ),
          portfolioManagementApiProvider.overrideWithValue(portfolioManagement),
          portfolioApiClientProvider.overrideWithValue(
            _TestHomePerformanceApi(),
          ),
          currencyRateApiProvider.overrideWithValue(
            const _TestCurrencyRateApi(),
          ),
          subscriptionControllerProvider.overrideWith(
            _FreeHomeSubscriptionController.new,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-chart-range-1y-pro-badge')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('home-1y-subscription-target')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Overview 1Y shows immediate loading while preserving the chart because slow history must acknowledge the tap',
    (tester) async {
      final portfolioApi = _SlowOverviewHistoryApi();
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
          portfolioApi,
        ),
      );
      await tester.pumpAndSettle();
      await _waitForHomeAuth(tester);

      await tester.tap(find.byKey(const Key('home-chart-range-1y')));
      await tester.pump();

      final context = tester.element(find.byType(HomePage));
      final state = ProviderScope.containerOf(
        context,
      ).read(homeControllerProvider);
      expect(state.chartRange, HomeChartRange.oneYear);
      expect(
        state.chartValues,
        mockHomeDashboard
            .portfoliosByFolderId['main']!
            .chartValuesByRange[HomeChartRange.oneMonth],
      );
      expect(portfolioApi.folderIds, ['main']);

      await tester.pump();
      expect(
        find.byKey(const Key('home-chart-range-loading-1y')),
        findsOneWidget,
      );

      portfolioApi.complete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('home-chart-range-loading-1y')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Home chart ranges keep a compact accent indicator because every range switch needs visible confirmation',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-chart-range-7d')));
      await tester.pumpAndSettle();

      final overviewIndicator = find.descendant(
        of: find.byKey(const Key('home-chart-range-7d')),
        matching: find.byType(Container),
      );
      expect(overviewIndicator, findsOneWidget);
      expect(tester.getSize(overviewIndicator).height, 22);
      final overviewDecoration =
          tester.widget<Container>(overviewIndicator).decoration!
              as BoxDecoration;
      expect(overviewDecoration.borderRadius, BorderRadius.circular(4));
      expect(overviewDecoration.gradient, isNotNull);

      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-range-7D')));
      await tester.pumpAndSettle();

      final performanceIndicator = find.ancestor(
        of: find.byKey(const Key('home-performance-range-7D')),
        matching: find.byType(Ink),
      );
      expect(performanceIndicator, findsOneWidget);
      expect(tester.getSize(performanceIndicator).height, 24);
      final selectedDecoration =
          tester.widget<Ink>(performanceIndicator).decoration! as BoxDecoration;
      expect(selectedDecoration.borderRadius, BorderRadius.circular(4));
      expect(selectedDecoration.gradient, isNotNull);

      final previousIndicator = find.ancestor(
        of: find.byKey(const Key('home-performance-range-1M')),
        matching: find.byType(Ink),
      );
      expect(previousIndicator, findsOneWidget);
      final previousDecoration =
          tester.widget<Ink>(previousIndicator).decoration! as BoxDecoration;
      expect(previousDecoration.gradient, isNull);
    },
  );

  testWidgets(
    'Pro users see Performance data and trends because the entitlement unlocks analytics',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('home-chart-range-1y-pro-badge')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-performance-locked')), findsNothing);
      expect(find.text('Market Value'), findsOneWidget);
      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(find.text(r'$800.00'), findsOneWidget);
      expect(find.text('60 cards with purchase price'), findsOneWidget);
      expect(
        find.byKey(const Key('home-performance-partial-info')),
        findsOneWidget,
      );
      expect(find.text('Trending Today'), findsNothing);
    },
  );

  testWidgets(
    'Home Performance metrics match the Figma 2x2 card layout and reuse detail icons',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      const metricKeys = [
        Key('home-performance-metric-total-paid'),
        Key('home-performance-metric-market-value'),
        Key('home-performance-metric-profit-loss'),
        Key('home-performance-metric-return'),
      ];
      const iconAssets = [
        'assets/collection/performance_purchase_cost.svg',
        'assets/collection/performance_current_value.svg',
        'assets/collection/performance_profit_loss.svg',
        'assets/collection/performance_return.svg',
      ];

      for (var index = 0; index < metricKeys.length; index++) {
        final metric = find.byKey(metricKeys[index]);
        expect(metric, findsOneWidget);
        expect(tester.getSize(metric).height, 100);
        final container = find
            .descendant(of: metric, matching: find.byType(Container))
            .first;
        final decoration =
            tester.widget<Container>(container).decoration! as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(12));
        expect(
          decoration.border,
          Border.all(color: const Color(0xFF474836).withValues(alpha: 0.3)),
        );
        final gradient = decoration.gradient! as LinearGradient;
        expect(gradient.begin, Alignment.topCenter);
        expect(gradient.end, Alignment.bottomCenter);
        expect(gradient.colors, [
          const Color(0xFF747B26).withValues(alpha: 0.12),
          const Color(0xFF343434).withValues(alpha: 0.38),
        ]);
        final icon = tester.widget<SvgPicture>(
          find.descendant(of: metric, matching: find.byType(SvgPicture)),
        );
        expect(
          (icon.bytesLoader as SvgAssetLoader).assetName,
          iconAssets[index],
        );
      }

      final totalPaidRect = tester.getRect(find.byKey(metricKeys[0]));
      final marketValueRect = tester.getRect(find.byKey(metricKeys[1]));
      final profitLossRect = tester.getRect(find.byKey(metricKeys[2]));
      expect(marketValueRect.left - totalPaidRect.right, 12);
      expect(profitLossRect.top - totalPaidRect.bottom, 12);
      expect(find.text('Priced cards only'), findsNWidgets(2));
    },
  );

  testWidgets(
    'Performance header replaces a zero purchase-price count without showing info',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
          _TestHomePerformanceApi(purchasePriceItemCount: 0),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      expect(
        find.text('Add purchase prices to track profit and return'),
        findsOneWidget,
      );
      expect(
        find.text('Add purchase prices to track profit and return.'),
        findsNothing,
      );
      expect(find.text('0 cards with purchase price'), findsNothing);
      expect(
        find.byKey(const Key('home-performance-partial-info')),
        findsNothing,
      );
      final marketValue = find.byKey(
        const Key('home-performance-metric-market-value-single'),
      );
      expect(marketValue, findsOneWidget);
      expect(tester.getSize(marketValue).height, 100);
      expect(tester.getSize(marketValue).width, 350);
      expect(
        find.descendant(
          of: marketValue,
          matching: find.text('Priced cards only'),
        ),
        findsNothing,
      );
      final icon = tester.widget<SvgPicture>(
        find.descendant(of: marketValue, matching: find.byType(SvgPicture)),
      );
      expect(
        (icon.bytesLoader as SvgAssetLoader).assetName,
        'assets/collection/performance_current_value.svg',
      );
    },
  );

  testWidgets(
    'Premium Home Performance uses the Figma horizontal asset cards because ranking must stay scannable without a second vertical feed',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      expect(find.text('Top Performers'), findsOneWidget);
      expect(find.byKey(const Key('home-top-performers-list')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('home-top-performers-list'))).width,
        350,
      );
      expect(find.text('Performer 1'), findsOneWidget);
      expect(find.text('Performer 6'), findsNothing);
      expect(find.text('View all'), findsOneWidget);
      expect(
        find.byKey(const Key('home-top-performer-item-pikachu')),
        findsOneWidget,
      );
      expect(find.text(r'$100.00'), findsOneWidget);
      expect(find.text('+50.00%'), findsOneWidget);
      expect(
        tester.getSize(
          find.byKey(const Key('home-top-performer-item-pikachu')),
        ),
        const Size(144, 253),
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('home-top-performer-item-charizard')),
            )
            .dx,
        greaterThan(
          tester
              .getTopLeft(
                find.byKey(const Key('home-top-performer-item-pikachu')),
              )
              .dx,
        ),
      );

      await tester.tap(find.byKey(const Key('home-performance-hide-amount')));
      await tester.pump();
      expect(find.text(hiddenMoneyText), findsWidgets);
      expect(find.text(r'$100.00'), findsNothing);
      expect(find.text('+50.00%'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('home-top-performers-list')),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('home-top-performers-list')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Performer 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Top Performers keeps View all visible for a short ranking because it is the collection navigation entry',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
          _TestHomePerformanceApi(topPerformerCount: 3),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('home-top-performers-view-all')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Empty Performance keeps Top Performers navigation and guidance because an empty collection still needs the ranking entry point',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
          _TestHomePerformanceApi(itemCount: 0, topPerformerCount: 0),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-performance-empty')), findsOneWidget);
      expect(find.text('Add your first card'), findsOneWidget);
      expect(find.text('Scan Cards'), findsOneWidget);
      expect(find.text('Search Cards'), findsOneWidget);
      expect(find.text('Top Performers'), findsOneWidget);
      expect(
        find.byKey(const Key('home-top-performers-view-all')),
        findsOneWidget,
      );
      expect(find.text('No cards in this portfolio yet'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('home-performance-empty'))).height,
        410,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('home-top-performers-empty')))
            .height,
        200,
      );
      expect(
        find.byKey(const Key('home-card-empty-illustration')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-top-performers-list')), findsNothing);
    },
  );

  testWidgets('empty Performance actions keep the Scan and Search routes', (
    tester,
  ) async {
    Future<void> openAction(Key buttonKey, String routeText) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _mockHomeRouteApp(
          subscriptionController: _ProHomeSubscriptionController.new,
          performanceApi: _TestHomePerformanceApi(
            itemCount: 0,
            topPerformerCount: 0,
          ),
        ),
      );
      await _waitForHomeAuth(tester);
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(buttonKey));
      await tester.pumpAndSettle();
      expect(find.text(routeText), findsOneWidget);
    }

    await openAction(
      const Key('home-portfolio-empty-scan'),
      'Scan route target',
    );
    await openAction(
      const Key('home-portfolio-empty-search'),
      'Search route target',
    );
  });

  testWidgets('Top Performers alone reuses the Most Valuable empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mockHomeApp(
        null,
        const _TestCurrencyRateApi(),
        const MockHomeRepository(),
        _ProHomeSubscriptionController.new,
        _TestHomePerformanceApi(topPerformerCount: 0),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-performance-tab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-performance-empty')), findsNothing);
    expect(find.byKey(const Key('home-top-performers-empty')), findsOneWidget);
    expect(find.text('No cards in this portfolio yet'), findsOneWidget);
  });

  testWidgets('Most Valuable opens the matching Card Detail Item context', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mockHomeRouteApp(
        homeRepository: const _MostValuableRouteHomeRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('home-most-valuable-card-main-0'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('card-1|item-pikachu|edit|portfolio'), findsOneWidget);
  });

  testWidgets(
    'Top Performer opens the matching Card Detail Item Performance context',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/cards/:cardId',
            builder: (context, state) => Scaffold(
              body: Text(
                '${state.pathParameters['cardId']}|'
                '${state.uri.queryParameters['item_id']}|'
                '${state.uri.queryParameters['entry']}|'
                '${state.uri.queryParameters['collection']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      final portfolioManagement = _TestPortfolioManagementApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
            collectionRepositoryProvider.overrideWithValue(
              _HomeCollectionRepository(portfolioManagement),
            ),
            portfolioManagementApiProvider.overrideWithValue(
              portfolioManagement,
            ),
            portfolioApiClientProvider.overrideWithValue(
              _TestHomePerformanceApi(),
            ),
            currencyRateApiProvider.overrideWithValue(
              const _TestCurrencyRateApi(),
            ),
            subscriptionControllerProvider.overrideWith(
              _ProHomeSubscriptionController.new,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();
      final performer = find.byKey(
        const Key('home-top-performer-item-pikachu'),
      );
      await tester.ensureVisible(performer);
      await tester.pumpAndSettle();
      await tester.tap(performer);
      await tester.pumpAndSettle();

      expect(
        find.text('card-1|item-pikachu|home performance|portfolio'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Top Performers View All opens the current Folder Portfolio and returning preserves the Home Performance context',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => Consumer(
              builder: (context, ref, child) {
                final collection = ref.watch(collectionControllerProvider);
                final sharedFolder = ref.watch(selectedPortfolioFolderProvider);
                return Scaffold(
                  body: Column(
                    children: [
                      Text(
                        '${collection.selectedTab.name}|'
                        '${collection.selectedFolderId}|$sharedFolder',
                      ),
                      TextButton(
                        key: const Key('collection-return-home'),
                        onPressed: context.pop,
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      final portfolioManagement = _TestPortfolioManagementApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
            collectionRepositoryProvider.overrideWithValue(
              _HomeCollectionRepository(portfolioManagement),
            ),
            portfolioManagementApiProvider.overrideWithValue(
              portfolioManagement,
            ),
            portfolioApiClientProvider.overrideWithValue(
              _TestHomePerformanceApi(),
            ),
            currencyRateApiProvider.overrideWithValue(
              const _TestCurrencyRateApi(),
            ),
            subscriptionControllerProvider.overrideWith(
              _ProHomeSubscriptionController.new,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-range-7D')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-hide-amount')));
      await tester.pumpAndSettle();

      final viewAll = find.byKey(const Key('home-top-performers-view-all'));
      await tester.ensureVisible(viewAll);
      await tester.pumpAndSettle();
      final viewAllTop = tester.getTopLeft(viewAll).dy;
      await tester.tap(viewAll);
      await tester.pumpAndSettle();

      expect(find.text('portfolio|main|main'), findsOneWidget);
      final collectionContext = tester.element(
        find.text('portfolio|main|main'),
      );
      final collectionContainer = ProviderScope.containerOf(collectionContext);
      expect(
        collectionContainer
            .read(collectionControllerProvider)
            .visibleItems
            .map((item) => item.source.id)
            .toList(),
        ['item-pikachu', 'item-charizard', 'item-umbreon'],
      );
      await tester.tap(find.byKey(const Key('collection-return-home')));
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(HomePage));
      final container = ProviderScope.containerOf(homeContext);
      expect(
        container.read(homePerformanceControllerProvider).selectedRange,
        PerformanceRange.sevenDays,
      );
      expect(container.read(homeControllerProvider).amountHidden, isTrue);
      expect(tester.getTopLeft(viewAll).dy, closeTo(viewAllTop, 0.1));
    },
  );

  testWidgets(
    'Performance repairs a missing session grant once and retries the failed request once',
    (tester) async {
      final api = _EntitlementSyncPerformanceApi(succeedAfterRepair: true);
      final repair = _EntitlementRepairTracker(result: true);
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          () => _RepairingHomeSubscriptionController(repair),
          api,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      expect(repair.calls, 1);
      expect(api.calls, 2);
      expect(find.byKey(const Key('home-performance-failure')), findsNothing);
      expect(find.text('Market Value'), findsOneWidget);
    },
  );

  testWidgets(
    'Performance stops after the one repaired retry also needs entitlement sync',
    (tester) async {
      final api = _EntitlementSyncPerformanceApi(succeedAfterRepair: false);
      final repair = _EntitlementRepairTracker(result: true);
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          () => _RepairingHomeSubscriptionController(repair),
          api,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(repair.calls, 1);
      expect(api.calls, 2);
      expect(find.byKey(const Key('home-performance-failure')), findsOneWidget);
    },
  );

  testWidgets(
    'A slow Performance Range request highlights the tap and shows bounded progress while keeping prior data visible',
    (tester) async {
      final api = _SlowRangePerformanceApi();
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
          api,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-performance-range-7D')));
      await tester.pump();

      final homeContext = tester.element(find.byType(HomePage));
      final loading = ProviderScope.containerOf(
        homeContext,
      ).read(homePerformanceControllerProvider);
      expect(loading.selectedRange, PerformanceRange.sevenDays);
      expect(loading.isLoading, isTrue);
      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(
        find.byKey(const Key('home-performance-range-loading-7D')),
        findsOneWidget,
      );

      api.completeRange();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('home-performance-range-loading-7D')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Performance Range failure keeps the previous Range and data and reports the failed action at the top',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
          _FailingRangePerformanceApi(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(HomePage));
      final container = ProviderScope.containerOf(homeContext);
      final previousData = container
          .read(homePerformanceControllerProvider)
          .data;
      await tester.tap(find.byKey(const Key('home-performance-range-7D')));
      await tester.pumpAndSettle();

      final failed = container.read(homePerformanceControllerProvider);
      expect(failed.selectedRange, PerformanceRange.oneMonth);
      expect(failed.data, same(previousData));
      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.text(genericFailureToastText), findsOneWidget);
      await tester.pump(kandoTopToastDuration);
      await tester.pump();
    },
  );

  testWidgets(
    'Performance Range reports failure after the one entitlement repair retry is exhausted',
    (tester) async {
      final api = _EntitlementSyncRangePerformanceApi();
      final repair = _EntitlementRepairTracker(result: true);
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          () => _RepairingHomeSubscriptionController(repair),
          api,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-range-7D')));
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(HomePage));
      final failed = ProviderScope.containerOf(
        homeContext,
      ).read(homePerformanceControllerProvider);
      expect(repair.calls, 1);
      expect(api.rangeCalls, 2);
      expect(failed.selectedRange, PerformanceRange.oneMonth);
      expect(failed.data, isNotNull);
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.text(genericFailureToastText), findsOneWidget);
      await tester.pump(kandoTopToastDuration);
      await tester.pump();
    },
  );

  testWidgets(
    'Performance Range keeps prior data when entitlement repair itself fails because an unknown grant cannot authorize a retry',
    (tester) async {
      final api = _EntitlementSyncRangePerformanceApi();
      final repair = _EntitlementRepairTracker(result: false);
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          () => _RepairingHomeSubscriptionController(repair),
          api,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(HomePage));
      final container = ProviderScope.containerOf(homeContext);
      final previousData = container
          .read(homePerformanceControllerProvider)
          .data;
      await tester.tap(find.byKey(const Key('home-performance-range-7D')));
      await tester.pumpAndSettle();

      final failed = container.read(homePerformanceControllerProvider);
      expect(repair.calls, 1);
      expect(api.rangeCalls, 1);
      expect(failed.selectedRange, PerformanceRange.oneMonth);
      expect(failed.data, same(previousData));
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.text(genericFailureToastText), findsOneWidget);
      await tester.pump(kandoTopToastDuration);
      await tester.pump();
    },
  );

  testWidgets(
    'Performance tooltip and partial-price info are mutually exclusive because stale overlays misstate the selected context',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      final chart = find.byKey(const Key('home-performance-chart'));
      final chartRect = tester.getRect(chart);
      await tester.tapAt(Offset(chartRect.right - 1, chartRect.center.dy));
      await tester.pump();

      final tooltip = tester.widget<Semantics>(chart).properties.value!;
      expect(tooltip, contains('Date: Aug 12, 2026'));
      expect(tooltip, isNot(contains('Daily Change:')));
      expect(tooltip, contains(r'Market: +$20.00'));
      expect(tooltip, contains(r'Portfolio: +$24.00'));
      expect(tooltip, contains('Qty: 4 (+2)'));
      expect(tooltip, isNot(contains('Price:')));

      await tester.tap(find.byKey(const Key('home-performance-partial-info')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        'No chart point selected',
      );
      expect(
        find.text(
          'Profit and return are calculated only from cards with purchase prices',
        ),
        findsOneWidget,
      );

      await tester.tapAt(Offset(chartRect.right - 1, chartRect.center.dy));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Profit and return are calculated only from cards with purchase prices',
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('home-performance-range-7D')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        'No chart point selected',
      );

      await tester.tap(find.byKey(const Key('home-performance-partial-info')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-overview-tab')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Profit and return are calculated only from cards with purchase prices',
        ),
        findsNothing,
      );
      expect(find.text('PORTFOLIO'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();
      final refreshedChart = find.byKey(const Key('home-performance-chart'));
      await tester.tapAt(tester.getRect(refreshedChart).center);
      await tester.pump();
      await tester.tap(find.byKey(const Key('home-performance-folder')));
      await tester.pump();
      expect(
        tester.widget<Semantics>(refreshedChart).properties.value,
        'No chart point selected',
      );
    },
  );

  testWidgets(
    'Performance tooltip keeps unavailable Market and Portfolio rows visible without inventing changes',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      final chart = find.byKey(const Key('home-performance-chart'));
      final chartRect = tester.getRect(chart);
      await tester.tapAt(Offset(chartRect.left + 1, chartRect.center.dy));
      await tester.pump();

      final tooltip = tester.widget<Semantics>(chart).properties.value!;
      expect(tooltip, contains('Date: Aug 11, 2026'));
      expect(tooltip, contains('Market: --'));
      expect(tooltip, contains('Portfolio: --'));
      expect(tooltip, contains('Qty: 2'));
      expect(tooltip, isNot(contains('Daily Change:')));
    },
  );

  testWidgets(
    'Performance tooltip converts Market and Portfolio changes to the selected currency',
    (tester) async {
      final preferences = _TestPortfolioManagementApi();
      await tester.pumpWidget(
        _mockHomeApp(
          preferences,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      final chart = find.byKey(const Key('home-performance-chart'));
      final chartRect = tester.getRect(chart);
      await tester.tapAt(Offset(chartRect.right - 1, chartRect.center.dy));
      await tester.pump();

      final tooltip = tester.widget<Semantics>(chart).properties.value!;
      expect(tooltip, contains('Market: +€18.20'));
      expect(tooltip, contains('Portfolio: +€21.84'));
      expect(tooltip, contains('Qty: 4 (+2)'));
      expect(tooltip, isNot(contains('Daily Change:')));
    },
  );

  testWidgets(
    'Performance header and purchase-price tip match the Figma geometry and visibility behavior',
    (tester) async {
      await (FontLoader('Fraunces')..addFont(
            rootBundle.load('assets/fonts/Baskerville-BaskervilleSemiBold.ttf'),
          ))
          .load();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();

      final header = find.byKey(const Key('home-performance-header'));
      final title = find.text('PERFORMANCE');
      final eye = find.byKey(const Key('home-performance-hide-amount'));
      final subtitle = find.text('60 cards with purchase price');
      final info = find.byKey(const Key('home-performance-partial-info'));
      expect(tester.getSize(header), const Size(350, 56));
      expect(tester.getSize(eye), const Size(24, 24));
      expect(tester.getSize(info), const Size(13, 13));
      expect(tester.getRect(eye).left - tester.getRect(title).right, 8);
      expect(
        tester.getRect(info).left - tester.getRect(subtitle).right,
        closeTo(4, 0.001),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SvgPicture &&
              widget.bytesLoader is SvgAssetLoader &&
              (widget.bytesLoader as SvgAssetLoader).assetName ==
                  'assets/home/performance_info.svg',
        ),
        findsOneWidget,
      );
      await expectLater(
        header,
        matchesGoldenFile(
          '../goldens/rendered/figma_home_performance_header_1911_8120_350x56.png',
        ),
      );

      await tester.tap(info);
      await tester.pump();
      final tip = find.byKey(const Key('home-performance-info-tip'));
      expect(tester.getSize(tip), const Size(242, 53.5));
      final tipRect = tester.getRect(tip);
      final infoRect = tester.getRect(info);
      expect(tipRect.bottom, closeTo(infoRect.top - 3, .01));
      expect(tipRect.center.dx, closeTo(infoRect.center.dx, .01));
      expect(
        find.text(
          'Profit and return are calculated only from cards with purchase prices',
        ),
        findsOneWidget,
      );
      final notch = tester.widget<SvgPicture>(
        find.byKey(const Key('home-performance-info-notch')),
      );
      expect(notch.width, 19);
      expect(notch.height, 6.70087);
      expect(
        (notch.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/performance_tooltip_notch.svg',
      );
      await expectLater(
        tip,
        matchesGoldenFile(
          '../goldens/rendered/figma_home_performance_tip_2209_15661_242x54.png',
        ),
      );

      await tester.tap(find.byKey(const Key('home-overview-tab')));
      await tester.pumpAndSettle();
      expect(tip, findsNothing);
      expect(find.text('PORTFOLIO'), findsOneWidget);
    },
  );

  testWidgets(
    '1D Performance keeps Qty visible while hidden amounts stay hidden because privacy applies to tooltip money only',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-performance-hide-amount')));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-performance-range-1D')));
      await tester.pumpAndSettle();

      final chart = find.byKey(const Key('home-performance-chart'));
      await tester.tapAt(tester.getRect(chart).center);
      await tester.pump();
      final tooltip = tester.widget<Semantics>(chart).properties.value!;
      expect(tooltip, isNot(contains('Daily Change:')));
      expect(tooltip, contains('Market: $hiddenMoneyText'));
      expect(tooltip, contains('Portfolio: $hiddenMoneyText'));
      expect(tooltip, contains('Qty: 4 (+2)'));
      expect(tooltip, isNot(contains(r'$20.00')));
      expect(tooltip, isNot(contains(r'$24.00')));
    },
  );

  testWidgets(
    'Home Performance makes a single valid data point visible before selection',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const MockHomeRepository(),
          _ProHomeSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-performance-range-1D')));
      await tester.pumpAndSettle();

      final chart = find.byKey(const Key('home-performance-chart'));
      final customPaint = tester.widget<CustomPaint>(
        find.descendant(of: chart, matching: find.byType(CustomPaint)),
      );
      final haloAlpha = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        customPaint.painter!.paint(Canvas(recorder), const Size(100, 100));
        final image = await recorder.endRecording().toImage(100, 100);
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return pixels!.getUint8((56 * 100 + 55) * 4 + 3);
      });

      expect(haloAlpha, greaterThan(0));
    },
  );

  testWidgets(
    'Portfolio chart selects the nearest date anywhere in the plot because users inspect historical values',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());

      final chart = find.byKey(const Key('home-portfolio-chart'));
      expect(chart, findsOneWidget);
      expect(
        tester.widget<Semantics>(chart).properties.value,
        'No chart point selected',
      );

      var chartRect = tester.getRect(chart);
      final touch = await tester.startGesture(
        Offset(chartRect.left + 1, chartRect.center.dy),
      );
      await tester.pump();
      final overviewTooltip = tester.widget<Semantics>(chart).properties.value!;
      expect(overviewTooltip, contains('Date: Jan 20, 2025'));
      expect(overviewTooltip, contains('Price:'));
      expect(overviewTooltip, isNot(contains('Daily Change')));

      await touch.moveTo(Offset(chartRect.right - 1, chartRect.center.dy));
      await tester.pump();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        contains('Date: Feb 18, 2025'),
      );

      await touch.up();
      await tester.pump();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        'No chart point selected',
      );

      chartRect = tester.getRect(chart);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(
        location: Offset(chartRect.right + 20, chartRect.center.dy),
      );
      await tester.pump();
      await mouse.moveTo(chartRect.center);
      await tester.pump();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        isNot('No chart point selected'),
      );

      await mouse.moveTo(Offset(chartRect.right + 20, chartRect.center.dy));
      await tester.pump();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        'No chart point selected',
      );
      await mouse.removePointer();
    },
  );

  testWidgets(
    'Home content uses the standard top spacing below the safe area',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byKey(const Key('home-normal-content')),
      );

      expect(
        scrollView.padding,
        const EdgeInsets.fromLTRB(20, KandoLayout.mainTabTopPadding, 20, 132),
      );
    },
  );

  testWidgets('Home chart follows the nearest day while tapping and dragging', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    final chart = find.byKey(const Key('home-portfolio-chart'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    final chartRect = tester.getRect(chart);

    final gesture = await tester.startGesture(
      Offset(chartRect.left + 1, chartRect.center.dy),
    );
    await tester.pump();
    expect(
      tester.widget<Semantics>(chart).properties.value,
      r'Date: Jan 20, 2025, Price: $10,800.00',
    );

    await gesture.moveTo(
      Offset(chartRect.left + chartRect.width * 4 / 9, chartRect.center.dy),
    );
    await tester.pump();
    expect(
      tester.widget<Semantics>(chart).properties.value,
      r'Date: Feb 3, 2025, Price: $11,940.00',
    );

    await gesture.moveTo(Offset(chartRect.right - 1, chartRect.center.dy));
    await tester.pump();
    expect(
      tester.widget<Semantics>(chart).properties.value,
      r'Date: Feb 18, 2025, Price: $12,450.80',
    );
    await gesture.up();
    await tester.pump();
    expect(
      tester.widget<Semantics>(chart).properties.value,
      'No chart point selected',
    );
  });

  testWidgets('Home mode tabs use the Figma text-only states', (tester) async {
    await tester.pumpWidget(_mockHomeApp());

    final overview = tester.widget<Text>(find.text('Overview'));
    final performance = tester.widget<Text>(find.text('Performance'));
    expect(overview.style?.fontSize, 16);
    expect(overview.style?.color, KandoColors.primaryOnDefault);
    expect(performance.style?.fontSize, 12);
    expect(performance.style?.color, const Color(0xFF615D3B));
    expect(find.byKey(const Key('home-overview-icon')), findsNothing);
    expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
  });

  testWidgets('Home View all links use 16px text', (tester) async {
    await tester.pumpWidget(_mockHomeApp());

    for (final text in tester.widgetList<Text>(find.text('View all'))) {
      expect(text.style?.fontSize, 16);
      expect(text.style?.height, 20 / 16);
    }

    final arrows = tester.widgetList<SvgPicture>(
      find.byKey(const Key('home-view-all-arrow')),
    );
    expect(arrows, hasLength(2));
    for (final arrow in arrows) {
      expect(arrow.width, 14);
      expect(arrow.height, 10);
      expect(
        (arrow.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/view_all_arrow.svg',
      );
    }
  });

  testWidgets('Most Valuable change badge matches the Figma glass style', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    final firstCard = find.byKey(const Key('home-most-valuable-card-main-0'));
    await tester.ensureVisible(firstCard);
    await tester.pumpAndSettle();
    final backdrop = find.descendant(
      of: firstCard,
      matching: find.byType(BackdropFilter),
    );
    final badgeContainer = find.descendant(
      of: backdrop,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.padding ==
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
    );
    final badgeText = tester.widget<Text>(find.text('+3.20%'));
    final badgePosition = find.descendant(
      of: firstCard,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Positioned && widget.top == 0 && widget.right == -2,
      ),
    );

    expect(backdrop, findsOneWidget);
    expect(badgeContainer, findsOneWidget);
    expect(badgePosition, findsOneWidget);
    expect(
      (tester.widget<Container>(badgeContainer).decoration as BoxDecoration)
          .color,
      KandoColors.accentGlow10,
    );
    expect(badgeText.style?.fontSize, 10);
    expect(badgeText.style?.fontWeight, FontWeight.w400);
    expect(badgeText.style?.height, 14 / 10);
  });

  testWidgets('Figma Home headings and card names use Fraunces', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    expect(
      tester.widget<Text>(find.text('Most Valuable')).style?.fontFamily,
      'Fraunces',
    );
    expect(
      tester.widget<Text>(find.text('Pikachu').first).style?.fontFamily,
      'Fraunces',
    );
    expect(
      tester
          .widget<Text>(find.text('Ragavan, Nimble Pilferer'))
          .style
          ?.fontFamily,
      'Fraunces',
    );
  });

  testWidgets(
    'Figma Home arrow assets render without a Material Icons font dependency',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());

      final currencyChevron = tester.widget<Image>(
        find.byKey(const Key('home-currency-chevron')),
      );
      expect(currencyChevron.width, 30);
      expect(currencyChevron.height, 30);
      expect(find.byKey(const Key('home-view-all-arrow')), findsNWidgets(2));
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_forward), findsNothing);
    },
  );

  testWidgets('Home currency control matches the Figma glass style', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    final control = find.byKey(const Key('home-currency-control'));
    final blur = find.byKey(const Key('home-currency-blur'));
    final material = tester.widget<Material>(
      find.descendant(of: control, matching: find.byType(Material)),
    );
    final padding = tester.widget<Padding>(
      find.descendant(
        of: control,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding == const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
    final currencyText = tester.widget<Text>(find.text('USD'));
    final currencySymbol = tester.widget<Text>(
      find.byKey(const Key('home-currency-symbol')),
    );

    expect(tester.getSize(control), const Size(98, 42));
    expect(blur, findsOneWidget);
    expect(material.color, KandoColors.accentGlow10);
    expect(padding.padding, const EdgeInsets.symmetric(horizontal: 12));
    expect(currencyText.style?.color, KandoColors.accent);
    expect(currencyText.style?.fontSize, 16);
    expect(currencyText.style?.fontWeight, FontWeight.w400);
    expect(currencyText.style?.height, 24 / 16);
    expect(currencySymbol.data, AppCurrency.usd.symbol);
    expect(currencySymbol.style?.color, KandoColors.accent);
    expect(currencySymbol.style?.fontSize, 10);
  });

  testWidgets(
    'folder picker changes portfolio sections but not Trending Today',
    (tester) async {
      final preferences = _TestPortfolioManagementApi();
      await tester.pumpWidget(_mockHomeApp(preferences));
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();

      expect(find.text('DRAG AND DROP TO CHANGE ORDER'), findsOneWidget);
      expect(find.byKey(const Key('collection-folder-add')), findsOneWidget);
      expect(
        find.byKey(const Key('collection-folder-edit-sealed')),
        findsOneWidget,
      );

      await tester.tap(find.text('Sealed').last);
      await tester.pumpAndSettle();

      expect(find.text('Sealed'), findsOneWidget);
      expect(find.text(r'$8,640.00'), findsOneWidget);
      expect(find.text('Evolving Skies Booster Box'), findsOneWidget);
      expect(find.text('Ragavan, Nimble Pilferer'), findsOneWidget);
      expect(preferences.selectedFolderIds, ['sealed']);
    },
  );

  testWidgets(
    'folder picker closes and refreshes Home before preference persistence because a real switch changed the portfolio',
    (tester) async {
      final preferences = _DelayedPortfolioManagementApi();
      final homeRepository = _CountingHomeRepository();
      await tester.pumpWidget(
        _mockHomeApp(preferences, const _TestCurrencyRateApi(), homeRepository),
      );
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sealed').last);
      await tester.pumpAndSettle();

      expect(find.text('Select Portfolio'), findsNothing);
      expect(find.text('Sealed'), findsOneWidget);
      expect(find.text(r'$8,640.00'), findsOneWidget);
      expect(homeRepository.calls, 2);

      preferences.preferenceWrite.complete();
      await tester.pumpAndSettle();
      expect(homeRepository.calls, 2);
    },
  );

  testWidgets(
    'renaming a folder keeps Home loaded because the selected portfolio did not change',
    (tester) async {
      final homeRepository = _CountingHomeRepository();
      await tester.pumpWidget(
        _mockHomeApp(
          _TestPortfolioManagementApi(),
          const _TestCurrencyRateApi(),
          homeRepository,
        ),
      );
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-folder-edit-sealed')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('collection-folder-name')),
        'Trade Binder',
      );
      await tester.tap(find.byKey(const Key('collection-folder-name-save')));
      await tester.pumpAndSettle();

      expect(find.text('Trade Binder'), findsOneWidget);
      expect(homeRepository.calls, 1);
    },
  );

  testWidgets(
    'currency picker converts the Figma portfolio and card price surfaces',
    (tester) async {
      final preferences = _TestPortfolioManagementApi();
      await tester.pumpWidget(_mockHomeApp(preferences));
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        KandoColors.surface,
      );
      expect(find.text('GBP'), findsOneWidget);
      expect(find.text('SGD'), findsOneWidget);

      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();

      expect(find.text('EUR'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('home-currency-symbol'))).data,
        AppCurrency.eur.symbol,
      );
      expect(find.textContaining('11,330.23'), findsOneWidget);
      expect(find.textContaining('9,100,000'), findsWidgets);
      expect(preferences.currencyCodes, ['EUR']);
    },
  );

  testWidgets(
    'currency search filters by display name before the real rate and preference update',
    (tester) async {
      final preferences = _TestPortfolioManagementApi();
      await tester.pumpWidget(_mockHomeApp(preferences));
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('home-currency-search')),
        'pound',
      );
      await tester.pump();

      expect(find.text('GBP'), findsOneWidget);
      expect(find.text('EUR'), findsNothing);

      await tester.tap(find.text('GBP'));
      await tester.pumpAndSettle();

      expect(preferences.currencyCodes, ['GBP']);
      expect(find.text('GBP'), findsOneWidget);
    },
  );

  testWidgets('currency picker failure uses the typed top toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mockHomeApp(
        _TestPortfolioManagementApi(),
        const _TestCurrencyRateApi(fails: true),
      ),
    );
    await _waitForHomeAuth(tester);

    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
    expect(find.byKey(const Key('kando-floating-toast')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(genericFailureToastText), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
  });

  testWidgets(
    'amount visibility uses the current eye state and keeps card prices visible',
    (tester) async {
      final preferences = _TestPortfolioManagementApi();
      await tester.pumpWidget(_mockHomeApp(preferences));
      await _waitForHomeAuth(tester);

      final cardPrice = find.descendant(
        of: find.byKey(const Key('home-most-valuable-card-main-0')),
        matching: find.text(r'$10,000,000.12'),
      );
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
      expect(cardPrice, findsOneWidget);

      await tester.tap(find.byKey(const Key('home-hide-amount')));
      await tester.pump();

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
      expect(find.text(hiddenMoneyText), findsOneWidget);
      expect(find.text(r'$12,450.80'), findsNothing);
      expect(cardPrice, findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(cardPrice, findsOneWidget);
      expect(preferences.amountHiddenValues, isEmpty);
    },
  );

  testWidgets(
    'Most Valuable change badges stay tied to the displayed card data after a portfolio switch',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());
      await _waitForHomeAuth(tester);

      await tester.ensureVisible(
        find.byKey(const Key('home-most-valuable-card-main-0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('+3.20%'), findsOneWidget);
      expect(find.text('0.001%'), findsNothing);

      await tester.ensureVisible(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sealed').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('home-most-valuable-card-sealed-0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('+5.40%'), findsOneWidget);
      expect(find.text('0.001%'), findsNothing);
    },
  );

  testWidgets(
    'page data failure keeps the Figma dashboard shell and refreshes local panels',
    (tester) async {
      final repository = _SuccessfulThenFailingHomeRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
          child: const _HomeTestApp(),
        ),
      );

      _refreshHome(tester);
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(find.text('Trending Today'), findsOneWidget);
      expect(find.text('Ragavan, Nimble Pilferer'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNWidgets(2));
      expect(find.byKey(const Key('home-failure-chart')), findsOneWidget);
      expect(
        find.byKey(const Key('home-failure-most-valuable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-failure-chart-refresh')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-failure-most-valuable-refresh')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-failure-error-icon')),
        findsNWidgets(2),
      );
      final failureIcon = tester.widget<SvgPicture>(
        find.byKey(const Key('home-failure-error-icon')).first,
      );
      expect(
        (failureIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/failure_state_error.svg',
      );
      final refreshIcon = tester.widget<SvgPicture>(
        find.byKey(const Key('home-failure-refresh-icon')).first,
      );
      expect(refreshIcon.width, 16);
      expect(refreshIcon.height, 16);
      expect(
        (refreshIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/refresh.svg',
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/home/refresh_button.png',
        ),
        findsNothing,
      );
      expect(find.text('Home'), findsOneWidget);
      expect(repository.calls, 2);

      await tester.tap(find.byKey(const Key('home-failure-chart-refresh')));
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);
      expect(repository.calls, 3);
    },
  );

  testWidgets(
    'Trending failure stays local because portfolio history remains usable',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeRepositoryProvider.overrideWithValue(
              const _TrendingUnavailableHomeRepository(),
            ),
          ],
          child: MaterialApp(theme: buildKandoTheme(), home: const HomePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(find.byKey(const Key('home-failure-chart')), findsNothing);
      expect(find.byKey(const Key('home-most-valuable-list')), findsOneWidget);
      expect(find.byKey(const Key('home-failure-trending')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-failure-trending')),
          matching: find.byKey(const Key('home-failure-error-icon')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-failure-trending-refresh')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Most Valuable failure refresh independently restores dashboard content',
    (tester) async {
      final repository = _SuccessfulThenFailingHomeRepository();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
          child: const _HomeTestApp(),
        ),
      );

      _refreshHome(tester);
      await tester.pumpAndSettle();

      final refresh = find.byKey(
        const Key('home-failure-most-valuable-refresh'),
      );
      await tester.scrollUntilVisible(refresh, 120);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(find.text(noContentAvailableText), findsNothing);
      expect(find.byKey(const Key('home-most-valuable-list')), findsOneWidget);
      expect(repository.calls, 3);
    },
  );

  testWidgets('failed dashboard uses Figma placeholders for every trend card', (
    tester,
  ) async {
    final repository = _SuccessfulThenFailingHomeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
        child: const _HomeTestApp(),
      ),
    );
    _refreshHome(tester);
    await tester.pumpAndSettle();

    for (var index = 0; index < 3; index += 1) {
      expect(
        find.byKey(Key('home-failure-trend-placeholder-$index')),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'auth startup shows the empty portfolio state instead of a false data failure',
    (tester) async {
      final storage = InMemoryAuthStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStorageProvider.overrideWithValue(storage),
            authRepositoryProvider.overrideWithValue(
              _PendingStartupAuthRepository(storage),
            ),
          ],
          child: const _HomeTestApp(),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(HomePage));
      final state = ProviderScope.containerOf(
        context,
      ).read(homeControllerProvider);
      expect(state.isLoading, isTrue);
      expect(state.isUnavailable, isFalse);
      expect(find.text('Add your first card'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);
      expect(find.text('Refresh'), findsNothing);
    },
  );

  testWidgets(
    'empty folder keeps the PORTFOLIO label because copy must not change with data state',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Empty'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      expect(find.text('No cards in this portfolio yet'), findsOneWidget);
      expect(find.text('PORTDOLIO'), findsNothing);
      expect(find.text('PORTFOLIO'), findsOneWidget);
      expect(find.text('Add your first card'), findsOneWidget);
      expect(
        find.text(
          "Start tracking your collection's\nvalue,price trends, and top cards.",
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-portfolio-empty-illustration')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-card-empty-illustration')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-empty-magnifier-outer')),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const Key('home-empty-magnifier-inner')),
        findsNWidgets(2),
      );
      final magnifierOuter = tester.widget<SvgPicture>(
        find.byKey(const Key('home-empty-magnifier-outer')).first,
      );
      final magnifierInner = tester.widget<SvgPicture>(
        find.byKey(const Key('home-empty-magnifier-inner')).first,
      );
      expect(
        (magnifierOuter.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/empty_state_magnifier_outer.svg',
      );
      expect(
        (magnifierInner.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/empty_state_magnifier_inner.svg',
      );
      expect(
        find.byKey(const Key('home-portfolio-empty-scan')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-portfolio-empty-search')),
        findsOneWidget,
      );
      expect(find.text('Scan Cards'), findsOneWidget);
      expect(find.text('Search Cards'), findsOneWidget);
      expect(find.text('1D'), findsNothing);
      expect(find.text('Trending Today'), findsOneWidget);
    },
  );

  testWidgets(
    'holdings without PostgreSQL prices show an unavailable market state instead of the empty collection CTA',
    (tester) async {
      await tester.pumpWidget(
        _mockHomeApp(
          null,
          const _TestCurrencyRateApi(),
          const _MissingMarketPriceHomeRepository(),
        ),
      );
      await _waitForHomeAuth(tester);

      expect(find.text('--'), findsOneWidget);
      expect(find.text('Market price unavailable'), findsNWidgets(2));
      expect(
        find.byKey(const Key('home-portfolio-market-price-missing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-most-valuable-market-price-missing')),
        findsOneWidget,
      );
      expect(find.text('Add your first card'), findsNothing);
      expect(find.text('No cards in this portfolio yet'), findsNothing);
      expect(find.byKey(const Key('home-portfolio-empty-scan')), findsNothing);
    },
  );

  testWidgets('empty portfolio actions open Scan and Search', (tester) async {
    Future<void> openAction(Key buttonKey, String routeText) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_mockHomeRouteApp());
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Empty'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      final buttonTap = tester
          .widget<GestureDetector>(
            find.descendant(
              of: find.byKey(buttonKey),
              matching: find.byType(GestureDetector),
            ),
          )
          .onTap!;
      buttonTap();
      await tester.pumpAndSettle();
      expect(find.text(routeText), findsOneWidget);
    }

    await openAction(
      const Key('home-portfolio-empty-scan'),
      'Scan route target',
    );
    await openAction(
      const Key('home-portfolio-empty-search'),
      'Search route target',
    );
  });

  testWidgets('Profile bottom tab navigates to the existing Profile page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.byKey(const Key('kando-tab-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Sign in / Sign up'), findsOneWidget);
  });

  testWidgets('Collection opens with Home portfolio preferences', (
    tester,
  ) async {
    final preferences = _TestPortfolioManagementApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
          portfolioManagementApiProvider.overrideWithValue(preferences),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );
    await _waitForHomeAuth(tester);

    final homeContext = tester.element(find.byType(HomePage));
    final container = ProviderScope.containerOf(homeContext);
    expect(
      await container
          .read(homeControllerProvider.notifier)
          .selectFolder('sealed'),
      isTrue,
    );
    expect(
      await container
          .read(homeControllerProvider.notifier)
          .toggleAmountHidden(),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('kando-tab-collection')));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('This section is coming soon.'), findsNothing);
    final collection = container.read(collectionControllerProvider);
    expect(collection.selectedFolder.id, 'sealed');
    expect(collection.amountHidden, isTrue);
  });

  testWidgets(
    'Most Valuable View all opens the selected portfolio by value because Home only previews the top cards',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
          ],
          child: const _HomeTestAppWithRoutes(),
        ),
      );
      await _waitForHomeAuth(tester);

      await tester.tap(find.byKey(const Key('home-most-valuable-view-all')));
      await tester.pumpAndSettle();

      expect(find.byType(CollectionPage), findsOneWidget);
      final context = tester.element(find.byType(CollectionPage));
      final collection = ProviderScope.containerOf(
        context,
      ).read(collectionControllerProvider);
      expect(collection.selectedTab, CollectionTab.portfolio);
      expect(collection.selectedSort, CollectionSort.valueDesc);
      expect(collection.visibleItems.first.name, 'Charizard ex');
    },
  );

  testWidgets(
    'Trending View all opens the live ranking because users need more than the Home preview',
    (tester) async {
      final trendingApi = _TrendingCardDataApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
            cardDataApiClientProvider.overrideWithValue(trendingApi),
          ],
          child: const _HomeTestAppWithRoutes(),
        ),
      );

      final viewAll = find.byKey(const Key('home-trending-view-all'));
      await tester.ensureVisible(viewAll);
      await tester.tap(viewAll);
      await tester.pumpAndSettle();

      expect(find.byType(TrendingTodayPage), findsOneWidget);
      final title = find.text('Trending Today');
      final backButton = find.byType(BackButton);
      expect(title, findsOneWidget);
      expect(backButton, findsOneWidget);
      expect(
        tester.getCenter(title).dy,
        closeTo(tester.getCenter(backButton).dy, 1),
      );
      expect(find.text('Live Trending'), findsOneWidget);
      expect(find.text('+5.00%'), findsOneWidget);
      expect(find.text('Falling Trending'), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('search-card-live-trending'))),
        const Size(170, 378),
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const Key('search-card-image-container-live-trending'),
              ),
            )
            .height,
        186,
      );
      expect(trendingApi.requestedPages, [1]);
    },
  );

  testWidgets(
    'Trending View all shows an empty state because PostgreSQL zero rows is a successful response',
    (tester) async {
      final trendingApi = _EmptyTrendingCardDataApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
            cardDataApiClientProvider.overrideWithValue(trendingApi),
          ],
          child: const _HomeTestAppWithRoutes(),
        ),
      );

      final viewAll = find.byKey(const Key('home-trending-view-all'));
      await tester.ensureVisible(viewAll);
      await tester.tap(viewAll);
      await tester.pumpAndSettle();

      expect(find.byType(KandoEmptyBlock), findsOneWidget);
      expect(find.text('No trending cards available'), findsOneWidget);
      expect(find.byType(KandoFailureBlock), findsNothing);
      expect(find.text(refreshText), findsNothing);
      expect(trendingApi.requestedPages, [1]);
    },
  );

  testWidgets(
    'Trending View all shows Refresh only when the PostgreSQL request fails',
    (tester) async {
      final trendingApi = _FailingTrendingCardDataApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
            cardDataApiClientProvider.overrideWithValue(trendingApi),
          ],
          child: const _HomeTestAppWithRoutes(),
        ),
      );

      final viewAll = find.byKey(const Key('home-trending-view-all'));
      await tester.ensureVisible(viewAll);
      await tester.tap(viewAll);
      await tester.pumpAndSettle();

      expect(find.byType(KandoFailureBlock), findsOneWidget);
      expect(find.text(refreshText), findsOneWidget);

      await tester.tap(find.text(refreshText));
      await tester.pumpAndSettle();

      expect(trendingApi.requestedPages, [1, 1]);
    },
  );

  testWidgets(
    'Trending pagination failure preserves loaded PostgreSQL rows and offers a retry',
    (tester) async {
      final trendingApi = _FailingSecondPageTrendingCardDataApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
            cardDataApiClientProvider.overrideWithValue(trendingApi),
          ],
          child: const _HomeTestAppWithRoutes(),
        ),
      );

      final viewAll = find.byKey(const Key('home-trending-view-all'));
      await tester.ensureVisible(viewAll);
      await tester.tap(viewAll);
      await tester.pumpAndSettle();

      expect(find.text('Live Trending 0'), findsOneWidget);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -6000),
        10000,
      );
      await tester.pumpAndSettle();

      expect(trendingApi.requestedPages, [1, 2]);
      expect(find.text('Live Trending 0'), findsOneWidget);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -2000),
        10000,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('trending-today-retry-page')),
        findsOneWidget,
      );
      expect(find.byType(KandoFailureBlock), findsNothing);
    },
  );

  testWidgets('Search bottom tab navigates to Search page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._searchOverrides(),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.byKey(const Key('kando-tab-search')));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.byKey(const Key('kando-tab-scan')));
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });
}

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}

_localAuthOverrides() {
  final storage = InMemoryAuthStorage();
  return [
    authStorageProvider.overrideWithValue(storage),
    authRepositoryProvider.overrideWithValue(
      LocalPlaceholderAuthRepository(storage),
    ),
    portfolioAmountHiddenStorageProvider.overrideWithValue(
      InMemoryPortfolioAmountHiddenStorage(),
    ),
  ];
}

Widget _mockHomeApp([
  PortfolioManagementApi? managementApi,
  CurrencyRateApi currencyRateApi = const _TestCurrencyRateApi(),
  HomeRepository homeRepository = const MockHomeRepository(),
  SubscriptionController Function()? subscriptionController,
  PortfolioApiClient? performanceApi,
  AppAnalytics? analytics,
]) {
  final portfolioManagement = managementApi ?? _TestPortfolioManagementApi();
  return DefaultAssetBundle(
    bundle: homeFixtureAssetBundle,
    child: ProviderScope(
      overrides: [
        ..._localAuthOverrides(),
        homeRepositoryProvider.overrideWithValue(homeRepository),
        collectionRepositoryProvider.overrideWithValue(
          _HomeCollectionRepository(portfolioManagement),
        ),
        portfolioManagementApiProvider.overrideWithValue(portfolioManagement),
        portfolioApiClientProvider.overrideWithValue(
          performanceApi ?? _TestHomePerformanceApi(),
        ),
        currencyRateApiProvider.overrideWithValue(currencyRateApi),
        subscriptionControllerProvider.overrideWith(
          subscriptionController ?? _FreeHomeSubscriptionController.new,
        ),
        if (analytics != null) analyticsProvider.overrideWithValue(analytics),
      ],
      child: const _HomeTestApp(),
    ),
  );
}

class _ProHomeSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() => const SubscriptionState(isPro: true);
}

class _FreeHomeSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.free);
}

class _EntitlementRepairTracker {
  _EntitlementRepairTracker({required this.result});

  final bool result;
  var calls = 0;
}

class _RepairingHomeSubscriptionController extends SubscriptionController {
  _RepairingHomeSubscriptionController(this.tracker);

  final _EntitlementRepairTracker tracker;

  @override
  SubscriptionState build() => const SubscriptionState(isPro: true);

  @override
  Future<EntitlementReconciliationResult> reconcileServerEntitlement() async {
    tracker.calls++;
    return tracker.result
        ? EntitlementReconciliationResult.premiumSynchronized
        : EntitlementReconciliationResult.verificationUnavailable;
  }
}

class _TestHomePerformanceApi extends PortfolioApiClient {
  _TestHomePerformanceApi({
    this.itemCount = 75,
    this.topPerformerCount = 6,
    this.purchasePriceItemCount,
  }) : super(Dio());

  final int itemCount;
  final int topPerformerCount;
  final int? purchasePriceItemCount;

  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
  }) async {
    final pricedItemCount = purchasePriceItemCount ?? (itemCount == 0 ? 0 : 60);
    final previous = PerformancePointDto(
      date: '2026-08-11',
      marketValueUsd: 100,
      marketValueChangeUsd: null,
      marketChangeUsd: null,
      portfolioChangeUsd: null,
      paidMarketValueUsd: 90,
      totalPaidUsd: 80,
      profitLossUsd: 10,
      profitLossChangeUsd: null,
      returnPercent: 12.5,
      quantity: 2,
      quantityChange: null,
    );
    final current = PerformancePointDto(
      date: '2026-08-12',
      marketValueUsd: 12450.8,
      marketValueChangeUsd: 44,
      marketChangeUsd: 20,
      portfolioChangeUsd: 24,
      paidMarketValueUsd: 1100,
      totalPaidUsd: 800,
      profitLossUsd: 300,
      profitLossChangeUsd: 20,
      returnPercent: 37.5,
      quantity: 4,
      quantityChange: 2,
    );
    return PortfolioPerformanceDto(
      range: range,
      rangeStart: '2026-07-12',
      rangeEnd: '2026-08-12',
      historyAvailableFrom: '2026-07-12',
      partialHistory: false,
      itemCount: itemCount,
      marketPriceStatus: itemCount == 0
          ? MarketPriceStatus.missing
          : MarketPriceStatus.available,
      purchasePriceStatus: pricedItemCount == 0
          ? PurchasePriceStatus.missing
          : pricedItemCount == itemCount
          ? PurchasePriceStatus.complete
          : PurchasePriceStatus.partial,
      purchasePriceItemCount: pricedItemCount,
      topPerformerCount: topPerformerCount,
      topPerformerItemIds: topPerformerCount == 0
          ? const []
          : const ['item-pikachu', 'item-charizard', 'item-umbreon'],
      topPerformers: List.generate(
        topPerformerCount,
        (index) => PortfolioTopPerformerDto(
          itemId: const [
            'item-pikachu',
            'item-charizard',
            'item-umbreon',
            'item-4',
            'item-5',
            'item-6',
          ][index],
          cardRef: 'card-${index + 1}',
          name: 'Performer ${index + 1}',
          setName: 'Ranking Set',
          cardNumber: '${index + 1}',
          imageUrl: null,
          profitLossUsd: 50.0 - index,
          returnPercent: index == 5 ? null : 50.0 - index,
          marketValueUsd: 100.0 - index,
        ),
      ),
      current: current,
      series: range == PerformanceRange.oneDay
          ? [current]
          : [previous, current],
    );
  }
}

class _SlowOverviewHistoryApi extends _TestHomePerformanceApi {
  final _response = Completer<List<PortfolioFolderValuationDto>>();
  final folderIds = <String?>[];

  @override
  Future<List<PortfolioFolderValuationDto>> getValuationHistory(
    AuthSession session, {
    int days = 90,
    String? folderId,
    bool localPremiumVerified = false,
  }) {
    folderIds.add(folderId);
    return _response.future;
  }

  void complete() {
    _response.complete(const [
      PortfolioFolderValuationDto(
        folderId: 'main',
        itemCount: 1,
        marketPriceStatus: MarketPriceStatus.available,
        currentValueUsd: 125,
        series: [
          PortfolioValuationPointDto(date: '2025-08-20', valueUsd: 100),
          PortfolioValuationPointDto(date: '2026-08-20', valueUsd: 125),
        ],
        mostValuable: [],
      ),
    ]);
  }
}

class _EntitlementSyncPerformanceApi extends _TestHomePerformanceApi {
  _EntitlementSyncPerformanceApi({required this.succeedAfterRepair});

  final bool succeedAfterRepair;
  var calls = 0;

  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
  }) {
    calls++;
    if (calls == 1 || !succeedAfterRepair) {
      throw const PortfolioApiException(
        'Premium access is still syncing.',
        code: 'ENTITLEMENT_SYNC_REQUIRED',
        statusCode: 409,
      );
    }
    return super.getPortfolioPerformance(
      session,
      range: range,
      folderId: folderId,
      localPremiumVerified: localPremiumVerified,
    );
  }
}

class _FailingRangePerformanceApi extends _TestHomePerformanceApi {
  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
  }) {
    if (range == PerformanceRange.sevenDays) {
      throw const PortfolioApiException(
        'Range request failed.',
        code: 'PERFORMANCE_UNAVAILABLE',
        statusCode: 503,
      );
    }
    return super.getPortfolioPerformance(
      session,
      range: range,
      folderId: folderId,
      localPremiumVerified: localPremiumVerified,
    );
  }
}

class _SlowRangePerformanceApi extends _TestHomePerformanceApi {
  final _rangeGate = Completer<void>();

  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
  }) async {
    if (range == PerformanceRange.sevenDays) {
      await _rangeGate.future;
    }
    return super.getPortfolioPerformance(
      session,
      range: range,
      folderId: folderId,
      localPremiumVerified: localPremiumVerified,
    );
  }

  void completeRange() => _rangeGate.complete();
}

class _EntitlementSyncRangePerformanceApi extends _TestHomePerformanceApi {
  var rangeCalls = 0;

  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
  }) {
    if (range == PerformanceRange.sevenDays) {
      rangeCalls++;
      throw const PortfolioApiException(
        'Premium access is still syncing.',
        code: 'ENTITLEMENT_SYNC_REQUIRED',
        statusCode: 409,
      );
    }
    return super.getPortfolioPerformance(
      session,
      range: range,
      folderId: folderId,
      localPremiumVerified: localPremiumVerified,
    );
  }
}

Widget _mockHomeRouteApp({
  HomeRepository homeRepository = const MockHomeRepository(),
  SubscriptionController Function()? subscriptionController,
  PortfolioApiClient? performanceApi,
}) {
  final portfolioManagement = _TestPortfolioManagementApi();
  return ProviderScope(
    overrides: [
      ..._localAuthOverrides(),
      homeRepositoryProvider.overrideWithValue(homeRepository),
      collectionRepositoryProvider.overrideWithValue(
        _HomeCollectionRepository(portfolioManagement),
      ),
      portfolioManagementApiProvider.overrideWithValue(portfolioManagement),
      if (performanceApi != null)
        portfolioApiClientProvider.overrideWithValue(performanceApi),
      currencyRateApiProvider.overrideWithValue(const _TestCurrencyRateApi()),
      if (subscriptionController != null)
        subscriptionControllerProvider.overrideWith(subscriptionController),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/scan',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Scan route target'))),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const Scaffold(
              body: Center(child: Text('Search route target')),
            ),
          ),
          GoRoute(
            path: '/cards/:cardId',
            builder: (context, state) => Scaffold(
              body: Text(
                '${state.pathParameters['cardId']}|'
                '${state.uri.queryParameters['item_id']}|'
                '${state.uri.queryParameters['entry']}|'
                '${state.uri.queryParameters['collection']}',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MostValuableRouteHomeRepository implements HomeRepository {
  const _MostValuableRouteHomeRepository();

  @override
  HomeDashboard loadDashboard() {
    const source = mockHomeDashboard;
    final cards = source.mostValuableCardsByFolderId['main']!;
    final first = cards.first;
    final linked = HomeCardHighlight(
      itemId: 'item-pikachu',
      cardRef: 'card-1',
      title: first.title,
      subtitle: first.subtitle,
      priceUsd: first.priceUsd,
      previousPriceUsd: first.previousPriceUsd,
      increasePercent: first.increasePercent,
      imageAssetPath: first.imageAssetPath,
      imageUrl: first.imageUrl,
    );
    return HomeDashboard(
      folders: source.folders,
      portfoliosByFolderId: source.portfoliosByFolderId,
      mostValuableByFolderId: source.mostValuableByFolderId,
      mostValuableCardsByFolderId: {
        ...source.mostValuableCardsByFolderId,
        'main': [linked, ...cards.skip(1)],
      },
      trending: source.trending,
      currencyCode: source.currencyCode,
      amountHidden: source.amountHidden,
      trendingUnavailable: source.trendingUnavailable,
    );
  }
}

class _HomeCollectionRepository extends MockCollectionRepository {
  const _HomeCollectionRepository(this._managementApi);

  final PortfolioManagementApi _managementApi;

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    await _managementApi.updatePreferences(
      session,
      currency: currency,
      amountHidden: amountHidden,
      lastSelectedFolderId: lastSelectedFolderId,
    );
  }
}

class _TestCurrencyRateApi implements CurrencyRateApi {
  const _TestCurrencyRateApi({this.fails = false});

  final bool fails;

  @override
  Future<double> loadUsdRate(String targetCurrency) async {
    if (fails) throw StateError('rate unavailable');
    return 0.91;
  }
}

class _TestPortfolioManagementApi implements PortfolioManagementApi {
  final List<String> currencyCodes = [];
  final List<bool> amountHiddenValues = [];
  final List<String> selectedFolderIds = [];

  @override
  Future<UserPreferenceDto> getPreferences(AuthSession session) async {
    return const UserPreferenceDto(
      currency: 'USD',
      amountHidden: false,
      lastSelectedFolderId: null,
    );
  }

  @override
  Future<UserPreferenceDto> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    if (currency != null) currencyCodes.add(currency);
    if (amountHidden != null) amountHiddenValues.add(amountHidden);
    if (lastSelectedFolderId != null) {
      selectedFolderIds.add(lastSelectedFolderId);
    }
    return UserPreferenceDto(
      currency: currency ?? 'USD',
      amountHidden: amountHidden ?? false,
      lastSelectedFolderId: lastSelectedFolderId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedPortfolioManagementApi extends _TestPortfolioManagementApi {
  final preferenceWrite = Completer<void>();

  @override
  Future<UserPreferenceDto> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    final result = await super.updatePreferences(
      session,
      currency: currency,
      amountHidden: amountHidden,
      lastSelectedFolderId: lastSelectedFolderId,
    );
    await preferenceWrite.future;
    return result;
  }
}

class _CountingHomeRepository implements HomeRepository {
  var calls = 0;

  @override
  HomeDashboard loadDashboard() {
    calls += 1;
    return const MockHomeRepository().loadDashboard();
  }
}

class _MissingMarketPriceHomeRepository implements HomeRepository {
  const _MissingMarketPriceHomeRepository();

  @override
  HomeDashboard loadDashboard() {
    return const HomeDashboard(
      folders: [HomeFolder(id: 'main', name: 'Main', isDefault: true)],
      portfoliosByFolderId: {
        'main': PortfolioSummary(
          folderId: 'main',
          itemCount: 1,
          marketPriceStatus: MarketPriceStatus.missing,
          totalValueUsd: 0,
          previous30dValueUsd: 0,
          chartValuesByRange: {
            HomeChartRange.oneMonth: [0],
          },
        ),
      },
      mostValuableByFolderId: {'main': null},
      mostValuableCardsByFolderId: {'main': []},
      trending: [],
    );
  }
}

class _PendingStartupAuthRepository extends LocalPlaceholderAuthRepository {
  _PendingStartupAuthRepository(super.storage);

  final _startup = Completer<AuthSession?>();

  @override
  Future<AuthSession?> currentSessionFromStorage() => _startup.future;
}

void _refreshHome(WidgetTester tester) {
  final context = tester.element(find.byType(HomePage));
  ProviderScope.containerOf(
    context,
  ).read(homeControllerProvider.notifier).refresh();
}

Future<void> _waitForHomeAuth(WidgetTester tester) async {
  final context = tester.element(find.byType(HomePage));
  final container = ProviderScope.containerOf(context);
  await container.read(authControllerProvider.notifier).startupComplete;
  await tester.pumpAndSettle();
}

class _HomeTestApp extends StatelessWidget {
  const _HomeTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomePage());
  }
}

class _HomeTestAppWithRoutes extends StatelessWidget {
  const _HomeTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => const CollectionPage(),
          ),
          GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/trending',
            builder: (context, state) => const TrendingTodayPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
    );
  }
}

class _TrendingCardDataApi
    implements CardDataApi, PaginatedTrendingCardDataApi {
  final requestedPages = <int>[];

  @override
  Future<List<CardDataCardDto>> trendingCards() async => const [
    CardDataCardDto(
      cardRef: 'live-trending',
      name: 'Live Trending',
      setName: 'Live Set',
      setCode: 'LIVE',
      cardNumber: '1',
      finish: 'Normal',
      language: 'English',
      objectType: 'tcg',
      imageUrl: null,
      rarity: 'Rare',
      priceUsd: 12,
      previous30dPriceUsd: 1,
      priceChange1dPercent: 5,
    ),
    CardDataCardDto(
      cardRef: 'falling-trending',
      name: 'Falling Trending',
      setName: 'Live Set',
      setCode: 'LIVE',
      cardNumber: '2',
      finish: 'Normal',
      language: 'English',
      objectType: 'tcg',
      imageUrl: null,
      rarity: 'Rare',
      priceUsd: 10,
      previous30dPriceUsd: 20,
      priceChange1dPercent: -5,
    ),
  ];

  @override
  Future<List<CardDataCardDto>> trendingCardPage({required int page}) async {
    requestedPages.add(page);
    return trendingCards();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyTrendingCardDataApi extends _TrendingCardDataApi {
  @override
  Future<List<CardDataCardDto>> trendingCards() async => const [];
}

class _FailingTrendingCardDataApi extends _TrendingCardDataApi {
  @override
  Future<List<CardDataCardDto>> trendingCards() {
    throw StateError('PostgreSQL trending unavailable');
  }
}

class _FailingSecondPageTrendingCardDataApi extends _TrendingCardDataApi {
  @override
  Future<List<CardDataCardDto>> trendingCardPage({required int page}) async {
    requestedPages.add(page);
    if (page == 2) {
      throw StateError('PostgreSQL trending page unavailable');
    }
    return List.generate(
      kandoPageSize,
      (index) => CardDataCardDto(
        cardRef: 'live-trending-$index',
        name: 'Live Trending $index',
        setName: 'Live Set',
        setCode: 'LIVE',
        cardNumber: '$index',
        finish: 'Normal',
        language: 'English',
        objectType: 'tcg',
        imageUrl: null,
        rarity: 'Rare',
        priceUsd: 12,
        previous30dPriceUsd: 1,
        priceChange1dPercent: 5,
      ),
    );
  }
}

class _SuccessfulThenFailingHomeRepository implements HomeRepository {
  var calls = 0;

  @override
  HomeDashboard loadDashboard() {
    calls += 1;
    if (calls == 2) {
      throw StateError('mock home unavailable');
    }
    return const MockHomeRepository().loadDashboard();
  }
}

class _TrendingUnavailableHomeRepository implements HomeRepository {
  const _TrendingUnavailableHomeRepository();

  @override
  HomeDashboard loadDashboard() {
    return mockHomeDashboard.copyWith(
      trending: const [],
      trendingUnavailable: true,
    );
  }
}
