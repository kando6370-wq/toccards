import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_card_tile.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/in_memory_portfolio_amount_hidden_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_collection_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  testWidgets(
    'Collection keeps static controls visible while data is pending',
    (tester) async {
      final repository = _PendingCollectionRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            collectionRepositoryProvider.overrideWithValue(repository),
            subscriptionControllerProvider.overrideWith(
              _FreeCollectionSubscriptionController.new,
            ),
          ],
          child: const _CollectionTestApp(),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('collection-controls-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('collection-segmented-tabs')),
        findsOneWidget,
      );
      expect(find.text('Portfolio'), findsWidgets);
      expect(find.text('Wishlist'), findsOneWidget);
      expect(find.byKey(const Key('collection-search-field')), findsOneWidget);
      expect(find.byType(KandoLoadingBlock), findsOneWidget);
      expect(repository.calls, 1);
    },
  );

  testWidgets('Collection filter matches the 390x884 Figma viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 884);
    addTearDown(tester.view.reset);

    await _pumpCollection(tester);
    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();

    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Price: High to Low'), findsOneWidget);
    expect(find.text('Price: Low to High'), findsOneWidget);
    final highToLowOption = tester.getRect(
      find
          .ancestor(
            of: find.text('Price: High to Low'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    final lowToHighOption = tester.getRect(
      find
          .ancestor(
            of: find.text('Price: Low to High'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(lowToHighOption.top - highToLowOption.bottom, 10);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Pokemon'), findsOneWidget);
    expect(find.byKey(const Key('collection-filter-apply')), findsOneWidget);
    expect(
      tester
          .getBottomRight(find.byKey(const Key('collection-filter-apply')))
          .dy,
      lessThanOrEqualTo(884),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Collection filter gains global options after opening without losing the chosen sort',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);
      final repository = _PendingPagedCollectionMetadataRepository();
      await _pumpCollection(tester, repository: repository);

      await tester.tap(find.byKey(const Key('collection-filter-button')));
      await tester.pumpAndSettle();
      expect(find.text('Magic: The Gathering'), findsNothing);
      expect(find.text('French'), findsNothing);
      await tester.tap(find.text('Price: Low to High'));
      await tester.pump();

      repository.completeMetadata();
      await tester.pumpAndSettle();
      expect(find.text('Magic: The Gathering'), findsOneWidget);
      expect(find.text('French'), findsOneWidget);
      await tester.tap(find.byKey(const Key('collection-filter-apply')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectionPage)),
      );
      expect(
        container.read(collectionControllerProvider).selectedSort,
        CollectionSort.valueAsc,
      );
    },
  );

  testWidgets(
    'Collection filter stays open while a full refresh temporarily reloads its page',
    (tester) async {
      final repository = _PendingPagedCollectionMetadataRepository();
      await _pumpCollection(tester, repository: repository);
      repository.completeMetadata();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-filter-button')));
      await tester.pumpAndSettle();

      repository.blockNextPage();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectionPage)),
      );
      final refresh = container
          .read(collectionControllerProvider.notifier)
          .refresh();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('collection-filter-sheet-background')),
        findsOneWidget,
      );

      repository.releaseNextPage();
      await refresh;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Collection filter still shows owned Games from summary when the catalog request fails',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);
      final repository = _PendingPagedCollectionMetadataRepository(
        catalogFails: true,
      );
      await _pumpCollection(tester, repository: repository);
      repository.completeMetadata();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-filter-button')));
      await tester.pumpAndSettle();

      expect(find.text('Magic: The Gathering'), findsOneWidget);
      expect(find.text('French'), findsOneWidget);
    },
  );

  testWidgets(
    'Collection keeps the empty action when totals fail but base count is zero',
    (tester) async {
      final empty = _PendingPagedCollectionMetadataRepository(
        total: 0,
        baseCount: 0,
        summaryFails: true,
      );
      await _pumpCollection(tester, repository: empty);
      expect(find.text('Start your portfolio'), findsOneWidget);
      expect(find.text('No matching cards found.'), findsNothing);
    },
  );

  testWidgets(
    'Collection keeps no-match when totals fail but the folder owns cards',
    (tester) async {
      final noMatch = _PendingPagedCollectionMetadataRepository(
        total: 0,
        baseCount: 3,
        summaryFails: true,
      );
      await _pumpCollection(tester, repository: noMatch);
      expect(find.text('Start your portfolio'), findsNothing);
      expect(find.text('No matching cards found.'), findsOneWidget);
    },
  );

  testWidgets(
    'Collection filter keeps its handle and Apply fixed while options scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);

      await _pumpCollection(tester);
      await tester.tap(find.byKey(const Key('collection-filter-button')));
      await tester.pumpAndSettle();

      final apply = find.byKey(const Key('collection-filter-apply'));
      final handle = find.byKey(const Key('collection-filter-sheet-handle'));
      final sortOption = find.text('Price: Low to High');
      final applyBeforeScroll = tester.getRect(apply);
      final handleBeforeScroll = tester.getRect(handle);
      final sortBeforeScroll = tester.getRect(sortOption);

      await tester.drag(
        find.byKey(const Key('collection-filter-sheet')),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(apply), applyBeforeScroll);
      expect(tester.getRect(handle), handleBeforeScroll);
      expect(tester.getTopLeft(sortOption).dy, lessThan(sortBeforeScroll.top));
    },
  );

  testWidgets('Collection filter dismisses when its handle is dragged down', (
    tester,
  ) async {
    await _pumpCollection(tester);
    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('collection-filter-sheet-handle')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-filter-sheet-background')),
      findsNothing,
    );
  });

  testWidgets('Collection search does not regain focus after Filter closes', (
    tester,
  ) async {
    await _pumpCollection(tester);
    final editableText = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('collection-search-field')),
        matching: find.byType(EditableText),
      ),
    );
    await tester.tap(find.byKey(const Key('collection-search-field')));
    await tester.pump();
    expect(editableText.focusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();
    expect(editableText.focusNode.hasFocus, isFalse);

    await tester.drag(
      find.byKey(const Key('collection-filter-sheet-handle')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();

    expect(editableText.focusNode.hasFocus, isFalse);
  });

  testWidgets('Collection search unfocuses when tapping outside', (
    tester,
  ) async {
    await _pumpCollection(tester);
    final editableText = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('collection-search-field')),
        matching: find.byType(EditableText),
      ),
    );
    await tester.tap(find.byKey(const Key('collection-search-field')));
    await tester.pump();
    expect(editableText.focusNode.hasFocus, isTrue);

    await tester.tap(find.text('PORTFOLIO'));
    await tester.pump();

    expect(editableText.focusNode.hasFocus, isFalse);
  });

  testWidgets('Collection shows Portfolio summary and rows by default', (
    tester,
  ) async {
    await _pumpCollection(tester);

    expect(find.byKey(const Key('collection-pull-to-refresh')), findsOneWidget);
    expect(find.text('Collection'), findsWidgets);
    expect(
      find.byKey(const Key('collection-premium-page-header')),
      findsOneWidget,
    );
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(
      find.byKey(const Key('collection-folder-switch-icon')),
      findsOneWidget,
    );
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(find.text('4 cards'), findsOneWidget);
    expect(find.text('2 graded'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('collection-segmented-tabs'))).height,
      44,
    );
    _expectCollectionTabStyle(
      tester,
      label: 'Portfolio',
      backgroundColor: KandoColors.accent.withValues(alpha: 0.22),
      textColor: KandoColors.accent,
      fontWeight: FontWeight.w600,
    );
    _expectCollectionTabStyle(
      tester,
      label: 'Wishlist',
      backgroundColor: Colors.transparent,
      textColor: KandoColors.mutedText,
      fontWeight: FontWeight.w400,
    );
    expect(
      tester.getSize(find.byKey(const Key('collection-search-field'))).height,
      44,
    );
    final searchFieldRect = tester.getRect(
      find.byKey(const Key('collection-search-field')),
    );
    final searchIcon = find.descendant(
      of: find.byKey(const Key('collection-search-field')),
      matching: find.byIcon(Icons.search),
    );
    final filterIcon = find.descendant(
      of: find.byKey(const Key('collection-search-field')),
      matching: find.byIcon(Icons.tune),
    );
    expect(tester.getRect(searchIcon).left - searchFieldRect.left, 16);
    expect(searchFieldRect.right - tester.getRect(filterIcon).right, 16);
    expect(
      tester
          .getSize(find.byKey(const Key('collection-portfolio-summary')))
          .height,
      110,
    );
    final summaryRect = tester.getRect(
      find.byKey(const Key('collection-portfolio-summary')),
    );
    expect(
      tester
              .getTopLeft(find.byKey(const Key('collection-portfolio-label')))
              .dx -
          summaryRect.left,
      17,
    );
    expect(
      summaryRect.right -
          tester
              .getRect(find.byKey(const Key('collection-folder-button')))
              .right,
      17,
    );
    expect(
      tester.getSize(find.byKey(const Key('collection-folder-button'))).height,
      24,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('collection-portfolio-value-row')))
          .height,
      40,
    );
    final folderButtonWidth = tester
        .getSize(find.byKey(const Key('collection-folder-button')))
        .width;
    expect(folderButtonWidth, greaterThanOrEqualTo(70));
    expect(folderButtonWidth, lessThan(150));
    expect(
      tester.getSize(find.byKey(const Key('collection-hide-amount'))).height,
      24,
    );
    final totalFinder = find.byKey(const Key('collection-portfolio-total'));
    final totalRect = tester.getRect(totalFinder);
    final eyeRect = tester.getRect(
      find.byKey(const Key('collection-hide-amount')),
    );
    expect(
      totalRect.width,
      closeTo(_singleLineTextWidth(tester, totalFinder), 0.01),
    );
    expect(eyeRect.left - totalRect.right, 12);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('collection-portfolio-total')))
          .style
          ?.fontSize,
      24,
    );
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Pokemon · Obsidian Flames'), findsOneWidget);
    expect(find.text('Special Illustration Rare · 223'), findsOneWidget);
    expect(find.text('PSA 10 · Holofoil'), findsOneWidget);
    expect(find.text(r'$780.00'), findsOneWidget);
    expect(find.text('Qty: 1'), findsWidgets);
    _expectTextOrder(tester, const [
      'Charizard ex',
      'Pokemon · Obsidian Flames',
      'Special Illustration Rare · 223',
      'PSA 10 · Holofoil',
      r'$780.00',
    ]);
    _expectCollectionCardRowMatchesSearchField(
      tester,
      leftCardId: 'charizard-ex',
      rightCardId: 'umbreon-vmax',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Android Portfolio summary grows with large text while its pinned header contains it',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);

      await _pumpCollection(
        tester,
        platform: TargetPlatform.android,
        textScale: 1.2,
      );

      final summary = find.byKey(const Key('collection-portfolio-summary'));
      final header = find.byKey(const Key('collection-controls-header'));
      final folder = find.byKey(const Key('collection-folder-button'));
      final valueRow = find.byKey(const Key('collection-portfolio-value-row'));
      final total = find.byKey(const Key('collection-portfolio-total'));
      final portfolioLabel = find.byKey(
        const Key('collection-portfolio-label'),
      );
      final folderLabel = find.descendant(
        of: folder,
        matching: find.byType(Text),
      );
      expect(tester.getSize(summary).height, 124);
      expect(
        tester.getRect(summary).bottom,
        lessThanOrEqualTo(tester.getRect(header).bottom),
      );
      expect(tester.getSize(folder).height, 30);
      expect(
        tester.getRect(folderLabel).top,
        greaterThanOrEqualTo(tester.getRect(folder).top),
      );
      expect(
        tester.getRect(folderLabel).bottom,
        lessThanOrEqualTo(tester.getRect(folder).bottom),
      );
      expect(tester.getSize(valueRow).height, 48);
      expect(tester.getSize(portfolioLabel).height, 24);
      expect(
        tester.getRect(total).top,
        greaterThanOrEqualTo(tester.getRect(valueRow).top),
      );
      expect(
        tester.getRect(total).bottom,
        lessThanOrEqualTo(tester.getRect(valueRow).bottom),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('iOS Portfolio summary keeps its original fixed height', (
    tester,
  ) async {
    await _pumpCollection(tester, platform: TargetPlatform.iOS);

    expect(
      tester
          .getSize(find.byKey(const Key('collection-portfolio-summary')))
          .height,
      110,
    );
    expect(
      tester.getSize(find.byKey(const Key('collection-folder-button'))).height,
      24,
    );
  });

  testWidgets(
    'Collection folder control grows without shrinking a long label',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);

      await _pumpCollection(
        tester,
        repository: const _LongFolderCollectionRepository(),
      );

      expect(
        tester.getSize(find.byKey(const Key('collection-folder-button'))).width,
        150,
      );
      final label = tester.widget<Text>(find.text(_longFolderName));
      expect(label.style?.fontSize, 14);
      expect(label.overflow, TextOverflow.ellipsis);
      final folderRect = tester.getRect(
        find.byKey(const Key('collection-folder-button')),
      );
      final totalFinder = find.byKey(const Key('collection-portfolio-total'));
      final totalRect = tester.getRect(totalFinder);
      expect(totalRect.top - folderRect.bottom, greaterThanOrEqualTo(4));
      expect(
        tester.renderObject<RenderParagraph>(totalFinder).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Collection portfolio total ellipsizes only when it does not fit',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);

      await _pumpCollection(
        tester,
        repository: const _LongPortfolioValueCollectionRepository(),
      );

      final total = tester.widget<Text>(
        find.byKey(const Key('collection-portfolio-total')),
      );
      expect(total.data, r'$123,456,789.00');
      expect(total.overflow, TextOverflow.ellipsis);
      final totalFinder = find.byKey(const Key('collection-portfolio-total'));
      final totalRect = tester.getRect(totalFinder);
      final eyeRect = tester.getRect(
        find.byKey(const Key('collection-hide-amount')),
      );
      expect(
        totalRect.width,
        lessThan(_singleLineTextWidth(tester, totalFinder)),
      );
      expect(eyeRect.left - totalRect.right, 12);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Collection passes its 30D change through the generic card field',
    (tester) async {
      await _pumpCollection(tester);

      final tile = tester.widget<SearchCardTile>(
        find.ancestor(
          of: find.byKey(const Key('search-card-charizard-ex')),
          matching: find.byType(SearchCardTile),
        ),
      );

      expect(tile.card.changePercent, 8.10);
      expect(tile.card.changeText, '+8.10%');
    },
  );

  testWidgets('pull refresh keeps Collection content and shows one spinner', (
    tester,
  ) async {
    final repository = _BlockingRefreshCollectionRepository();
    await _pumpCollection(tester, repository: repository);

    final indicator = find.byKey(const Key('collection-pull-to-refresh'));
    final refresh = tester.state<RefreshIndicatorState>(indicator).show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.calls, 2);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    expect(find.byType(KandoLoadingBlock), findsNothing);
    expect(find.text('Charizard ex'), findsOneWidget);

    await repository.completeRefresh();
    await refresh;
    await tester.pumpAndSettle();

    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(find.text('Charizard ex'), findsOneWidget);
  });

  testWidgets('Collection controls share the pull-to-refresh scroll surface', (
    tester,
  ) async {
    await _pumpCollection(tester);

    final controls = find.byKey(const Key('collection-segmented-tabs'));
    expect(
      find.ancestor(
        of: controls,
        matching: find.byKey(const Key('collection-pull-to-refresh')),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: controls, matching: find.byType(CustomScrollView)),
      findsOneWidget,
    );
  });

  testWidgets(
    'Collection content uses the standard top spacing below the safe area',
    (tester) async {
      await _pumpCollection(tester);

      final header = tester.widget<Padding>(
        find.byKey(const Key('collection-fixed-header')),
      );
      final contentPadding = tester.widget<SliverPadding>(
        find.byKey(const Key('collection-content-padding')),
      );

      expect(
        header.padding,
        const EdgeInsets.fromLTRB(20, KandoLayout.mainTabTopPadding, 20, 16),
      );
      expect(contentPadding.padding, const EdgeInsets.fromLTRB(20, 0, 20, 24));
    },
  );

  testWidgets(
    'Collection builds only nearby cards so a large portfolio remains scrollable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);

      await _pumpCollection(
        tester,
        repository: const _LargeCollectionRepository(),
      );

      expect(find.byType(SearchCardTile).evaluate().length, lessThan(20));
      _expectCollectionCardRowMatchesSearchField(
        tester,
        leftCardId: 'bulk-0',
        rightCardId: 'bulk-1',
      );

      await tester.drag(
        find.byKey(const Key('collection-content-list')),
        const Offset(0, -10000),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-card-bulk-39')), findsOneWidget);
      expect(
        find.byKey(const Key('collection-controls-header')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'paged Collection keeps the two-column card geometry while loading more on scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);
      final repository = _PagedCollectionGridRepository();
      await _pumpCollection(tester, repository: repository);
      repository.completeMetadata();
      await tester.pumpAndSettle();

      _expectCollectionCardRowMatchesSearchField(
        tester,
        leftCardId: 'paged-0',
        rightCardId: 'paged-1',
      );
      expect(
        tester.getSize(find.byKey(const Key('search-card-paged-0'))).height,
        378,
      );
      await tester.drag(
        find.byKey(const Key('collection-content-list')),
        const Offset(0, -10000),
      );
      await tester.pumpAndSettle();

      expect(repository.requestedPages, [1, 2]);
      await tester.drag(
        find.byKey(const Key('collection-content-list')),
        const Offset(0, -10000),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-card-paged-44')), findsOneWidget);
      expect(
        find.byKey(const Key('collection-controls-header')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Free Folder limit opens Paywall without showing the create form',
    (tester) async {
      await _pumpCollection(tester, useRoutes: true);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-folder-add')));
      await tester.pumpAndSettle();

      expect(find.text('Subscription'), findsOneWidget);
      expect(
        find.byKey(const Key('collection-folder-name-sheet')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Collection header stays fixed because card browsing must preserve controls and portfolio context',
    (tester) async {
      await _pumpCollection(tester);

      final header = find.byKey(const Key('collection-fixed-header'));
      final controls = find.byKey(const Key('collection-controls-header'));
      final list = find.byKey(const Key('collection-content-list'));
      final firstCard = find.text('Charizard ex');
      final headerBeforeScroll = tester.getRect(header);
      final controlsBeforeScroll = tester.getRect(controls);
      final cardBeforeScroll = tester.getRect(firstCard);

      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.getRect(header), headerBeforeScroll);
      expect(tester.getRect(controls), controlsBeforeScroll);
      expect(tester.getTopLeft(firstCard).dy, lessThan(cardBeforeScroll.top));
    },
  );

  testWidgets('Collection restores the server currency preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const _PreferenceCollectionRepository(),
          ),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1,132.95'), findsOneWidget);
    expect(find.textContaining('709.80'), findsOneWidget);
    expect(find.text('+8.10%'), findsOneWidget);
  });

  testWidgets('page failure shows Refresh and restores collection content', (
    tester,
  ) async {
    final repository = _FailingThenSuccessfulCollectionRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(repository),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('collection-controls-header')), findsOneWidget);
    expect(find.byKey(const Key('collection-segmented-tabs')), findsOneWidget);
    expect(find.byKey(const Key('collection-search-field')), findsOneWidget);
    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(
      find.byKey(const Key('collection-failure-illustration')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('collection-failure-refresh')), findsOneWidget);
    expect(find.byType(KandoFailureBlock), findsNothing);
    expect(find.text('Collection'), findsWidgets);
    expect(repository.calls, 1);

    final searchFieldRect = tester.getRect(
      find.byKey(const Key('collection-search-field')),
    );
    final illustrationRect = tester.getRect(
      find.byKey(const Key('collection-failure-illustration')),
    );
    final refreshRect = tester.getRect(
      find.byKey(const Key('collection-failure-refresh')),
    );
    final illustration = tester.widget<SvgPicture>(
      find.byKey(const Key('collection-failure-illustration')),
    );
    expect(illustration.width, 100);
    expect(illustration.height, 100);
    expect(refreshRect.height, 44);
    expect(illustrationRect.top, greaterThan(searchFieldRect.bottom));

    await tester.tap(find.byKey(const Key('collection-failure-refresh')));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('folder picker changes Portfolio list', (tester) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-folder-select-sealed')));
    await tester.pumpAndSettle();

    expect(find.text('Sealed'), findsWidgets);
    expect(find.text('Evolving Skies Booster Box'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });

  testWidgets(
    'folder manager exposes Figma actions and creates a backend folder',
    (tester) async {
      await _pumpCollection(
        tester,
        subscriptionController: _ProCollectionSubscriptionController.new,
      );

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();

      expect(find.text('Select Portfolio'), findsOneWidget);
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        KandoColors.surface,
      );
      expect(find.text('DRAG AND DROP TO CHANGE ORDER'), findsOneWidget);
      expect(find.byKey(const Key('collection-folder-add')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('collection-folder-delete-main')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(const Key('collection-folder-edit-sealed')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('collection-folder-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('collection-folder-name-sheet')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byKey(const Key('collection-folder-name')),
        'Trade',
      );
      await tester.tap(find.byKey(const Key('collection-folder-name-save')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trade'), findsOneWidget);
      expect(
        find.byKey(const Key('collection-folder-default-folder-trade')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Create Folder keeps its input on server failure and blocks duplicate saves while pending',
    (tester) async {
      final repository = _BlockingCreateFolderRepository();
      await _pumpCollection(
        tester,
        repository: repository,
        subscriptionController: _ProCollectionSubscriptionController.new,
      );

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-folder-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('collection-folder-name')),
        'Trade',
      );
      await tester.tap(find.byKey(const Key('collection-folder-name-save')));
      await tester.pump();

      expect(repository.createCalls, 1);
      expect(find.text('SAVING'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('collection-folder-name-save')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('collection-folder-name')),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(
        find.byKey(const Key('collection-folder-name-save')),
        warnIfMissed: false,
      );
      expect(repository.createCalls, 1);

      repository.completeError('ENTITLEMENT_SYNC_REQUIRED', statusCode: 409);
      await tester.pumpAndSettle();
      expect(find.text('Trade'), findsOneWidget);
      expect(
        find.textContaining('Premium access is still syncing'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.byKey(const Key('kando-floating-toast')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const Key('kando-top-toast')),
                matching: find.byIcon(Icons.priority_high_rounded),
              ),
            )
            .color,
        KandoColors.errorText,
      );
      expect(find.text('SAVE'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('kando-top-toast')),
          matching: find.byTooltip('Close'),
        ),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'a concurrent Free Folder limit refreshes the list and opens Paywall instead of creating a third folder',
    (tester) async {
      final repository = _ConcurrentFolderLimitRepository();
      await _pumpCollection(tester, repository: repository, useRoutes: true);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-folder-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('collection-folder-name')),
        'Trade',
      );
      await tester.tap(find.byKey(const Key('collection-folder-name-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, 1);
      expect(repository.loadCalls, 2);
      expect(find.text('Subscription'), findsOneWidget);
      expect(
        find.byKey(const Key('collection-folder-name-sheet')),
        findsNothing,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.text('Subscription')),
      );
      expect(
        container.read(collectionControllerProvider).dashboard.folders.length,
        2,
      );
    },
  );

  testWidgets(
    'folder radio and label share a large target because portfolio switching must not require precise text taps',
    (tester) async {
      await _pumpCollection(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collection-folder-select-sealed')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Portfolio'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectionPage)),
      );
      expect(
        container.read(collectionControllerProvider).selectedFolder.id,
        'sealed',
      );
    },
  );

  testWidgets('folder delete confirmation opens as a bottom sheet', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-folder-delete-sealed')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-folder-delete-sheet')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byKey(const Key('collection-folder-delete-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-folder-delete-sealed')),
      findsNothing,
    );
  });

  testWidgets(
    'editing a folder keeps the sheet open with loading until rename succeeds',
    (tester) async {
      final repository = _BlockingFolderMutationRepository();
      await _pumpCollection(tester, repository: repository);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-folder-edit-sealed')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('collection-folder-name')),
        'Trade',
      );
      await tester.tap(find.byKey(const Key('collection-folder-name-save')));
      await tester.pump();

      expect(repository.renameCalls, 1);
      expect(
        find.byKey(const Key('collection-folder-name-sheet')),
        findsOneWidget,
      );
      expect(find.text('SAVING'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('collection-folder-name-save')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('collection-folder-name')),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(
        find.byKey(const Key('collection-folder-name-save')),
        warnIfMissed: false,
      );
      expect(repository.renameCalls, 1);

      repository.completeRename(name: 'Trade');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('collection-folder-name-sheet')),
        findsNothing,
      );
      expect(find.text('Trade'), findsOneWidget);
    },
  );

  testWidgets(
    'deleting a folder keeps confirmation open with loading until success',
    (tester) async {
      final repository = _BlockingFolderMutationRepository();
      await _pumpCollection(tester, repository: repository);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collection-folder-delete-sealed')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collection-folder-delete-confirm')),
      );
      await tester.pump();

      expect(repository.deleteCalls, 1);
      expect(
        find.byKey(const Key('collection-folder-delete-sheet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('collection-folder-delete-confirm')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('collection-folder-delete-confirm')),
        warnIfMissed: false,
      );
      expect(repository.deleteCalls, 1);

      repository.completeDelete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('collection-folder-delete-sheet')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('collection-folder-delete-sealed')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a failed folder delete keeps confirmation open and restores its action',
    (tester) async {
      final repository = _BlockingFolderMutationRepository();
      await _pumpCollection(tester, repository: repository);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collection-folder-delete-sealed')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collection-folder-delete-confirm')),
      );
      await tester.pump();

      repository.failDelete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('collection-folder-delete-sheet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('collection-folder-delete-confirm')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.text('DELETE'), findsOneWidget);
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(
        find.byKey(const Key('collection-folder-delete-sealed')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('kando-top-toast')),
          matching: find.byTooltip('Close'),
        ),
      );
      await tester.pump();
    },
  );

  testWidgets('Wishlist tab uses wishlist copy and hides quantity', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    _expectCollectionTabStyle(
      tester,
      label: 'Portfolio',
      backgroundColor: Colors.transparent,
      textColor: KandoColors.mutedText,
      fontWeight: FontWeight.w400,
    );
    _expectCollectionTabStyle(
      tester,
      label: 'Wishlist',
      backgroundColor: KandoColors.accent.withValues(alpha: 0.22),
      textColor: KandoColors.accent,
      fontWeight: FontWeight.w600,
    );
    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.text('One Piece Manga Luffy (JP)'), findsOneWidget);
    expect(find.text('Lorcana · The First Chapter'), findsOneWidget);
    expect(find.text('Enchanted Rare · 212'), findsOneWidget);
    expect(find.text('Raw · Near Mint (NM)'), findsNothing);
    expect(find.text('Enchanted'), findsOneWidget);
    expect(find.textContaining('Qty:'), findsNothing);
    expect(find.text(r'$480.00'), findsOneWidget);
    expect(find.text('+6.70%'), findsOneWidget);
    _expectCollectionCardRowMatchesSearchField(
      tester,
      leftCardId: 'lorcana-elsa',
      rightCardId: 'one-piece-luffy',
    );
  });

  testWidgets('search no-match state is distinct from empty state', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No matching cards found.'), findsOneWidget);
    expect(find.text('Try adjusting your search or filters.'), findsOneWidget);
    expect(find.byKey(const Key('collection-no-match-state')), findsOneWidget);
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(find.text('4 cards'), findsOneWidget);
    expect(find.text('2 graded'), findsOneWidget);
    expect(find.text('No cards in this portfolio yet.'), findsNothing);
  });

  testWidgets('amount toggle masks only the portfolio total', (tester) async {
    await _pumpCollection(tester);

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    expect(find.text(r'$780.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('collection-hide-amount')));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.text(hiddenMoneyText), findsOneWidget);
    expect(find.text(r'$1,245.00'), findsNothing);
    expect(find.text(r'$780.00'), findsOneWidget);
    expect(find.text('+8.10%'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.text(r'$780.00'), findsOneWidget);
  });

  testWidgets(
    'amount toggle stays local when the server preference endpoint fails',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const _FailingPreferenceCollectionRepository(),
            ),
          ],
          child: const _CollectionTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('collection-hide-amount')));
      await tester.pump();
      await tester.pump();

      expect(find.text(genericFailureToastText), findsNothing);
      expect(find.text(r'$1,245.00'), findsNothing);
      expect(find.text(hiddenMoneyText), findsOneWidget);
    },
  );

  testWidgets('filter sheet applies Game and Language filters', (tester) async {
    await _pumpCollection(tester);

    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();
    final sheet = tester.widget<DecoratedBox>(
      find.byKey(const Key('collection-filter-sheet-background')),
    );
    expect((sheet.decoration as BoxDecoration).color, KandoColors.surface);
    expect(find.text('Price: High to Low'), findsOneWidget);
    expect(find.text('Price: Low to High'), findsOneWidget);
    expect(find.text('LANGUAGE'), findsOneWidget);
    await tester.tap(find.text('Japanese').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('GAME / IP'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('GAME / IP'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pokemon'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Pokemon'), findsOneWidget);
    await tester.tap(find.byKey(const Key('collection-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pikachu Promo'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });

  testWidgets('Collection bottom navigation can return Home and Profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kando-tab-collection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in / Sign up'), findsOneWidget);
  });

  testWidgets('Collection bottom navigation can open Search', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets('Collection cards open the detail for their backend card ref', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('search-card-charizard-ex'));
    await tester.ensureVisible(card);
    await tester.drag(
      find.byKey(const Key('collection-content-list')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('Detail charizard-ex item-charizard'), findsOneWidget);
  });

  testWidgets(
    'Portfolio empty state actions open Scan and Search because empty collections must have recovery paths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            ..._searchOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
          ],
          child: const _CollectionTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      expect(find.text('Start your portfolio'), findsOneWidget);
      expect(find.text('Scan or search cards to track value'), findsOneWidget);
      expect(
        find.byKey(const Key('collection-portfolio-empty-illustration')),
        findsOneWidget,
      );
      final portfolioIllustration = tester.widget<Image>(
        find.byKey(const Key('collection-portfolio-empty-illustration')),
      );
      expect(
        (portfolioIllustration.image as AssetImage).assetName,
        'assets/collection/portfolio_empty_figma.png',
      );
      expect(portfolioIllustration.width, 83);
      expect(portfolioIllustration.height, 90);
      final scanIcon = tester.widget<SvgPicture>(
        find.descendant(
          of: find.widgetWithText(FilledButton, 'SCAN A CARD'),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (scanIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/empty_action_camera.svg',
      );
      expect(scanIcon.width, 16.0417);
      expect(scanIcon.height, 14.5417);
      final searchIcon = tester.widget<SvgPicture>(
        find.descendant(
          of: find.widgetWithText(FilledButton, 'SEARCH A CARD'),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (searchIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/empty_action_search.svg',
      );
      expect(searchIcon.width, 15.2707);
      expect(searchIcon.height, 15.8891);
      expect(
        tester
            .getBottomLeft(find.widgetWithText(FilledButton, 'SEARCH A CARD'))
            .dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('kando-tab-bar'))).dy,
        ),
      );

      await tester.ensureVisible(find.text('SCAN A CARD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SCAN A CARD'));
      await tester.pumpAndSettle();

      expect(find.text('ALIGN CARD HERE'), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            ..._searchOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
          ],
          child: const _CollectionTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      expect(find.text('Start your portfolio'), findsOneWidget);

      await tester.ensureVisible(find.text('SEARCH A CARD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SEARCH A CARD'));
      await tester.pumpAndSettle();

      expect(find.text('Search cards, sets, or characters'), findsOneWidget);
      expect(find.text('Squirtle'), findsOneWidget);
    },
  );

  testWidgets('Wishlist empty state matches the Figma recovery layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const _EmptyWishlistCollectionRepository(),
          ),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('Your wishlist is empty'), findsOneWidget);
    expect(find.text('Add cards you want to collect later'), findsOneWidget);
    expect(find.text('SEARCH CARDS'), findsOneWidget);
    final searchButton = find.widgetWithText(FilledButton, 'SEARCH CARDS');
    final searchButtonIcon = tester.widget<SvgPicture>(
      find.descendant(of: searchButton, matching: find.byType(SvgPicture)),
    );
    expect(
      searchButtonIcon.colorFilter,
      const ColorFilter.mode(KandoColors.ink, BlendMode.srcIn),
    );
    expect(
      tester
          .widget<FilledButton>(searchButton)
          .style
          ?.foregroundColor
          ?.resolve(const <WidgetState>{}),
      KandoColors.ink,
    );
    expect(
      find.byKey(const Key('collection-wishlist-empty-illustration')),
      findsOneWidget,
    );
    final wishlistIllustration = tester.widget<Image>(
      find.byKey(const Key('collection-wishlist-empty-illustration')),
    );
    expect(
      (wishlistIllustration.image as AssetImage).assetName,
      'assets/collection/wishlist_empty_figma.png',
    );
    expect(wishlistIllustration.width, 170);
    expect(wishlistIllustration.height, 100);
    expect(find.byKey(const Key('collection-portfolio-summary')), findsNothing);
  });

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kando-tab-scan')));
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });
}

void _expectCollectionTabStyle(
  WidgetTester tester, {
  required String label,
  required Color backgroundColor,
  required Color textColor,
  required FontWeight fontWeight,
}) {
  final labelFinder = find.text(label).first;
  final materialFinder = find
      .ancestor(of: labelFinder, matching: find.byType(Material))
      .first;
  final material = tester.widget<Material>(materialFinder);
  final text = tester.widget<Text>(labelFinder);

  expect(material.color, backgroundColor);
  expect(material.borderRadius, BorderRadius.circular(999));
  expect(text.style?.fontSize, 15);
  expect(text.style?.color, textColor);
  expect(text.style?.fontWeight, fontWeight);
}

Future<void> _pumpCollection(
  WidgetTester tester, {
  CollectionRepository repository = const MockCollectionRepository(),
  SubscriptionController Function()? subscriptionController,
  bool useRoutes = false,
  TargetPlatform? platform,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._localAuthOverrides(
          commercialPolicy: platform == TargetPlatform.android
              ? const AppCommercialPolicy(isAndroidFreeLaunch: true)
              : const AppCommercialPolicy(isAndroidFreeLaunch: false),
        ),
        collectionRepositoryProvider.overrideWithValue(repository),
        subscriptionControllerProvider.overrideWith(
          subscriptionController ?? _FreeCollectionSubscriptionController.new,
        ),
      ],
      child: useRoutes
          ? const _CollectionTestAppWithRoutes()
          : _CollectionTestApp(platform: platform, textScale: textScale),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectCollectionCardRowMatchesSearchField(
  WidgetTester tester, {
  required String leftCardId,
  required String rightCardId,
}) {
  final searchFieldRect = tester.getRect(find.byType(TextField).first);
  final leftCardRect = tester.getRect(
    find.byKey(Key('search-card-$leftCardId')),
  );
  final rightCardRect = tester.getRect(
    find.byKey(Key('search-card-$rightCardId')),
  );

  expect(leftCardRect.left, closeTo(searchFieldRect.left, 0.01));
  expect(rightCardRect.right, closeTo(searchFieldRect.right, 0.01));
  expect(rightCardRect.left - leftCardRect.right, closeTo(10, 0.01));
}

void _expectTextOrder(WidgetTester tester, List<String> labels) {
  for (var index = 1; index < labels.length; index++) {
    expect(
      tester.getRect(find.text(labels[index])).top,
      greaterThan(tester.getRect(find.text(labels[index - 1])).top),
      reason: 'Collection cards must preserve the Search Cards field order.',
    );
  }
}

double _singleLineTextWidth(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  final context = tester.element(finder);
  final painter = TextPainter(
    text: TextSpan(
      text: text.data,
      style: DefaultTextStyle.of(context).style.merge(text.style),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}

_localAuthOverrides({
  AppCommercialPolicy commercialPolicy = const AppCommercialPolicy(
    isAndroidFreeLaunch: false,
  ),
}) {
  final storage = InMemoryAuthStorage();
  return [
    appCommercialPolicyProvider.overrideWithValue(commercialPolicy),
    authStorageProvider.overrideWithValue(storage),
    authRepositoryProvider.overrideWithValue(
      LocalPlaceholderAuthRepository(storage),
    ),
    currencyRateApiProvider.overrideWithValue(const _TestCurrencyRateApi()),
    portfolioAmountHiddenStorageProvider.overrideWithValue(
      InMemoryPortfolioAmountHiddenStorage(),
    ),
  ];
}

class _TestCurrencyRateApi implements CurrencyRateApi {
  const _TestCurrencyRateApi();

  @override
  Future<double> loadUsdRate(String targetCurrency) async => 0.91;
}

class _CollectionTestApp extends StatelessWidget {
  const _CollectionTestApp({this.platform, this.textScale = 1});

  final TargetPlatform? platform;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: platform == null ? null : ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const CollectionPage(),
    );
  }
}

class _CollectionTestAppWithRoutes extends StatelessWidget {
  const _CollectionTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/collection',
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
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
          GoRoute(
            path: '/cards/:cardId',
            builder: (context, state) => Scaffold(
              body: Text(
                'Detail ${state.pathParameters['cardId']} '
                '${state.uri.queryParameters['item_id']}',
              ),
            ),
          ),
          GoRoute(
            path: '/subscription',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Subscription'))),
          ),
        ],
      ),
    );
  }
}

class _ProCollectionSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() => const SubscriptionState(isPro: true);

  @override
  Future<EntitlementReconciliationResult> reconcileServerEntitlement() async {
    return EntitlementReconciliationResult.verificationUnavailable;
  }
}

class _FreeCollectionSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.free);
}

class _FailingThenSuccessfulCollectionRepository
    implements CollectionRepository {
  var calls = 0;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock collection unavailable');
    }
    return const MockCollectionRepository().loadDashboard(session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingCollectionRepository extends MockCollectionRepository {
  final _dashboard = Completer<CollectionDashboard>();
  var calls = 0;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) {
    calls += 1;
    return _dashboard.future;
  }
}

const _longFolderName = 'International Tournament Collection Archive';

class _LongFolderCollectionRepository extends MockCollectionRepository {
  const _LongFolderCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(
      folders: [
        for (final folder in dashboard.folders)
          folder.id == 'main' ? folder.copyWith(name: _longFolderName) : folder,
      ],
    );
  }
}

class _LargeCollectionRepository extends MockCollectionRepository {
  const _LargeCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(
      portfolioItems: [
        for (var index = 0; index < 40; index++)
          CollectionItem(
            id: 'bulk-$index',
            cardRef: 'bulk-$index',
            folderId: 'main',
            name: 'Bulk Card $index',
            setName: 'Bulk Set',
            number: '#$index',
            rarity: 'Rare',
            game: 'Pokemon',
            language: 'English',
            finish: 'Normal',
            grader: 'Raw',
            condition: 'Near Mint',
            grade: null,
            quantity: 1,
            marketValueUsd: 1,
            previous30dPriceUsd: 1,
            addedAtSort: 40 - index,
          ),
      ],
    );
  }
}

class _PendingPagedCollectionMetadataRepository extends MockCollectionRepository
    implements CollectionPagedRepository, CollectionGameCatalogRepository {
  _PendingPagedCollectionMetadataRepository({
    this.total = 3,
    this.baseCount = 3,
    this.summaryFails = false,
    this.catalogFails = false,
  });

  final int total;
  final int baseCount;
  final bool summaryFails;
  final bool catalogFails;
  final _summary = Completer<CollectionSummaryResult>();
  final _games = Completer<List<String>>();
  Completer<void>? _nextPage;

  @override
  bool get supportsPaging => true;

  @override
  Future<CollectionPageResult> loadPage(
    AuthSession session, {
    required CollectionTab tab,
    String? folderId,
    String query = '',
    CollectionSort sort = CollectionSort.newest,
    int page = 1,
    Set<String> games = const {},
    Set<String> languages = const {},
    List<String> performanceItemIds = const [],
  }) async {
    await _nextPage?.future;
    final source = await super.loadDashboard(session);
    return CollectionPageResult(
      dashboard: source.copyWith(
        portfolioItems: total == 0
            ? const []
            : source.portfolioItems
                  .where((item) => item.folderId == 'main')
                  .toList(),
        wishlistItems: const [],
      ),
      folderId: folderId ?? 'main',
      total: total,
      baseCount: baseCount,
      page: page,
      pageSize: 40,
    );
  }

  @override
  Future<CollectionSummaryResult> loadSummary(AuthSession session) =>
      summaryFails
      ? Future.error(StateError('summary unavailable'))
      : _summary.future;

  @override
  Future<List<String>> loadGameOptions() => catalogFails
      ? Future.error(StateError('games unavailable'))
      : _games.future;

  void completeMetadata() {
    _summary.complete(
      const CollectionSummaryResult(
        folders: {
          'main': CollectionFolderTotals(
            folderId: 'main',
            itemCount: 3,
            cardCount: 4,
            gradedCount: 2,
            totalValueUsd: 1245,
            languages: ['English', 'French'],
          ),
        },
        wishlistCount: 0,
        wishlistLanguages: [],
        games: ['Pokemon', 'Magic: The Gathering'],
      ),
    );
    _games.complete(const ['Pokemon', 'Magic: The Gathering']);
  }

  void blockNextPage() => _nextPage = Completer<void>();

  void releaseNextPage() {
    _nextPage?.complete();
    _nextPage = null;
  }
}

class _PagedCollectionGridRepository
    extends _PendingPagedCollectionMetadataRepository {
  final requestedPages = <int>[];

  @override
  Future<CollectionPageResult> loadPage(
    AuthSession session, {
    required CollectionTab tab,
    String? folderId,
    String query = '',
    CollectionSort sort = CollectionSort.newest,
    int page = 1,
    Set<String> games = const {},
    Set<String> languages = const {},
    List<String> performanceItemIds = const [],
  }) async {
    requestedPages.add(page);
    final source = await const MockCollectionRepository().loadDashboard(
      session,
    );
    final items = [
      for (
        var index = (page - 1) * 40;
        index < page * 40 && index < 45;
        index++
      )
        CollectionItem(
          id: 'paged-$index',
          cardRef: 'paged-$index',
          folderId: 'main',
          name: 'Paged $index',
          setName: 'Set',
          number: '#$index',
          rarity: 'Rare',
          game: 'Pokemon',
          language: 'English',
          finish: 'Normal',
          grader: 'Raw',
          condition: 'Near Mint',
          grade: null,
          quantity: 1,
          marketValueUsd: 1,
          previous30dPriceUsd: 1,
          addedAtSort: 45 - index,
        ),
    ];
    return CollectionPageResult(
      dashboard: source.copyWith(
        portfolioItems: items,
        wishlistItems: const [],
      ),
      folderId: folderId ?? 'main',
      total: 45,
      baseCount: 45,
      page: page,
      pageSize: 40,
    );
  }
}

class _LongPortfolioValueCollectionRepository extends MockCollectionRepository {
  const _LongPortfolioValueCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    return CollectionDashboard(
      folders: const [
        CollectionFolder(id: 'main', name: 'Main', isDefault: true),
      ],
      portfolioItems: const [
        CollectionItem(
          id: 'item-long-value',
          cardRef: 'long-value-card',
          folderId: 'main',
          name: 'Long Value Card',
          setName: 'Test Set',
          number: '#001',
          rarity: 'Rare',
          game: 'Pokemon',
          language: 'English',
          finish: 'Holofoil',
          grader: 'Raw',
          condition: 'Near Mint',
          grade: null,
          quantity: 1,
          marketValueUsd: 123456789,
          previous30dPriceUsd: 123456789,
          increasePercent: null,
          addedAtSort: 1,
        ),
      ],
      wishlistItems: const [],
    );
  }
}

class _BlockingRefreshCollectionRepository extends MockCollectionRepository {
  final _refresh = Completer<CollectionDashboard>();
  AuthSession? _session;
  var calls = 0;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) {
    _session = session;
    calls += 1;
    if (calls == 1) return super.loadDashboard(session);
    return _refresh.future;
  }

  Future<void> completeRefresh() async {
    _refresh.complete(await super.loadDashboard(_session!));
  }
}

class _PreferenceCollectionRepository extends MockCollectionRepository {
  const _PreferenceCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(currencyCode: 'EUR');
  }
}

class _FailingPreferenceCollectionRepository extends MockCollectionRepository {
  const _FailingPreferenceCollectionRepository();

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) {
    throw StateError('Preference backend rejected the mutation.');
  }
}

class _BlockingCreateFolderRepository extends MockCollectionRepository {
  final createCompleter = Completer<CollectionFolder>();
  var createCalls = 0;

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  }) {
    createCalls += 1;
    return createCompleter.future;
  }

  void completeError(String code, {int? statusCode}) {
    createCompleter.completeError(
      PortfolioApiException('rejected', code: code, statusCode: statusCode),
    );
  }
}

class _BlockingFolderMutationRepository extends MockCollectionRepository {
  final _renameCompleter = Completer<CollectionFolder>();
  final _deleteCompleter = Completer<void>();
  var renameCalls = 0;
  var deleteCalls = 0;

  @override
  Future<CollectionFolder> renameFolder(
    AuthSession session,
    String folderId,
    String name,
  ) {
    renameCalls += 1;
    return _renameCompleter.future;
  }

  @override
  Future<void> deleteFolder(AuthSession session, String folderId) {
    deleteCalls += 1;
    return _deleteCompleter.future;
  }

  void completeRename({required String name}) {
    _renameCompleter.complete(
      CollectionFolder(id: 'sealed', name: name, isDefault: false),
    );
  }

  void completeDelete() => _deleteCompleter.complete();

  void failDelete() {
    _deleteCompleter.completeError(StateError('delete failed'));
  }
}

class _ConcurrentFolderLimitRepository extends MockCollectionRepository {
  var loadCalls = 0;
  var createCalls = 0;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    loadCalls += 1;
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(
      folders: dashboard.folders.take(loadCalls == 1 ? 1 : 2).toList(),
    );
  }

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  }) {
    createCalls += 1;
    throw const PortfolioApiException(
      'Premium is required.',
      code: 'PREMIUM_REQUIRED',
      statusCode: 403,
    );
  }
}

class _EmptyWishlistCollectionRepository extends MockCollectionRepository {
  const _EmptyWishlistCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(wishlistItems: const []);
  }
}
