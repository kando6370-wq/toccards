import 'dart:async';
import 'dart:ui' as ui;

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
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/features/home/trending_today_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_collection_repository.dart';
import '../support/mock_home_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  test(
    'Figma Home card photo decodes at its design source aspect ratio',
    () async {
      final data = await rootBundle.load('assets/home/mega_lucario_ex.png');
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
    final stream = const AssetImage(
      'assets/home/mega_lucario_ex.png',
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

  testWidgets('Figma normal Home renders at the approved 390x844 baseline', (
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
        ],
        child: MaterialApp(
          theme: buildKandoTheme(),
          home: const RepaintBoundary(
            key: Key('home-figma-golden'),
            child: HomePage(),
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

  testWidgets('Figma partial Home failure renders at the 390x844 baseline', (
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
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: buildKandoTheme(),
          home: const RepaintBoundary(
            key: Key('home-failure-figma-golden'),
            child: HomePage(),
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
    expect(find.text('PORTFOLIO'), findsOneWidget);
    expect(find.byKey(const Key('home-pull-to-refresh')), findsOneWidget);
    expect(find.text('PORTDOLIO'), findsNothing);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text(r'$12,450.80'), findsOneWidget);
    expect(find.text('1D'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('15D'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('3M'), findsOneWidget);
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
  });

  testWidgets(
    'Portfolio chart selects the nearest date anywhere in the plot because users inspect historical values',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());

      final chart = find.byKey(const Key('home-portfolio-chart'));
      expect(chart, findsOneWidget);

      final chartRect = tester.getRect(chart);
      await tester.tapAt(Offset(chartRect.left + 1, chartRect.center.dy));
      await tester.pump();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        contains('Date: Feb 12, 2025'),
      );

      await tester.tapAt(Offset(chartRect.right - 1, chartRect.center.dy));
      await tester.pump();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        contains('Date: Feb 21, 2025'),
      );
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
    final chartRect = tester.getRect(chart);

    await tester.tapAt(Offset(chartRect.left + 1, chartRect.center.dy));
    await tester.pump();
    expect(
      tester.widget<Semantics>(chart).properties.value,
      r'Date: Feb 12, 2025, Price: $11,800.00',
    );

    await tester.tapAt(
      Offset(chartRect.left + chartRect.width * 4 / 9, chartRect.center.dy),
    );
    await tester.pump();
    expect(
      tester.widget<Semantics>(chart).properties.value,
      r'Date: Feb 16, 2025, Price: $12,050.00',
    );

    await tester.dragFrom(
      Offset(chartRect.left + 1, chartRect.center.dy),
      Offset(chartRect.width - 2, 0),
    );
    await tester.pump();
    expect(
      tester.widget<Semantics>(chart).properties.value,
      r'Date: Feb 21, 2025, Price: $12,450.80',
    );
  });

  testWidgets(
    'Overview uses the Figma SVG icon and filled 16px inverse label',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());

      final overview = tester.widget<Text>(find.text('Overview'));
      expect(overview.style?.fontSize, 16);
      expect(overview.style?.color, const Color(0xFF303126));

      final icon = tester.widget<SvgPicture>(
        find.byKey(const Key('home-overview-icon')),
      );
      expect(icon.width, 14);
      expect(icon.height, 14);
      expect(
        (icon.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/overview.svg',
      );
    },
  );

  testWidgets('Home View all links use 16px text', (tester) async {
    await tester.pumpWidget(_mockHomeApp());

    for (final text in tester.widgetList<Text>(find.text('View all'))) {
      expect(text.style?.fontSize, 16);
      expect(text.style?.height, 20 / 16);
    }
  });

  testWidgets('Most Valuable change badge matches the Figma glass style', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    final firstCard = find.byKey(const Key('home-most-valuable-card-main-0'));
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
    final badgePosition = tester.widget<Positioned>(
      find.ancestor(of: find.text('+3.20%'), matching: find.byType(Positioned)),
    );

    expect(backdrop, findsOneWidget);
    expect(badgeContainer, findsOneWidget);
    expect(badgePosition.top, 0);
    expect(badgePosition.right, -2);
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
    'folder picker closes and updates Home before preference persistence because switching must stay responsive',
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
      expect(homeRepository.calls, 1);

      preferences.preferenceWrite.complete();
      await tester.pumpAndSettle();
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

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
      expect(find.text(r'$780.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-hide-amount')));
      await tester.pump();

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
      expect(find.text(hiddenMoneyText), findsOneWidget);
      expect(find.text(r'$12,450.80'), findsNothing);
      expect(find.text(r'$780.00'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.text(r'$780.00'), findsOneWidget);
      expect(preferences.amountHiddenValues, [true]);
    },
  );

  testWidgets(
    'Most Valuable change badges stay tied to the displayed card data after a portfolio switch',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());
      await _waitForHomeAuth(tester);

      expect(find.text('+3.20%'), findsOneWidget);
      expect(find.text('0.001%'), findsNothing);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sealed').last);
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
      expect(find.text('Live Trending'), findsOneWidget);
      expect(trendingApi.requestedPages, [1]);
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
  ];
}

Widget _mockHomeApp([
  PortfolioManagementApi? managementApi,
  CurrencyRateApi currencyRateApi = const _TestCurrencyRateApi(),
  HomeRepository homeRepository = const MockHomeRepository(),
]) {
  final portfolioManagement = managementApi ?? _TestPortfolioManagementApi();
  return ProviderScope(
    overrides: [
      ..._localAuthOverrides(),
      homeRepositoryProvider.overrideWithValue(homeRepository),
      collectionRepositoryProvider.overrideWithValue(
        _HomeCollectionRepository(portfolioManagement),
      ),
      portfolioManagementApiProvider.overrideWithValue(portfolioManagement),
      currencyRateApiProvider.overrideWithValue(currencyRateApi),
    ],
    child: const _HomeTestApp(),
  );
}

Widget _mockHomeRouteApp() {
  final portfolioManagement = _TestPortfolioManagementApi();
  return ProviderScope(
    overrides: [
      ..._localAuthOverrides(),
      homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
      collectionRepositoryProvider.overrideWithValue(
        _HomeCollectionRepository(portfolioManagement),
      ),
      portfolioManagementApiProvider.overrideWithValue(portfolioManagement),
      currencyRateApiProvider.overrideWithValue(const _TestCurrencyRateApi()),
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
        ],
      ),
    ),
  );
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
      priceChange1dPercent: 5,
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
