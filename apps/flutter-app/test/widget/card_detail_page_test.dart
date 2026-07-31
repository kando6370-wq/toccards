import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_card_detail_repository.dart';

void main() {
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

      await tester.tap(foilTab);
      await tester.pumpAndSettle();

      expect(repository.requestedFinishes.last, 'Foil');
      expect(find.text(r'$20.00'), findsWidgets);
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
    expect(find.text('6M'), findsNothing);
    expect(find.text('12M'), findsNothing);
    expect(find.text('MAX'), findsNothing);
    expect(find.text('30D'), findsNothing);
    expect(find.text('30 days ago'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
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
    'top portfolio icon opens the Figma item sheet because creation is a focused workflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        const _CardDetailTestApp(cardId: 'one-piece-luffy'),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      final portfolioIcon = tester.widget<SvgPicture>(
        find.byKey(const Key('card-detail-add-to-portfolio-icon')),
      );
      expect(
        portfolioIcon.bytesLoader,
        isA<SvgAssetLoader>().having(
          (loader) => loader.assetName,
          'assetName',
          'assets/collection/add_to_portfolio.svg',
        ),
      );
      expect(portfolioIcon.width, 20);
      expect(portfolioIcon.height, 20);

      await tester.tap(
        find.byKey(const Key('card-detail-add-to-portfolio-one-piece-luffy')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('card-detail-add-item-sheet')),
        findsOneWidget,
      );
      expect(find.text('Collection item'), findsOneWidget);
      expect(find.text('Adding to Main'), findsOneWidget);
      await tester.tap(find.byKey(const Key('card-detail-add-item-portfolio')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNWidgets(2));
      expect(find.text('Portfolio'), findsOneWidget);
      await tester.tap(find.text('Sealed').last);
      await tester.pumpAndSettle();
      expect(find.text('Adding to Sealed'), findsOneWidget);
      expect(find.byKey(const Key('card-detail-item-portfolio')), findsNothing);
      expect(find.text('Language'), findsWidgets);
      expect(find.text('Finish'), findsWidgets);
      expect(find.text('TOTAL VALUE'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('card-detail-item-total')))
            .data,
        '--',
      );
      expect(find.text('Add this card'), findsOneWidget);
      expect(find.text('Near Mint (NM)'), findsWidgets);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getBottomRight(find.byKey(const Key('card-detail-item-submit')))
            .dy,
        lessThanOrEqualTo(544),
      );
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      final submitTopBeforeScroll = tester.getTopLeft(
        find.byKey(const Key('card-detail-item-submit')),
      );
      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-condition')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const Key('card-detail-item-submit'))).dy,
        submitTopBeforeScroll.dy,
      );
      await tester.tap(find.byKey(const Key('card-detail-item-condition')));
      await tester.pumpAndSettle();
      expect(find.text('Lightly Played (LP)'), findsOneWidget);
      expect(find.text('Near Mint (NM)'), findsWidgets);
      await tester.tap(find.text('Near Mint (NM)').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('card-detail-item-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-item-submit')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );
      final savedState = container.read(
        cardDetailControllerProvider('one-piece-luffy'),
      );
      final savedDetail = savedState.detail;

      expect(savedDetail.isCollected, isTrue);
      expect(savedDetail.quantity, 1);
      expect(savedDetail.isWishlisted, isFalse);
      expect(find.byKey(const Key('card-detail-add-item-sheet')), findsNothing);
      expect(
        find.byKey(const Key('card-detail-add-to-portfolio-one-piece-luffy')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('card-detail-share-one-piece-luffy')),
        findsOneWidget,
      );
      expect(find.text('OWNERSHIP SUMMARY'), findsNothing);
      expect(savedState.collectionItemRows.single.portfolioName, 'Sealed');
      expect(
        savedState.collectionItemRows.single.statusText,
        'Raw / Near Mint (NM)',
      );
      expect(savedState.collectionItemRows.single.purchasePriceText, '--');
      final successToast = find.byKey(
        const Key('kando-centered-success-toast'),
      );
      expect(successToast, findsOneWidget);
      expect(find.byKey(const Key('kando-top-toast')), findsNothing);
      expect(find.text('Success'), findsOneWidget);
      expect(find.text(portfolioCardAddedToastText), findsOneWidget);
      expect(tester.getSize(successToast), const Size(320, 212));
      final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        tester.getCenter(successToast),
        Offset(viewSize.width / 2, viewSize.height / 2),
      );
      final title = tester.widget<Text>(find.text('Success'));
      expect(title.style?.fontFamily, 'Fraunces');
      expect(title.style?.fontSize, 24);
      expect(title.style?.fontWeight, FontWeight.w600);
      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pump();
      expect(successToast, findsNothing);
    },
  );

  testWidgets('Add this card waits for the API before showing success', (
    tester,
  ) async {
    final repository = _DelayedCreateCardDetailRepository();
    await tester.pumpWidget(
      _CardDetailTestApp(cardId: 'one-piece-luffy', repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('card-detail-add-to-portfolio-one-piece-luffy')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-detail-item-submit')));
    await tester.pump();

    expect(repository.pendingCreate, isNotNull);
    expect(find.byKey(const Key('card-detail-add-item-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('card-detail-item-submit-loading')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('card-detail-item-submit')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    expect(find.text('Add this card'), findsOneWidget);
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);

    repository.completeCreate();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-detail-add-item-sheet')), findsNothing);
    expect(
      find.byKey(const Key('card-detail-item-submit-loading')),
      findsNothing,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CardDetailPage)),
    );
    expect(
      container
          .read(cardDetailControllerProvider('one-piece-luffy'))
          .isSavingCollectionItemDraft,
      isFalse,
    );
    expect(
      find.byKey(const Key('kando-centered-success-toast')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
    expect(find.text(portfolioCardAddedToastText), findsOneWidget);
    await tester.pump(kandoCenteredSuccessToastDuration);
    await tester.pump();
  });

  testWidgets(
    'add item links graded graders to the styled grade sheet because grade is a dependent choice',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const _CardDetailTestApp(cardId: 'one-piece-luffy'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('card-detail-add-to-portfolio-one-piece-luffy')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('card-detail-item-grader')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BGS').last);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNWidgets(2));
      expect(find.text('Grade'), findsWidgets);
      expect(find.text('BGS 10'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(
        tester
            .getBottomRight(find.byKey(const Key('card-detail-choice-sheet')))
            .dy,
        844,
      );
      expect(
        tester
            .widget<Material>(find.byKey(const Key('card-detail-choice-sheet')))
            .borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );

      await tester.tap(find.text('9.5'));
      await tester.pumpAndSettle();
      expect(find.text('BGS 9.5'), findsOneWidget);

      await tester.tap(find.byKey(const Key('card-detail-item-grade')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('card-detail-item-grader')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Raw').last);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.byKey(const Key('card-detail-item-condition')),
        findsOneWidget,
      );
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
    expect(find.text('LANGUAGE'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
    expect(find.text('FINISH'), findsOneWidget);
    expect(find.text('Holofoil'), findsWidgets);
    expect(find.text('Total'), findsNothing);
    expect(find.text('Pulled from Obsidian Flames binder.'), findsOneWidget);
    expect(find.byKey(const Key('card-detail-price-chart')), findsNothing);
  });

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
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Ungraded'), findsOneWidget);
    expect(find.text(r'$215.00'), findsWidgets);

    await tester.tap(find.byKey(const Key('card-detail-market-category-psa')));
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
    expect(find.text('PSA 10 Holofoil'), findsOneWidget);
    expect(find.text('BGS 10 Holofoil'), findsOneWidget);
    final chart = find.byKey(const Key('card-detail-price-chart-interactive'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    final chartRect = tester.getRect(chart);
    final touch = await tester.startGesture(
      Offset(chartRect.left + 1, chartRect.center.dy),
    );
    await tester.pump();
    final chartSemantics = tester.widget<Semantics>(chart);
    expect(chartSemantics.properties.value, contains('PSA 10 Holofoil'));
    expect(chartSemantics.properties.value, contains('BGS 10 Holofoil'));
    await touch.up();
    await tester.pump();
    await tester.ensureVisible(find.text('3M'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3M'));
    await tester.pumpAndSettle();

    expect(find.text('90 days ago'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text(r'$780.00'), findsWidgets);
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('owned Collection Item can be edited from CardDetail', (
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

    expect(find.text('OWNERSHIP\nSUMMARY'), findsOneWidget);
    expect(find.byKey(const Key('card-detail-item-portfolio')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('card-detail-item-quantity')),
      '3',
    );
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-item-grader')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raw').last);
    await tester.pumpAndSettle();

    expect(find.text('CONDITION'), findsOneWidget);
    expect(find.text('GRADE'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('card-detail-item-notes')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('card-detail-item-notes')),
      'Cracked slab for binder.',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-item-submit')),
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-detail-item-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Save changes'), findsNothing);
    expect(find.text('QUANTITY'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Raw'), findsOneWidget);
    expect(find.text('Near Mint (NM)'), findsOneWidget);
    expect(find.text('Cracked slab for binder.'), findsOneWidget);
  });

  testWidgets(
    'choosing a graded grader opens grade choices so its dependent grade can be completed immediately',
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

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('GRADE'), findsNWidgets(2));
      expect(find.text('BGS 10'), findsOneWidget);

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

      await tester.tap(find.text('Raw').last);
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
      await tester.tap(find.byKey(const Key('card-detail-item-finish')));
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
      expect(find.text('Save changes'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-card-detail')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-card-detail')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Collection Item'), 400);
      await tester.ensureVisible(find.text('Edit item'));
      await tester.pumpAndSettle();

      expect(find.text('Edit item'), findsOneWidget);
      expect(find.text('Save changes'), findsNothing);
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

  testWidgets('owned Collection Item Save changes shows loading while saving', (
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

    expect(find.text('Save changes'), findsNothing);
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
    expect(find.text('OWNERSHIP\nSUMMARY'), findsOneWidget);
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
      const Offset(0, 400),
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
  });

  final String cardId;
  final CardDetailActions? actions;
  final CardDetailRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(_cardDetailAuthStorage),
        authRepositoryProvider.overrideWithValue(_cardDetailAuthRepository),
        cardDetailRepositoryProvider.overrideWithValue(
          repository ?? const MockCardDetailRepository(),
        ),
        if (actions != null)
          cardDetailActionsProvider.overrideWithValue(actions!),
      ],
      child: MaterialApp(home: CardDetailPage(cardId: cardId)),
    );
  }
}

class _FinishTabCardDetailRepository extends MockCardDetailRepository
    implements CardDetailSectionRepository {
  final List<String?> requestedFinishes = [];

  @override
  Future<CardDetail> loadCoreDetail(String cardId) async {
    return const CardDetail(
      id: '180865',
      type: CardDetailType.tcg,
      name: 'Test Card',
      game: 'Pokemon',
      setName: 'Test Set',
      identityLine: '#180865',
      finish: 'Normal',
      language: 'English',
      availableFinishes: ['Normal', 'Foil'],
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
      overrides: _cardDetailOverrides,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-card-detail'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const CardDetailPage(cardId: 'charizard-ex'),
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
  }) async {
    this.cardRef = cardRef;
    this.name = name;
    this.setName = setName;
    this.marketPrice = marketPrice;
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

class _DelayedCreateCardDetailRepository extends MockCardDetailRepository {
  Completer<CardCollectionItem>? pendingCreate;

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) {
    final completer = Completer<CardCollectionItem>();
    pendingCreate = completer;
    return completer.future;
  }

  void completeCreate() {
    final completer = pendingCreate;
    if (completer == null || completer.isCompleted) return;
    completer.complete(
      const CardCollectionItem(
        id: 'created-luffy',
        cardRef: 'one-piece-luffy',
        folderId: 'main',
        portfolioName: 'Main',
        quantity: 1,
        grader: 'Raw',
        condition: 'Near Mint (NM)',
        grade: null,
        language: 'English',
        finish: 'Holofoil',
        purchasePriceUsd: null,
        notes: '',
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

class _MultiItemCardDetailRepository extends MockCardDetailRepository {
  const _MultiItemCardDetailRepository();

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await super.loadDetail(session, cardId);
    final firstItem = detail.collectionItems.first;
    return detail.copyWith(
      collectionItems: [
        firstItem,
        firstItem.copyWith(
          portfolioName: 'Sealed',
          quantity: 2,
          grader: 'Raw',
          condition: 'Lightly Played (LP)',
          grade: null,
          purchasePriceUsd: 20.0,
          notes: 'Hidden duplicate item.',
        ),
      ],
    );
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
  }) {
    throw StateError('market prices unavailable');
  }

  @override
  Future<CardDetailSeriesData> loadPriceSeries(
    String cardId, {
    CardDetailMarketData? market,
    String? finish,
  }) {
    throw StateError('price series unavailable');
  }

  @override
  Future<List<CardSoldListing>> loadSoldListings(String cardId) {
    throw StateError('sold listings unavailable');
  }
}
