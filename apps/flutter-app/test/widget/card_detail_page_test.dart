import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_actions.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_models.dart';
import 'package:kando_app/features/card_detail/card_detail_page.dart';
import 'package:kando_app/features/card_detail/card_detail_repository.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/pending_collection.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_card_detail_repository.dart';

void main() {
  test('Performance tooltip separates Figma label and value styles', () {
    final span = buildCardDetailChartTooltipRow(r'Market Value: $790.00');
    final children = span.children!.cast<TextSpan>();

    expect(children, hasLength(2));
    expect(children[0].text, 'Market Value:');
    expect(children[0].style?.color, const Color(0xFF999578));
    expect(children[0].style?.fontFamily, 'Geist');
    expect(children[0].style?.fontSize, 12);
    expect(children[0].style?.height, 18 / 12);
    expect(children[1].text, r' $790.00');
    expect(children[1].style?.color, KandoColors.accent);
    expect(children[1].style?.fontSize, 10);
    expect(children[1].style?.height, 14 / 10);
  });

  testWidgets(
    'product 180865 shows Normal and Foil tabs and switching refreshes material prices',
    (tester) async {
      final repository = _FinishTabCardDetailRepository();
      await tester.pumpWidget(
        _CardDetailTestApp(cardId: '180865', repository: repository),
      );
      await tester.pumpAndSettle();

      final normalTab = find.byKey(const Key('card-detail-finish-Normal'));
      final foilTab = find.byKey(const Key('card-detail-finish-Foil'));
      await tester.scrollUntilVisible(normalTab, 400);
      expect(normalTab, findsOneWidget);
      expect(foilTab, findsOneWidget);
      expect(
        find.byKey(const Key('card-detail-finish-icon-Normal')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-detail-finish-icon-Foil')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const Key('card-detail-price-heading')))
            .dy,
        lessThan(tester.getTopLeft(normalTab).dy),
        reason: 'Figma defines Finish as a control within the Price section.',
      );

      await tester.ensureVisible(foilTab);
      await tester.pumpAndSettle();
      await tester.tap(foilTab);
      await tester.pumpAndSettle();

      expect(repository.requestedFinishes.last, 'Foil');
      expect(find.text(r'$20.00'), findsWidgets);
    },
  );

  testWidgets(
    'more than two Finish tabs generate a center pattern per finish',
    (tester) async {
      final repository = _FinishTabCardDetailRepository(
        finishes: const ['Normal', 'Foil', 'Holofoil'],
      );
      await tester.pumpWidget(
        _CardDetailTestApp(cardId: '180865', repository: repository),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-finish-icon-Holofoil')),
        findsOneWidget,
        reason: 'Every finish needs a stable generated center pattern.',
      );
    },
  );

  testWidgets(
    'overflowing Finish tabs scroll and remove their end cue at the last item',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FinishTabCardDetailRepository(
        finishes: const [
          'Normal',
          '1st Edition',
          '1st Edition Holofoil',
          'Reverse Holofoil',
        ],
      );
      await tester.pumpWidget(
        _CardDetailTestApp(cardId: '600820', repository: repository),
      );
      await tester.pumpAndSettle();

      final scroll = find.byKey(const Key('card-detail-finish-tabs-scroll'));
      await tester.scrollUntilVisible(
        scroll,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final scrollView = tester.widget<SingleChildScrollView>(scroll);
      expect(scrollView.controller!.position.maxScrollExtent, greaterThan(0));
      expect(
        find.byKey(const Key('card-detail-finish-tabs-end-fade')),
        findsOneWidget,
        reason:
            'Overflow needs a visible cue that more finishes are available.',
      );
      final longLabel = tester.widget<Text>(find.text('1st Edition Holofoil'));
      expect(longLabel.maxLines, 1);
      expect(longLabel.softWrap, isFalse);

      await tester.drag(scroll, const Offset(-1000, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-finish-tabs-end-fade')),
        findsNothing,
        reason:
            'The overflow cue must disappear once the last finish is visible.',
      );
    },
  );

  testWidgets('Wishlist CardDetail uses the global Finish tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _CardDetailTestApp(cardId: 'one-piece-luffy'),
    );
    await tester.pumpAndSettle();

    final removeWishlist = find.byKey(const Key('card-detail-remove-wishlist'));
    await tester.scrollUntilVisible(removeWishlist, 400);
    expect(removeWishlist, findsOneWidget);
    expect(find.byKey(const Key('card-detail-finish-Normal')), findsOneWidget);
  });

  testWidgets(
    'Price always shows its Finish tab when only one material exists',
    (tester) async {
      await tester.pumpWidget(const _CardDetailTestApp(cardId: 'squirtle'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-finish-Holofoil')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'mobile CardDetail keeps the Figma hero size because the primary card must stay inspectable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _CardDetailTestApp(cardId: 'squirtle'));
      await tester.pumpAndSettle();

      final heroSize = tester.getSize(
        find.byKey(const Key('card-detail-hero')),
      );
      expect(heroSize.width, 350);
      expect(heroSize.height, closeTo(454, 0.01));
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.byKey(const Key('card-detail-price-chart')),
        400,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide CardDetail aligns hero, primary action, and owned tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    final heroWidth = tester
        .getSize(find.byKey(const Key('card-detail-hero')))
        .width;
    final actionWidth = tester
        .getSize(find.byKey(const Key('card-detail-view-sold-listings')))
        .width;
    final tabsWidth = tester
        .getSize(find.byKey(const Key('card-detail-owned-tabs')))
        .width;

    expect(heroWidth, 390);
    expect(actionWidth, heroWidth);
    expect(tabsWidth, heroWidth);
  });

  testWidgets(
    'owned CardDetail tabs match Figma typography without truncating labels',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
      await tester.pumpAndSettle();

      final tabs = find.byKey(const Key('card-detail-owned-tabs'));
      await tester.scrollUntilVisible(tabs, 400);
      await tester.pumpAndSettle();

      final tabBar = tester.widget<TabBar>(
        find.descendant(of: tabs, matching: find.byType(TabBar)),
      );
      expect(tabBar.labelPadding, EdgeInsets.zero);

      TextStyle labelStyle(String label) => DefaultTextStyle.of(
        tester.element(find.descendant(of: tabs, matching: find.text(label))),
      ).style;

      for (final label in const ['Collection Item', 'Performance', 'Price']) {
        final labelFinder = find.descendant(
          of: tabs,
          matching: find.text(label),
        );
        expect(labelFinder, findsOneWidget);
        final style = labelStyle(label);
        expect(style.fontSize, 13);
        expect(style.height, closeTo(16 / 13, 0.001));
        expect(style.fontWeight, FontWeight.w400);
        expect(style.letterSpacing, 0);
        expect(
          tester.renderObject<RenderParagraph>(labelFinder).didExceedMaxLines,
          isFalse,
        );
      }

      expect(labelStyle('Collection Item').color, KandoColors.accent);
      expect(labelStyle('Performance').color, const Color(0xFF92927D));
      expect(labelStyle('Price').color, const Color(0xFF92927D));

      await tester.tap(find.descendant(of: tabs, matching: find.text('Price')));
      await tester.pumpAndSettle();

      expect(labelStyle('Collection Item').color, const Color(0xFF92927D));
      expect(labelStyle('Performance').color, const Color(0xFF92927D));
      expect(labelStyle('Price').color, KandoColors.accent);
    },
  );

  testWidgets('uncollected CardDetail renders identity and price overview', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'squirtle'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('card-detail-pull-to-refresh')),
      findsOneWidget,
    );
    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text('Pokemon'), findsWidgets);
    expect(find.text('Mega Evolution Promos'), findsWidgets);
    expect(find.text('Promo #039'), findsWidgets);
    expect(
      find.byKey(const Key('card-detail-add-to-portfolio-squirtle')),
      findsOneWidget,
    );
    expect(find.text('Add to Portfolio'), findsNothing);
    expect(find.text('Collect'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-price-chart')),
      400,
    );

    expect(find.text('Price'), findsOneWidget);
    expect(find.byKey(const Key('card-detail-price-chart')), findsOneWidget);
    expect(find.text('1D'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('15D'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('3M'), findsOneWidget);
    expect(find.text('1Y'), findsOneWidget);
    final oneYearProBadge = find.byKey(
      const Key('card-detail-price-range-1y-pro-badge'),
    );
    expect(oneYearProBadge, findsOneWidget);
    expect(tester.getSize(oneYearProBadge), const Size(35, 20));
    expect(
      tester.getRect(oneYearProBadge).left -
          tester.getRect(find.text('1Y')).right,
      4,
    );
    expect(
      find.ancestor(
        of: oneYearProBadge,
        matching: find.byKey(const Key('card-detail-price-range-1y')),
      ),
      findsOneWidget,
    );
    expect(find.text('6M'), findsNothing);
    expect(find.text('12M'), findsNothing);
    expect(find.text('MAX'), findsNothing);
    expect(find.text('30D'), findsNothing);
    expect(find.text('30 days ago'), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Ungraded'), findsOneWidget);
    expect(find.text('PSA'), findsOneWidget);
    expect(find.text('ACE'), findsNothing);
    expect(find.text('BGS'), findsNothing);
    expect(find.text('Near Mint (NM)'), findsOneWidget);
    expect(find.text(r'$32.13'), findsWidgets);
    expect(find.text('+2.19%'), findsOneWidget);
    expect(find.text('Collection Item'), findsNothing);
    expect(
      find.byKey(const Key('card-detail-remove-from-portfolio')),
      findsNothing,
    );
  });

  testWidgets('free owners can tap the Price 1Y PRO badge to open Premium', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailPriceRangeRouteApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-price-chart')),
      400,
    );
    final oneYearProBadge = find.byKey(
      const Key('card-detail-price-range-1y-pro-badge'),
    );
    await tester.ensureVisible(oneYearProBadge);
    await tester.pumpAndSettle();

    await tester.tap(oneYearProBadge);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('card-detail-price-subscription-target')),
      findsOneWidget,
    );
  });

  testWidgets('Pro owners see Price 1Y without the PRO badge', (tester) async {
    await tester.pumpWidget(
      const _CardDetailTestApp(
        cardId: 'squirtle',
        collectionItemId: null,
        subscriptionController: _ProCardSubscriptionController.new,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-price-chart')),
      400,
    );

    expect(find.text('1Y'), findsOneWidget);
    expect(
      find.byKey(const Key('card-detail-price-range-1y-pro-badge')),
      findsNothing,
    );
  });

  testWidgets(
    'Card Detail chart ranges keep a compact accent indicator because every range switch needs visible confirmation',
    (tester) async {
      await tester.pumpWidget(
        const _CardDetailTestApp(
          cardId: 'squirtle',
          collectionItemId: null,
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('card-detail-price-chart')),
        400,
      );

      final priceRange = find.byKey(const Key('card-detail-price-range-7d'));
      await tester.ensureVisible(priceRange);
      await tester.pumpAndSettle();
      await tester.tap(priceRange);
      await tester.pumpAndSettle();

      final priceIndicator = find.descendant(
        of: priceRange,
        matching: find.byType(Container),
      );
      expect(priceIndicator, findsOneWidget);
      expect(tester.getSize(priceIndicator), const Size(40, 24));
      final priceDecoration =
          tester.widget<Container>(priceIndicator).decoration! as BoxDecoration;
      expect(priceDecoration.shape, BoxShape.rectangle);
      expect(priceDecoration.borderRadius, BorderRadius.circular(4));
      expect(priceDecoration.gradient, isNotNull);

      await tester.pumpWidget(
        const _CardDetailTestApp(
          cardId: 'charizard-ex',
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('card-detail-performance-range-7D')),
      );
      await tester.pumpAndSettle();

      final performanceIndicator = find.ancestor(
        of: find.byKey(const Key('card-detail-performance-range-7D')),
        matching: find.byType(Ink),
      );
      expect(performanceIndicator, findsOneWidget);
      expect(tester.getSize(performanceIndicator).height, 24);
      final performanceDecoration =
          tester.widget<Ink>(performanceIndicator).decoration! as BoxDecoration;
      expect(performanceDecoration.borderRadius, BorderRadius.circular(4));
      expect(performanceDecoration.gradient, isNotNull);

      final previousIndicator = find.ancestor(
        of: find.byKey(const Key('card-detail-performance-range-1M')),
        matching: find.byType(Ink),
      );
      expect(previousIndicator, findsOneWidget);
      final previousDecoration =
          tester.widget<Ink>(previousIndicator).decoration! as BoxDecoration;
      expect(previousDecoration.gradient, isNull);
    },
  );

  testWidgets('Price Tab missing data renders fallback copy', (tester) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'mystery-promo'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-price-chart')),
      400,
    );

    expect(find.byKey(const Key('card-detail-price-chart')), findsOneWidget);
    expect(find.text('No price data available.'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('card-detail-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
    expect(find.text('-/-'), findsWidgets);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('No sold listings available.'), findsOneWidget);
    expect(find.text(noContentAvailableText), findsNothing);
  });

  testWidgets(
    'Price chart reveals point details only after chart interaction',
    (tester) async {
      await tester.pumpWidget(const _CardDetailTestApp(cardId: 'squirtle'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('card-detail-price-chart')),
        400,
      );

      final chart = find.byKey(
        const Key('card-detail-price-chart-interactive'),
      );
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();

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
      expect(
        tester.widget<Semantics>(chart).properties.value,
        r'Date: 30 days ago, Price: $30.67',
      );

      await touch.moveTo(Offset(chartRect.right - 1, chartRect.center.dy));
      await tester.pump();
      expect(
        tester.widget<Semantics>(chart).properties.value,
        r'Date: Today, Price: $32.13',
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
    'optional endpoint failures stay inside Price Market and Shop because base card navigation must remain usable',
    (tester) async {
      await tester.pumpWidget(
        const _CardDetailTestApp(
          cardId: 'squirtle',
          repository: _FailingSectionCardDetailRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Squirtle'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('card-detail-price-chart-failure')),
        400,
      );

      expect(
        find.byKey(const Key('card-detail-price-chart-failure')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-detail-market-prices-failure')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('card-detail-shop-failure')), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNWidgets(3));
    },
  );

  testWidgets(
    'Shop opens the backend listing URL because marketplace routes are server-owned',
    (tester) async {
      final actions = _RecordingCardDetailActions();
      await tester.pumpWidget(
        _CardDetailTestApp(cardId: 'squirtle', actions: actions),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Shop'), 400);
      await tester.ensureVisible(find.text('Squirtle Promo Holofoil'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const Key(
            'card-detail-shop-image-2026-07-02-Squirtle Promo Holofoil',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Squirtle Promo Holofoil'));
      await tester.pumpAndSettle();

      expect(actions.marketplaceUrl, 'https://market.example/squirtle-promo');
    },
  );

  testWidgets(
    'sold listings action uses the real card identity because the external query must match the detail',
    (tester) async {
      final actions = _RecordingCardDetailActions();
      await tester.pumpWidget(
        _CardDetailTestApp(cardId: 'squirtle', actions: actions),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('card-detail-view-sold-listings')));
      await tester.pumpAndSettle();

      expect(actions.soldListingsName, 'Squirtle');
      expect(actions.soldListingsSetName, 'Mega Evolution Promos');
    },
  );

  testWidgets(
    'wishlisted CardDetail asks before removal because Wishlist deletion is destructive',
    (tester) async {
      await tester.pumpWidget(
        const _CardDetailTestApp(cardId: 'one-piece-luffy'),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('card-detail-remove-wishlist')),
        400,
      );
      expect(
        find.byKey(const Key('card-detail-remove-wishlist-icon')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.bookmark_remove_outlined), findsNothing);

      await tester.tap(find.byKey(const Key('card-detail-remove-wishlist')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byKey(const Key('card-detail-remove-confirmation-sheet')),
        findsOneWidget,
      );
      expect(
        find.text('This card will be removed from your wishlist'),
        findsOneWidget,
      );
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('REMOVE'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('card-detail-remove-confirmation-cancel')),
      );
      await tester.pumpAndSettle();

      var container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );
      expect(
        container
            .read(cardDetailControllerProvider('one-piece-luffy'))
            .detail
            .isWishlisted,
        isTrue,
      );
      expect(
        find.byKey(const Key('card-detail-remove-confirmation-sheet')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('card-detail-remove-wishlist')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('card-detail-remove-confirmation-submit')),
      );
      await tester.pumpAndSettle();

      container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );
      expect(
        container
            .read(cardDetailControllerProvider('one-piece-luffy'))
            .detail
            .isWishlisted,
        isFalse,
      );
    },
  );

  testWidgets(
    'failed removal shows the shared failure toast above the confirmation sheet',
    (tester) async {
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'one-piece-luffy',
          repository: _FailingRemovalCardDetailRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('card-detail-remove-wishlist')),
        400,
      );
      await tester.tap(find.byKey(const Key('card-detail-remove-wishlist')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('card-detail-remove-confirmation-submit')),
      );
      await tester.pump();

      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.text(genericFailureToastText), findsOneWidget);
      expect(
        find.byKey(const Key('card-detail-remove-confirmation-sheet')),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );
      expect(
        container
            .read(cardDetailControllerProvider('one-piece-luffy'))
            .detail
            .isWishlisted,
        isTrue,
      );
      await tester.pump(kandoTopToastDuration);
      await tester.pump();
    },
  );

  testWidgets(
    'generic CardDetail collection action opens the item editor without changing saved Qty',
    (tester) async {
      await tester.pumpWidget(
        const _CardDetailTestApp(cardId: 'one-piece-luffy'),
      );
      await tester.pumpAndSettle();

      final collect = find.byKey(
        const Key('card-detail-add-to-portfolio-one-piece-luffy'),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );

      await tester.tap(collect);
      await tester.pumpAndSettle();

      expect(container.read(pendingCollectionProvider), isEmpty);
      expect(
        container
            .read(cardDetailControllerProvider('one-piece-luffy'))
            .detail
            .quantity,
        0,
      );
      expect(
        find.byKey(const Key('card-detail-add-item-sheet')),
        findsOneWidget,
      );
      expect(find.byType(QuickCollectionReviewPage), findsNothing);
    },
  );

  testWidgets(
    'Add this card shows duplicate failures in a top toast because the fixed action must not require scrolling to the form error',
    (tester) async {
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'one-piece-luffy',
          repository: const _DuplicateCreateCardDetailRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('card-detail-add-to-portfolio-one-piece-luffy')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-item-submit')));
      await tester.pump();

      final toast = find.byKey(const Key('kando-top-toast'));
      expect(toast, findsOneWidget);
      expect(
        find.descendant(
          of: toast,
          matching: find.text(duplicateCollectionItemMessage),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-detail-add-item-sheet')),
        findsOneWidget,
      );

      await tester.pump(kandoTopToastDuration);
      await tester.pump();
    },
  );

  testWidgets('owned CardDetail defaults to Collection Item content', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Collected'), findsNothing);
    expect(find.text('Collect'), findsNothing);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.byIcon(Icons.ios_share_outlined), findsNothing);
    expect(find.text('In Your Portfolio'), findsNothing);
    expect(
      find.byKey(const Key('card-detail-share-charizard-ex')),
      findsOneWidget,
    );
    final shareIcon = tester.widget<SvgPicture>(
      find.byKey(const Key('card-detail-share-icon')),
    );
    expect(
      shareIcon.bytesLoader,
      isA<SvgAssetLoader>().having(
        (loader) => loader.assetName,
        'assetName',
        'assets/collection/share.svg',
      ),
    );

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);

    expect(find.text('Collection Item'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text('GRADER'), findsOneWidget);
    expect(find.text('PSA'), findsOneWidget);
    expect(find.text('GRADE'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('PURCHASE PRICE'), findsOneWidget);
    expect(find.text(r'$650.00'), findsWidgets);
    final ownershipCard = find.byKey(
      const Key('card-detail-collection-item-item-charizard'),
    );
    expect(
      find.descendant(
        of: ownershipCard,
        matching: find.text('CURRENT MARKET PRICE'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: ownershipCard, matching: find.text(r'$780.00')),
      findsNothing,
    );
    final orderedLabels = [
      'GRADER',
      'GRADE',
      'LANGUAGE',
      'FINISH',
      'PURCHASE PRICE',
    ];
    final labelOffsets = [
      for (final label in orderedLabels)
        tester
            .getTopLeft(
              find.descendant(of: ownershipCard, matching: find.text(label)),
            )
            .dy,
    ];
    expect(
      labelOffsets,
      orderedEquals([...labelOffsets]..sort()),
      reason: 'Read-only fields must follow the edit form order.',
    );
    expect(find.text('LANGUAGE'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
    expect(find.text('FINISH'), findsOneWidget);
    expect(find.text('Holofoil'), findsWidgets);
    expect(find.text('Total'), findsNothing);
    expect(find.text('Pulled from Obsidian Flames binder.'), findsOneWidget);
    expect(find.byKey(const Key('card-detail-price-chart')), findsNothing);
  });

  testWidgets(
    'free owners see a locked card Performance tab because financial analytics are Pro-only',
    (tester) async {
      await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-performance-locked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('kando-premium-locked-panel-preview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('kando-premium-locked-panel-blur')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-detail-unlock-performance')),
        findsOneWidget,
      );
      final lockedSize = tester.getSize(
        find.byKey(const Key('card-detail-performance-locked')),
      );
      final tabsSize = tester.getSize(
        find.byKey(const Key('card-detail-owned-tabs')),
      );
      expect(lockedSize, Size(tabsSize.width, 427));
      expect(find.text("Track This Card's Performance"), findsOneWidget);
      expect(find.text('Unlock Performance'), findsOneWidget);
      expect(find.text(r'$650.00'), findsNothing);
      expect(find.text(r'$780.00'), findsNothing);
    },
  );

  testWidgets(
    'Pro owners see server Item performance because Card Detail must not aggregate same-card Items',
    (tester) async {
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-performance-content')),
        findsOneWidget,
      );
      expect(find.text(r'$600.00'), findsOneWidget);
      expect(find.text(r'$790.00'), findsOneWidget);
      expect(find.text(r'+$190.00'), findsOneWidget);
      expect(find.text('31.67%'), findsOneWidget);
      expect(
        find.byKey(const Key('card-detail-missing-purchase-price')),
        findsNothing,
      );

      final purchaseCostCard = find.byKey(
        const Key('card-detail-performance-metric-purchase-cost'),
      );
      final currentValueCard = find.byKey(
        const Key('card-detail-performance-metric-current-value'),
      );
      final profitLossCard = find.byKey(
        const Key('card-detail-performance-metric-profit-loss'),
      );
      expect(tester.getSize(purchaseCostCard).height, 100);
      expect(tester.getSize(currentValueCard).height, 100);
      expect(tester.getSize(profitLossCard).height, 100);
      expect(
        tester.getTopLeft(currentValueCard).dx -
            tester.getTopRight(purchaseCostCard).dx,
        12,
      );
      expect(
        tester.getTopLeft(profitLossCard).dy -
            tester.getBottomLeft(purchaseCostCard).dy,
        12,
      );

      await tester.ensureVisible(
        find.byKey(const Key('card-detail-performance-chart')),
      );
      final chartPanel = find.byKey(
        const Key('card-detail-performance-chart-panel'),
      );
      expect(tester.getSize(chartPanel).height, 203);
      expect(
        find.descendant(
          of: chartPanel,
          matching: find.byKey(const Key('card-detail-performance-range-1D')),
        ),
        findsOneWidget,
      );
      final oneDayRange = tester.widget<InkWell>(
        find.byKey(const Key('card-detail-performance-range-1D')),
      );
      expect(
        oneDayRange.overlayColor?.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
      expect(oneDayRange.splashFactory, same(NoSplash.splashFactory));
      final chart = find.byKey(const Key('card-detail-performance-chart'));
      await tester.tapAt(tester.getRect(chart).center);
      await tester.pump();
      final tooltip = tester.widget<Semantics>(chart).properties.value!;
      expect(tooltip, contains('Date: 2026-08-12'));
      expect(tooltip, contains(r'Daily Change: +$40.00'));
      expect(tooltip, contains(r'Market Value: $790.00'));
      expect(tooltip, contains(r'Profit / Loss: +$190.00'));
      expect(tooltip, contains('Qty: 1'));
      expect(tooltip, isNot(contains('Price:')));

      await tester.tap(
        find.byKey(const Key('card-detail-performance-range-1D')),
      );
      await tester.pumpAndSettle();
      final oneDayChart = find.byKey(
        const Key('card-detail-performance-chart'),
      );
      expect(
        tester.widget<Semantics>(oneDayChart).properties.value,
        'No chart point selected',
      );
      await tester.tapAt(tester.getRect(oneDayChart).center);
      await tester.pump();
      expect(
        tester.widget<Semantics>(oneDayChart).properties.value,
        contains(r'Daily Change: +$40.00'),
      );
    },
  );

  testWidgets(
    'slow Card Performance range shows Home-style progress while preserving the chart',
    (tester) async {
      final performanceApi = _SlowRangeCardPerformanceApi();
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          performanceApi: performanceApi,
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('card-detail-performance-range-7D')),
      );
      await tester.pump();

      expect(find.text(r'$790.00'), findsOneWidget);
      expect(
        find.byKey(const Key('card-detail-performance-range-loading-7D')),
        findsOneWidget,
      );

      await performanceApi.completeRange();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('card-detail-performance-range-loading-7D')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Card Performance makes a single data point clearly visible before selection',
    (tester) async {
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('card-detail-performance-chart')),
      );

      final chart = find.byKey(const Key('card-detail-performance-chart'));
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
        return pixels!.getUint8((52 * 100 + 55) * 4 + 3);
      });

      expect(haloAlpha, greaterThan(0));
    },
  );

  testWidgets(
    'Pro owners without purchase price can edit the Collection Item because Performance cannot be calculated yet',
    (tester) async {
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          repository: _MissingPurchasePriceCardDetailRepository(),
          performanceApi: _MissingPriceCardPerformanceApi(),
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-missing-purchase-price')),
        findsOneWidget,
      );
      expect(
        find.text('Add purchase price to calculate your card performance.'),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('card-detail-performance-chart')),
      );
      final chart = find.byKey(const Key('card-detail-performance-chart'));
      await tester.tapAt(tester.getRect(chart).center);
      await tester.pump();
      final tooltip = tester.widget<Semantics>(chart).properties.value!;
      expect(tooltip, contains(r'Daily Change: +$55.00'));
      expect(tooltip, contains(r'Market Value: $790.00'));
      expect(tooltip, contains('Qty: 1'));
      expect(tooltip, isNot(contains('Profit / Loss')));
      expect(tooltip, isNot(contains('Purchase Cost')));
      expect(tooltip, isNot(contains('Return')));

      await tester.ensureVisible(
        find.byKey(const Key('card-detail-edit-missing-purchase-price')),
      );
      final missingPriceCard = find.byKey(
        const Key('card-detail-missing-purchase-price'),
      );
      final editPurchasePriceButton = find.byKey(
        const Key('card-detail-edit-missing-purchase-price'),
      );
      expect(tester.getSize(editPurchasePriceButton).height, 36);
      expect(
        tester.getSize(editPurchasePriceButton).width,
        lessThan(tester.getSize(missingPriceCard).width),
      );
      await tester.tap(
        find.byKey(const Key('card-detail-edit-missing-purchase-price')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-item-purchase-price')),
        findsOneWidget,
      );
      final purchasePriceField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('card-detail-item-purchase-price')),
          matching: find.byType(EditableText),
        ),
      );
      expect(purchasePriceField.controller.text, isEmpty);
    },
  );

  testWidgets(
    'saving a missing purchase price reloads Item Performance because the previous missing response is stale',
    (tester) async {
      final repository = _EditableMissingPurchasePriceCardDetailRepository();
      final performanceApi = _MissingPriceCardPerformanceApi(
        hasPurchasePrice: () => repository.hasPurchasePrice,
      );
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          repository: repository,
          performanceApi: performanceApi,
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(performanceApi.requestCount, 1);
      expect(
        find.byKey(const Key('card-detail-missing-purchase-price')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('card-detail-edit-missing-purchase-price')),
      );
      await tester.tap(
        find.byKey(const Key('card-detail-edit-missing-purchase-price')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-purchase-price')),
      );
      await tester.enterText(
        find.byKey(const Key('card-detail-item-purchase-price')),
        '600',
      );
      final submit = find.byKey(const Key('card-detail-item-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(repository.hasPurchasePrice, isTrue);
      await tester.drag(
        find.byKey(const Key('card-detail-scroll')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(performanceApi.requestCount, 2);
      expect(
        find.byKey(const Key('card-detail-missing-purchase-price')),
        findsNothing,
      );
      expect(find.text(r'$600.00'), findsOneWidget);
    },
  );

  testWidgets(
    'refreshing Card Detail reloads Item Performance because refresh must not retain its previous response',
    (tester) async {
      final repository = _EditableMissingPurchasePriceCardDetailRepository();
      final performanceApi = _MissingPriceCardPerformanceApi(
        hasPurchasePrice: () => repository.hasPurchasePrice,
      );
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          repository: repository,
          performanceApi: performanceApi,
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(performanceApi.requestCount, 1);
      expect(
        find.byKey(const Key('card-detail-missing-purchase-price')),
        findsOneWidget,
      );

      repository.hasPurchasePrice = true;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );
      await container
          .read(cardDetailControllerProvider('charizard-ex').notifier)
          .refresh();
      await tester.pumpAndSettle();
      final refreshed = container.read(
        cardDetailControllerProvider('charizard-ex'),
      );
      expect(refreshed.isUnavailable, isFalse);
      expect(refreshed.isLoading, isFalse);
      expect(refreshed.detail.collectionItems.single.id, 'item-charizard');
      expect(find.byKey(const Key('card-detail-owned-tabs')), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(performanceApi.requestCount, 2);
      expect(
        find.byKey(const Key('card-detail-missing-purchase-price')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'same-card multiple Items hide Performance without an Item context because guessing would mix ownership',
    (tester) async {
      await tester.pumpWidget(
        const _CardDetailTestApp(
          cardId: 'charizard-ex',
          repository: _MultiItemCardDetailRepository(),
          collectionItemId: null,
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Performance'), findsNothing);
      expect(find.text('Collection Item'), findsNothing);
      expect(find.text('In Your Portfolio'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
    },
  );

  testWidgets(
    'In Your Portfolio opens the editor before its market refresh completes so editing is never blocked by the network',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _DelayedEditPriceCardDetailRepository();
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          collectionItemId: null,
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      final item = find.byKey(
        const Key('card-detail-portfolio-item-item-charizard'),
      );
      await tester.scrollUntilVisible(item, 400);
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pump();

      expect(repository.pendingEditPriceRefresh, isNotNull);
      expect(find.text('SAVE CHANGES'), findsOneWidget);

      repository.completeEditPriceRefresh();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'In Your Portfolio editor uses the shared backed footer and visible Save loading',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _DelayedUpdateCardDetailRepository();
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          collectionItemId: null,
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      final item = find.byKey(
        const Key('card-detail-portfolio-item-item-charizard'),
      );
      await tester.scrollUntilVisible(item, 400);
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('card-detail-edit-item-sheet'));
      final footer = find.byKey(const Key('card-detail-item-edit-footer'));
      expect(sheet, findsOneWidget);
      expect(footer, findsOneWidget);
      expect(
        tester.getBottomRight(footer).dy,
        closeTo(tester.getBottomRight(sheet).dy, 0.01),
      );
      final footerDecoration =
          tester.widget<Container>(footer).decoration! as BoxDecoration;
      expect(footerDecoration.color, KandoColors.ink);

      final save = find.byKey(const Key('card-detail-edit-item-sheet-save'));
      await tester.tap(save);
      await tester.pump();

      expect(repository.pendingUpdate, isNotNull);
      final progress = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: save,
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(progress.color, KandoColors.primaryOnDefault);
      expect(tester.widget<TextButton>(save).onPressed, isNull);

      repository.completeUpdate();
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    },
  );

  testWidgets(
    'In Your Portfolio editor removes only after Figma confirmation because cancellation must preserve the saved Item',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const _CardDetailTestApp(
          cardId: 'charizard-ex',
          collectionItemId: null,
        ),
      );
      await tester.pumpAndSettle();

      final item = find.byKey(
        const Key('card-detail-portfolio-item-item-charizard'),
      );
      await tester.scrollUntilVisible(item, 400);
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();

      final remove = find.byKey(const Key('card-detail-remove-from-portfolio'));
      expect(remove, findsOneWidget);
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(
        find.text('This card will be removed from your portfolio'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('card-detail-remove-confirmation-cancel')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-edit-item-sheet')),
        findsOneWidget,
      );
      expect(remove, findsOneWidget);

      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('card-detail-remove-confirmation-submit')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-edit-item-sheet')),
        findsNothing,
      );
      expect(find.text('In Your Portfolio'), findsNothing);
      expect(find.text('Price'), findsOneWidget);
    },
  );

  testWidgets('Collection list entry defaults owned CardDetail to Price', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _CardDetailTestApp(
        cardId: 'charizard-ex',
        entrySource: AnalyticsValue.sourceEdit,
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-owned-tabs')),
      400,
    );

    expect(find.byKey(const Key('card-detail-price-chart')), findsOneWidget);
    expect(
      find.byKey(const Key('card-detail-collection-item-item-charizard')),
      findsNothing,
    );
  });

  testWidgets(
    'Home Performance entry opens the selected Item Performance because the ranking links to that financial context',
    (tester) async {
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          entrySource: AnalyticsValue.sourceHomePerformance,
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('card-detail-owned-tabs')),
        400,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-performance-content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-detail-collection-item-item-charizard')),
        findsNothing,
      );
      expect(find.byKey(const Key('card-detail-price-chart')), findsNothing);
    },
  );

  testWidgets(
    'Home Performance entry does not substitute another Item when the ranked Item is no longer valid',
    (tester) async {
      await tester.pumpWidget(
        _CardDetailTestApp(
          cardId: 'charizard-ex',
          collectionItemId: 'deleted-item',
          entrySource: AnalyticsValue.sourceHomePerformance,
          subscriptionController: _ProCardSubscriptionController.new,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-performance-content')),
        findsNothing,
      );
      expect(find.byKey(const Key('card-detail-owned-tabs')), findsNothing);
      expect(
        find.byKey(const Key('card-detail-portfolio-item-item-charizard')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'owned CardDetail displays one Collection Item while keeping list data',
    (tester) async {
      await tester.pumpWidget(
        const _CardDetailTestApp(
          cardId: 'charizard-ex',
          repository: _MultiItemCardDetailRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Collection Item'), 400);

      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Pulled from Obsidian Flames binder.'), findsOneWidget);
      expect(find.text('Hidden duplicate item.'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );
      expect(
        container
            .read(cardDetailControllerProvider('charizard-ex'))
            .collectionItemRows,
        hasLength(2),
      );
    },
  );

  testWidgets(
    'owned CardDetail displays the requested Collection Item because same-card versions keep independent ownership data',
    (tester) async {
      await tester.pumpWidget(
        const _CardDetailTestApp(
          cardId: 'charizard-ex',
          collectionItemId: 'item-charizard-sealed',
          repository: _MultiItemCardDetailRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Collection Item'), 400);

      expect(
        find.byKey(
          const Key('card-detail-collection-item-item-charizard-sealed'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card-detail-collection-item-item-charizard')),
        findsNothing,
      );
      expect(find.text('Sealed'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text(r'$20.00'), findsOneWidget);
      expect(find.text('Hidden duplicate item.'), findsOneWidget);
      expect(find.text('Pulled from Obsidian Flames binder.'), findsNothing);
    },
  );

  testWidgets('owned CardDetail can switch to Price overview', (tester) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Price'), 400);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.splashFactory, NoSplash.splashFactory);
    expect(
      tabs.overlayColor?.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-detail-price-chart')), findsOneWidget);
    expect(find.text('RAW'), findsOneWidget);
    expect(find.text('GRADED'), findsOneWidget);
    final priceModeControl = find.byKey(
      const Key('card-detail-price-mode-control'),
    );
    expect(tester.getSize(priceModeControl), const Size(150, 24));
    final rawMode = tester.widget<Container>(
      find.byKey(const Key('card-detail-price-mode-raw')),
    );
    final rawDecoration = rawMode.decoration! as BoxDecoration;
    expect(tester.getSize(find.byWidget(rawMode)), const Size(74, 24));
    expect(
      rawDecoration.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(6),
        bottomLeft: Radius.circular(6),
      ),
    );
    expect(
      (rawDecoration.border! as Border).top.color,
      const Color(0x1A90927C),
    );
    expect(rawDecoration.boxShadow, const [
      BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(
        color: Color(0x1FFFFFFF),
        offset: Offset(0.5, 0.5),
        blurRadius: 0.5,
        blurStyle: BlurStyle.inner,
      ),
    ]);
    expect((rawDecoration.gradient! as LinearGradient).colors, const [
      Color(0x99747B26),
      Color(0x33747B26),
    ]);
    final gradedMode = tester.widget<Container>(
      find.byKey(const Key('card-detail-price-mode-graded')),
    );
    final gradedDecoration = gradedMode.decoration! as BoxDecoration;
    expect(tester.getSize(find.byWidget(gradedMode)), const Size(77, 24));
    final rawRect = tester.getRect(find.byWidget(rawMode));
    final gradedRect = tester.getRect(find.byWidget(gradedMode));
    expect(rawRect.right - gradedRect.left, 1);
    expect(
      gradedDecoration.borderRadius,
      const BorderRadius.only(
        topRight: Radius.circular(6),
        bottomRight: Radius.circular(6),
      ),
    );
    expect(
      (gradedDecoration.border! as Border).top.color,
      const Color(0x1A90927C),
    );
    expect(gradedDecoration.boxShadow, const [
      BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 1),
      BoxShadow(
        color: Color(0x1FFFFFFF),
        offset: Offset(0.5, 0.5),
        blurRadius: 0.5,
        blurStyle: BlurStyle.inner,
      ),
    ]);
    expect(gradedDecoration.color, KandoColors.surface);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Ungraded'), findsOneWidget);
    expect(find.text(r'$215.00'), findsWidgets);
    expect(find.text('30 days ago'), findsNothing);
    expect(find.text('14 days ago'), findsNothing);
    expect(find.text('Today'), findsNothing);

    final psaCategory = find.byKey(
      const Key('card-detail-market-category-psa'),
    );
    await tester.ensureVisible(psaCategory);
    await tester.pumpAndSettle();
    await tester.tap(psaCategory);
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    expect(find.text(r'$780.00'), findsWidgets);
  });

  testWidgets('owned Price Tab selectors update visible series rows', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Price'), 400);
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GRADED'));
    await tester.pumpAndSettle();
    final selectedGradedMode = tester.widget<Container>(
      find.byKey(const Key('card-detail-price-mode-graded')),
    );
    final selectedGradedDecoration =
        selectedGradedMode.decoration! as BoxDecoration;
    expect(
      (selectedGradedDecoration.gradient! as LinearGradient).colors,
      const [Color(0x99747B26), Color(0x33747B26)],
    );
    expect(
      selectedGradedDecoration.borderRadius,
      const BorderRadius.only(
        topRight: Radius.circular(6),
        bottomRight: Radius.circular(6),
      ),
    );
    expect(selectedGradedDecoration.boxShadow!.first.blurRadius, 2);
    final unselectedRawMode = tester.widget<Container>(
      find.byKey(const Key('card-detail-price-mode-raw')),
    );
    final unselectedRawDecoration =
        unselectedRawMode.decoration! as BoxDecoration;
    expect(unselectedRawDecoration.color, KandoColors.surface);
    expect(
      unselectedRawDecoration.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(6),
        bottomLeft: Radius.circular(6),
      ),
    );
    expect(unselectedRawDecoration.boxShadow!.first.blurRadius, 1);
    expect(find.text('PSA 10'), findsOneWidget);
    expect(find.text('BGS 10'), findsOneWidget);
    expect(find.text('PSA 10 Holofoil'), findsNothing);
    expect(find.text('BGS 10 Holofoil'), findsNothing);
    final chart = find.byKey(const Key('card-detail-price-chart-interactive'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    final chartRect = tester.getRect(chart);
    final touch = await tester.startGesture(
      Offset(chartRect.left + 1, chartRect.center.dy),
    );
    await tester.pump();
    final chartSemantics = tester.widget<Semantics>(chart);
    expect(chartSemantics.properties.value, contains('PSA 10'));
    expect(chartSemantics.properties.value, contains('BGS 10'));
    expect(chartSemantics.properties.value, isNot(contains('Holofoil')));
    await touch.up();
    await tester.pump();
    await tester.ensureVisible(find.text('3M'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3M'));
    await tester.pumpAndSettle();

    expect(find.text('90 days ago'), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.text(r'$780.00'), findsWidgets);
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('owned Collection Item can be edited from CardDetail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);
    await tester.ensureVisible(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-item-quantity')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit collection item'), findsNothing);
    expect(find.text('OWNERSHIP SUMMARY'), findsOneWidget);
    expect(find.byKey(const Key('card-detail-item-portfolio')), findsOneWidget);
    expect(
      find.byKey(const Key('card-detail-item-edit-footer')),
      findsOneWidget,
    );
    expect(find.text('SAVE CHANGES'), findsOneWidget);
    expect(find.text('PURCHASE DETAILS'), findsNothing);
    expect(
      find.byKey(const Key('card-detail-remove-from-portfolio')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('card-detail-item-selected-card')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('card-detail-item-market-price')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const Key('card-detail-item-quantity')),
      '3',
    );
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-item-grader')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-item-state-raw')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-detail-item-state-raw')));
    await tester.pumpAndSettle();

    expect(find.text('CONDITION'), findsOneWidget);
    expect(find.text('GRADE'), findsNothing);
    expect(find.text('RAW DETAILS'), findsOneWidget);
    expect(find.text('GRADING DETAILS'), findsNothing);
    expect(find.text('RAW CARD'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('card-detail-item-notes')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('card-detail-item-notes')),
      'Cracked slab for binder.',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-detail-item-submit')));
    await tester.pumpAndSettle();

    expect(find.text('SAVE CHANGES'), findsNothing);
    expect(find.text('QUANTITY'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Raw'), findsOneWidget);
    expect(find.text('Near Mint (NM)'), findsOneWidget);
    expect(find.text('Cracked slab for binder.'), findsOneWidget);
  });

  testWidgets(
    'graded edit keeps grader and grade choices inline because both belong to one Figma state',
    (tester) async {
      await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Collection Item'), 400);
      await tester.ensureVisible(find.text('Edit item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit item'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-grader')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('BGS').last);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('GRADING DETAILS'), findsOneWidget);
      await tester.ensureVisible(find.text('9.5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9.5'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );
      expect(
        container
            .read(cardDetailControllerProvider('charizard-ex'))
            .collectionItemDraft
            ?.grade,
        '9.5',
      );
      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-state-raw')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-item-state-raw')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('CONDITION'), findsOneWidget);
    },
  );

  testWidgets(
    'Collection Item qualifier choices exclude values absent from this card',
    (tester) async {
      await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Collection Item'), 400);
      await tester.ensureVisible(find.text('Edit item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit item'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-language')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-item-language')));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsWidgets);
      expect(find.text('Japanese'), findsNothing);

      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-finish')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Holofoil'), findsWidgets);
      expect(find.text('Normal'), findsNothing);
    },
  );

  testWidgets(
    'Collection Item edit closes with CardDetail because reopening the card must start in read-only mode',
    (tester) async {
      await tester.pumpWidget(const _CardDetailReentryApp());
      await tester.tap(find.byKey(const Key('open-card-detail')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Collection Item'), 400);
      await tester.ensureVisible(find.text('Edit item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit item'));
      await tester.pumpAndSettle();
      expect(find.text('SAVE CHANGES'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-card-detail')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-card-detail')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Collection Item'), 400);
      await tester.ensureVisible(find.text('Edit item'));
      await tester.pumpAndSettle();

      expect(find.text('Edit item'), findsOneWidget);
      expect(find.text('SAVE CHANGES'), findsNothing);
    },
  );

  testWidgets(
    'Card Performance keeps its range across tabs but resets to 1M after reentry',
    (tester) async {
      BoxDecoration rangeDecoration(String range) {
        final indicator = find.ancestor(
          of: find.byKey(Key('card-detail-performance-range-$range')),
          matching: find.byType(Ink),
        );
        expect(indicator, findsOneWidget);
        return tester.widget<Ink>(indicator).decoration! as BoxDecoration;
      }

      await tester.pumpWidget(const _CardDetailReentryApp());
      await tester.tap(find.byKey(const Key('open-card-detail')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(rangeDecoration('1M').gradient, isNotNull);
      expect(rangeDecoration('3M').gradient, isNull);

      await tester.tap(
        find.byKey(const Key('card-detail-performance-range-3M')),
      );
      await tester.pumpAndSettle();
      expect(rangeDecoration('3M').gradient, isNotNull);

      await tester.tap(find.text('Price'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(rangeDecoration('3M').gradient, isNotNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-card-detail')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Performance'), 400);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(rangeDecoration('1M').gradient, isNotNull);
      expect(rangeDecoration('3M').gradient, isNull);
    },
  );

  testWidgets(
    'owned Collection Item edit keeps keyboard dismissed after changing another field',
    (tester) async {
      await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Collection Item'), 400);
      await tester.ensureVisible(find.text('Edit item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit item'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-quantity')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('card-detail-item-quantity')),
        '3',
      );
      await tester.pump();

      expect(tester.testTextInput.isVisible, isTrue);

      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-language')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-item-language')));
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isFalse);
      final quantityField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('card-detail-item-quantity')),
          matching: find.byType(EditableText),
        ),
      );
      expect(quantityField.focusNode.hasFocus, isFalse);
    },
  );

  testWidgets('owned Collection Item purchase price uses decimal keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);
    await tester.ensureVisible(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-item-purchase-price')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final purchasePriceField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('card-detail-item-purchase-price')),
        matching: find.byType(EditableText),
      ),
    );

    expect(
      purchasePriceField.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
  });

  testWidgets('owned Collection Item Save shows loading while saving', (
    tester,
  ) async {
    final repository = _DelayedUpdateCardDetailRepository();
    await tester.pumpWidget(
      _CardDetailTestApp(cardId: 'charizard-ex', repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);
    await tester.ensureVisible(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('card-detail-item-submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();

    expect(repository.pendingUpdate, isNotNull);
    expect(
      find.descendant(
        of: submit,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(tester.widget<TextButton>(submit).onPressed, isNull);

    repository.completeUpdate();
    await tester.pumpAndSettle();

    expect(find.text('SAVE CHANGES'), findsNothing);
    expect(find.text('Edit item'), findsOneWidget);
  });

  testWidgets('owned Collection Item shows validation without losing draft', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);
    await tester.ensureVisible(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-item-quantity')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('card-detail-item-quantity')),
      '0',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CardDetailPage)),
    );
    expect(
      await container
          .read(cardDetailControllerProvider('charizard-ex').notifier)
          .saveCollectionItemDraft(),
      isFalse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Quantity must be at least 1.'), findsOneWidget);
    expect(find.text('OWNERSHIP SUMMARY'), findsOneWidget);
  });

  testWidgets('owned Collection Item can be removed after confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-remove-from-portfolio')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('card-detail-remove-from-portfolio-icon')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await tester.tap(
      find.byKey(const Key('card-detail-remove-from-portfolio')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.byKey(const Key('card-detail-remove-confirmation-sheet')),
      findsOneWidget,
    );
    expect(
      find.text('This card will be removed from your portfolio'),
      findsOneWidget,
    );
    expect(find.text('CANCEL'), findsOneWidget);
    expect(find.text('REMOVE'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('card-detail-remove-confirmation-cancel')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Collection Item'), findsOneWidget);
    expect(
      find.byKey(const Key('card-detail-remove-confirmation-sheet')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('card-detail-remove-from-portfolio')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('card-detail-remove-confirmation-submit')),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('card-detail-scroll')),
      const Offset(0, 800),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add to Portfolio'), findsNothing);
    expect(
      find.byKey(const Key('card-detail-add-to-portfolio-charizard-ex')),
      findsOneWidget,
    );
    expect(find.text('Collection Item'), findsNothing);
    expect(find.byKey(const Key('card-detail-price-chart')), findsOneWidget);
  });

  testWidgets('owned CardDetail shares its real identity and market price', (
    tester,
  ) async {
    final actions = _RecordingCardDetailActions();
    await tester.pumpWidget(
      _CardDetailTestApp(cardId: 'charizard-ex', actions: actions),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('card-detail-share-charizard-ex')));
    await tester.pumpAndSettle();

    expect(actions.name, 'Charizard ex');
    expect(actions.cardRef, 'charizard-ex');
    expect(actions.setName, 'Obsidian Flames');
    expect(actions.marketPrice, r'$780.00');
    expect(actions.sharePositionOrigin, isNotNull);
    expect(actions.sharePositionOrigin?.isEmpty, isFalse);
  });

  testWidgets('unknown CardDetail shows shared failure copy', (tester) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'missing-card'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CardDetailPage)),
    );
    await container.read(authControllerProvider.notifier).startupComplete;
    await container
        .read(cardDetailControllerProvider('missing-card').notifier)
        .refresh();
    expect(
      container.read(cardDetailControllerProvider('missing-card')).loadStatus,
      KandoLoadStatus.failure,
    );
    await tester.pump();

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
  });

  testWidgets('CardDetail route reads cardId from path', (tester) async {
    await tester.pumpWidget(const _CardDetailRouteApp());
    await tester.pumpAndSettle();

    expect(find.text('Squirtle'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-price-chart')),
      400,
    );
    expect(find.byKey(const Key('card-detail-price-chart')), findsOneWidget);
  });
}

class _CardDetailTestApp extends StatelessWidget {
  const _CardDetailTestApp({
    required this.cardId,
    this.actions,
    this.repository,
    this.entrySource = AnalyticsValue.sourceSearch,
    this.subscriptionController,
    this.performanceApi,
    this.collectionItemId = 'item-charizard',
  });

  final String cardId;
  final CardDetailActions? actions;
  final CardDetailRepository? repository;
  final String entrySource;
  final SubscriptionController Function()? subscriptionController;
  final PortfolioApiClient? performanceApi;
  final String? collectionItemId;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(_cardDetailAuthStorage),
        authRepositoryProvider.overrideWithValue(_cardDetailAuthRepository),
        cardDetailRepositoryProvider.overrideWithValue(
          repository ?? const MockCardDetailRepository(),
        ),
        portfolioApiClientProvider.overrideWithValue(
          performanceApi ?? _CardPerformanceApi(),
        ),
        if (actions != null)
          cardDetailActionsProvider.overrideWithValue(actions!),
        subscriptionControllerProvider.overrideWith(
          subscriptionController ?? _FreeCardSubscriptionController.new,
        ),
      ],
      child: MaterialApp(
        home: CardDetailPage(
          cardId: cardId,
          collectionItemId: collectionItemId,
          entrySource: entrySource,
        ),
      ),
    );
  }
}

class _CardDetailPriceRangeRouteApp extends StatelessWidget {
  const _CardDetailPriceRangeRouteApp();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(_cardDetailAuthStorage),
        authRepositoryProvider.overrideWithValue(_cardDetailAuthRepository),
        cardDetailRepositoryProvider.overrideWithValue(
          const MockCardDetailRepository(),
        ),
        portfolioApiClientProvider.overrideWithValue(_CardPerformanceApi()),
        subscriptionControllerProvider.overrideWith(
          _FreeCardSubscriptionController.new,
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const CardDetailPage(
                cardId: 'squirtle',
                collectionItemId: null,
              ),
            ),
            GoRoute(
              path: '/subscription',
              builder: (context, state) => const Scaffold(
                key: Key('card-detail-price-subscription-target'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProCardSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() => const SubscriptionState(isPro: true);
}

class _FreeCardSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.free);
}

class _CardPerformanceApi extends PortfolioApiClient {
  _CardPerformanceApi() : super(Dio());

  @override
  Future<PortfolioPerformanceDto> getItemPerformance(
    AuthSession session, {
    required String itemId,
    required PerformanceRange range,
    bool localPremiumVerified = false,
  }) async {
    final point = PerformancePointDto(
      date: '2026-08-12',
      marketValueUsd: 790,
      marketValueChangeUsd: 55,
      marketChangeUsd: 10,
      portfolioChangeUsd: 20,
      paidMarketValueUsd: 790,
      totalPaidUsd: 600,
      profitLossUsd: 190,
      profitLossChangeUsd: 40,
      returnPercent: 31.67,
      quantity: 1,
      quantityChange: 0,
    );
    return PortfolioPerformanceDto(
      range: range,
      rangeStart: '2026-07-12',
      rangeEnd: '2026-08-12',
      historyAvailableFrom: '2026-07-12',
      partialHistory: false,
      itemCount: 1,
      marketPriceStatus: MarketPriceStatus.available,
      purchasePriceStatus: PurchasePriceStatus.complete,
      purchasePriceItemCount: 1,
      current: point,
      series: [point],
    );
  }
}

class _SlowRangeCardPerformanceApi extends _CardPerformanceApi {
  Completer<PortfolioPerformanceDto>? _pending;
  Future<PortfolioPerformanceDto>? _response;

  @override
  Future<PortfolioPerformanceDto> getItemPerformance(
    AuthSession session, {
    required String itemId,
    required PerformanceRange range,
    bool localPremiumVerified = false,
  }) {
    final response = super.getItemPerformance(
      session,
      itemId: itemId,
      range: range,
      localPremiumVerified: localPremiumVerified,
    );
    if (range == PerformanceRange.oneMonth) return response;
    _pending = Completer<PortfolioPerformanceDto>();
    _response = response;
    return _pending!.future;
  }

  Future<void> completeRange() async {
    _pending!.complete(await _response!);
  }
}

class _MissingPriceCardPerformanceApi extends _CardPerformanceApi {
  _MissingPriceCardPerformanceApi({this.hasPurchasePrice});

  final bool Function()? hasPurchasePrice;
  int requestCount = 0;

  @override
  Future<PortfolioPerformanceDto> getItemPerformance(
    AuthSession session, {
    required String itemId,
    required PerformanceRange range,
    bool localPremiumVerified = false,
  }) async {
    requestCount += 1;
    final normal = await super.getItemPerformance(
      session,
      itemId: itemId,
      range: range,
      localPremiumVerified: localPremiumVerified,
    );
    if (hasPurchasePrice?.call() ?? false) return normal;
    final point = PerformancePointDto(
      date: normal.current.date,
      marketValueUsd: normal.current.marketValueUsd,
      marketValueChangeUsd: normal.current.marketValueChangeUsd,
      marketChangeUsd: normal.current.marketChangeUsd,
      portfolioChangeUsd: normal.current.portfolioChangeUsd,
      paidMarketValueUsd: null,
      totalPaidUsd: null,
      profitLossUsd: null,
      profitLossChangeUsd: null,
      returnPercent: null,
      quantity: normal.current.quantity,
      quantityChange: normal.current.quantityChange,
    );
    return PortfolioPerformanceDto(
      range: range,
      rangeStart: normal.rangeStart,
      rangeEnd: normal.rangeEnd,
      historyAvailableFrom: normal.historyAvailableFrom,
      partialHistory: false,
      itemCount: 1,
      marketPriceStatus: MarketPriceStatus.available,
      purchasePriceStatus: PurchasePriceStatus.missing,
      purchasePriceItemCount: 0,
      current: point,
      series: [point],
    );
  }
}

class _FinishTabCardDetailRepository extends MockCardDetailRepository
    implements CardDetailSectionRepository {
  _FinishTabCardDetailRepository({this.finishes = const ['Normal', 'Foil']});

  final List<String> finishes;
  final List<String?> requestedFinishes = [];

  @override
  Future<CardDetail> loadCoreDetail(String cardId) async {
    return CardDetail(
      id: '180865',
      type: CardDetailType.tcg,
      name: 'Test Card',
      game: 'Pokemon',
      setName: 'Test Set',
      identityLine: '#180865',
      finish: 'Normal',
      language: 'English',
      availableFinishes: finishes,
      quantity: 0,
      isWishlisted: false,
      marketPrices: [
        CardMarketPrice(
          label: 'Raw Near Mint',
          priceUsd: 10,
          previous30dPriceUsd: null,
        ),
      ],
    );
  }

  @override
  Future<CardDetail> loadBaseDetail(AuthSession session, String cardId) {
    return loadCoreDetail(cardId);
  }

  @override
  Future<CardDetail> loadAssetState(
    AuthSession session,
    CardDetail detail,
  ) async {
    return detail;
  }

  @override
  Future<CardDetailMarketData> loadMarketPrices(
    String cardId, {
    String? finish,
    String? language,
  }) async {
    requestedFinishes.add(finish);
    final price = finish == 'Foil' ? 20.0 : 10.0;
    final dto = CardDataMarketPriceDto(
      grader: 'Raw',
      grade: null,
      condition: 'Near Mint',
      price: price,
    );
    return CardDetailMarketData(
      prices: [dto],
      marketPrices: [
        CardMarketPrice(
          label: 'Raw Near Mint',
          condition: 'Near Mint',
          priceUsd: price,
          previous30dPriceUsd: null,
        ),
      ],
    );
  }

  @override
  Future<CardDetailSeriesData> loadPriceSeries(
    String cardId, {
    CardDetailMarketData? market,
    String? finish,
    Iterable<CardPriceRange> ranges = const [
      CardPriceRange.oneDay,
      CardPriceRange.sevenDays,
      CardPriceRange.fifteenDays,
      CardPriceRange.oneMonth,
      CardPriceRange.threeMonths,
    ],
  }) async {
    final price = finish == 'Foil' ? 20.0 : 10.0;
    final points = [
      CardPricePoint(dateLabel: '2026-07-01', priceUsd: price - 1),
      CardPricePoint(dateLabel: '2026-07-30', priceUsd: price),
    ];
    return CardDetailSeriesData(
      marketPrices: market?.marketPrices ?? const [],
      rawSeriesByRange: {CardPriceRange.oneMonth: points},
      rawSeries: [
        CardPriceChartSeries(
          label: 'Raw Near Mint',
          seriesByRange: {CardPriceRange.oneMonth: points},
        ),
      ],
      gradedSeriesByRange: const {},
    );
  }

  @override
  Future<List<CardSoldListing>> loadSoldListings(String cardId) async =>
      const [];
}

class _DelayedEditPriceCardDetailRepository
    extends _FinishTabCardDetailRepository {
  Completer<CardDetailMarketData>? pendingEditPriceRefresh;
  var _marketPriceRequestCount = 0;

  @override
  Future<CardDetail> loadCoreDetail(String cardId) {
    return const MockCardDetailRepository().loadDetail(
      const AuthSession(
        ownerType: OwnerType.anonymous,
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      ),
      cardId,
    );
  }

  @override
  Future<CardDetailMarketData> loadMarketPrices(
    String cardId, {
    String? finish,
    String? language,
  }) {
    _marketPriceRequestCount += 1;
    if (_marketPriceRequestCount == 1) {
      return Future.value(_editMarketData);
    }
    pendingEditPriceRefresh = Completer<CardDetailMarketData>();
    return pendingEditPriceRefresh!.future;
  }

  void completeEditPriceRefresh() {
    pendingEditPriceRefresh?.complete(_editMarketData);
  }

  static final _editMarketData = CardDetailMarketData(
    prices: const [
      CardDataMarketPriceDto(
        grader: 'PSA',
        grade: 10,
        condition: null,
        price: 780,
      ),
    ],
    marketPrices: const [
      CardMarketPrice(
        label: 'PSA 10',
        grader: 'PSA',
        grade: 10,
        priceUsd: 780,
        previous30dPriceUsd: null,
      ),
    ],
  );
}

class _CardDetailRouteApp extends StatelessWidget {
  const _CardDetailRouteApp();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: _cardDetailOverrides,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/cards/squirtle',
          routes: [
            GoRoute(
              path: '/cards/:cardId',
              builder: (context, state) {
                return CardDetailPage(
                  cardId: state.pathParameters['cardId'] ?? '',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CardDetailReentryApp extends StatelessWidget {
  const _CardDetailReentryApp();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        ..._cardDetailOverrides,
        portfolioApiClientProvider.overrideWithValue(_CardPerformanceApi()),
        subscriptionControllerProvider.overrideWith(
          _ProCardSubscriptionController.new,
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-card-detail'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const CardDetailPage(
                      cardId: 'charizard-ex',
                      collectionItemId: 'item-charizard',
                    ),
                  ),
                ),
                child: const Text('Open card'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _cardDetailAuthStorage = InMemoryAuthStorage();
final _cardDetailAuthRepository = LocalPlaceholderAuthRepository(
  _cardDetailAuthStorage,
);

final _cardDetailOverrides = [
  authStorageProvider.overrideWithValue(_cardDetailAuthStorage),
  authRepositoryProvider.overrideWithValue(_cardDetailAuthRepository),
  cardDetailRepositoryProvider.overrideWithValue(
    const MockCardDetailRepository(),
  ),
];

class _RecordingCardDetailActions implements CardDetailActions {
  String? cardRef;
  String? name;
  String? setName;
  String? marketPrice;
  String? marketplaceUrl;
  String? soldListingsName;
  String? soldListingsSetName;
  Rect? sharePositionOrigin;

  @override
  Future<void> openMarketplaceListing(String url) async {
    marketplaceUrl = url;
  }

  @override
  Future<void> openSoldListings({
    required String name,
    required String setName,
  }) async {
    soldListingsName = name;
    soldListingsSetName = setName;
  }

  @override
  Future<void> shareCard({
    required String cardRef,
    required String name,
    required String setName,
    required String marketPrice,
    Rect? sharePositionOrigin,
  }) async {
    this.cardRef = cardRef;
    this.name = name;
    this.setName = setName;
    this.marketPrice = marketPrice;
    this.sharePositionOrigin = sharePositionOrigin;
  }
}

class _DelayedUpdateCardDetailRepository extends MockCardDetailRepository {
  Completer<CardCollectionItem>? pendingUpdate;

  @override
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) {
    final completer = Completer<CardCollectionItem>();
    pendingUpdate = completer;
    return completer.future;
  }

  void completeUpdate() {
    final completer = pendingUpdate;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete(
      const CardCollectionItem(
        id: 'owned-charizard',
        cardRef: 'charizard-ex',
        folderId: 'main',
        portfolioName: 'Main',
        quantity: 1,
        grader: 'PSA',
        condition: null,
        grade: '10',
        language: 'English',
        finish: 'Holofoil',
        purchasePriceUsd: 120,
        notes: 'Pulled from Obsidian Flames binder.',
      ),
    );
  }
}

class _FailingRemovalCardDetailRepository extends MockCardDetailRepository {
  @override
  Future<void> deleteWishlist(AuthSession session, String wishlistItemId) {
    throw StateError('wishlist removal unavailable');
  }
}

class _DuplicateCreateCardDetailRepository extends MockCardDetailRepository {
  const _DuplicateCreateCardDetailRepository();

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
    String? idempotencyKey,
  }) {
    throw const PortfolioApiException(
      duplicateCollectionItemMessage,
      code: duplicateCollectionItemErrorCode,
    );
  }
}

class _MultiItemCardDetailRepository extends MockCardDetailRepository {
  const _MultiItemCardDetailRepository();

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await super.loadDetail(session, cardId);
    final firstItem = detail.collectionItems.first;
    return detail.copyWith(
      collectionItems: [
        firstItem,
        CardCollectionItem(
          id: 'item-charizard-sealed',
          cardRef: firstItem.cardRef,
          folderId: firstItem.folderId,
          portfolioName: 'Sealed',
          quantity: 2,
          grader: 'Raw',
          condition: 'Lightly Played (LP)',
          grade: null,
          language: firstItem.language,
          finish: firstItem.finish,
          purchasePriceUsd: 20.0,
          notes: 'Hidden duplicate item.',
        ),
      ],
    );
  }
}

class _MissingPurchasePriceCardDetailRepository
    extends MockCardDetailRepository {
  const _MissingPurchasePriceCardDetailRepository();

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await super.loadDetail(session, cardId);
    return detail.copyWith(
      collectionItems: [
        detail.collectionItems.first.copyWith(purchasePriceUsd: null),
      ],
    );
  }
}

class _EditableMissingPurchasePriceCardDetailRepository
    extends _MissingPurchasePriceCardDetailRepository {
  bool hasPurchasePrice = false;

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await super.loadDetail(session, cardId);
    if (!hasPurchasePrice) return detail;
    return detail.copyWith(
      collectionItems: [
        detail.collectionItems.first.copyWith(purchasePriceUsd: 600.0),
      ],
    );
  }

  @override
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    hasPurchasePrice = item.purchasePriceUsd != null;
    return item.copyWith(cardRef: detail.id);
  }
}

class _FailingSectionCardDetailRepository extends MockCardDetailRepository
    implements CardDetailSectionRepository {
  const _FailingSectionCardDetailRepository();

  @override
  Future<CardDetail> loadBaseDetail(AuthSession session, String cardId) {
    return loadDetail(session, cardId);
  }

  @override
  Future<CardDetail> loadCoreDetail(String cardId) {
    return loadDetail(
      const AuthSession(
        ownerType: OwnerType.anonymous,
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
      ),
      cardId,
    );
  }

  @override
  Future<CardDetail> loadAssetState(
    AuthSession session,
    CardDetail detail,
  ) async {
    return detail;
  }

  @override
  Future<CardDetailMarketData> loadMarketPrices(
    String cardId, {
    String? finish,
    String? language,
  }) {
    throw StateError('market prices unavailable');
  }

  @override
  Future<CardDetailSeriesData> loadPriceSeries(
    String cardId, {
    CardDetailMarketData? market,
    String? finish,
    Iterable<CardPriceRange> ranges = const [
      CardPriceRange.oneDay,
      CardPriceRange.sevenDays,
      CardPriceRange.fifteenDays,
      CardPriceRange.oneMonth,
      CardPriceRange.threeMonths,
    ],
  }) {
    throw StateError('price series unavailable');
  }

  @override
  Future<List<CardSoldListing>> loadSoldListings(String cardId) {
    throw StateError('sold listings unavailable');
  }
}
