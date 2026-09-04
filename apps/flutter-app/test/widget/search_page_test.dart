import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_models.dart';
import 'package:kando_app/features/card_detail/card_detail_page.dart';
import 'package:kando_app/features/card_detail/card_detail_repository.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_card_tile.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/pending_collection.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/kando_bottom_sheet_page.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_card_detail_repository.dart';
import '../support/mock_collection_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  testWidgets('Search shows Cards tab with Pokemon results by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-premium-page-header')), findsOneWidget);
    expect(find.text('Search'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-field')),
        matching: find.byKey(const Key('search-premium-top-entry')),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('search-pull-to-refresh')), findsOneWidget);
    expect(find.text('Pokemon'), findsOneWidget);
    expect(find.text('Cards'), findsWidgets);
    expect(find.text('Sets'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Squirtle')).style?.fontFamily,
      'Fraunces',
    );
    expect(find.text(r'$32.13'), findsOneWidget);
    expect(find.text('+4.76%'), findsOneWidget);
    expect(find.text('+8.10%'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('search-field'))).height, 44);
    expect(
      tester.getSize(find.byKey(const Key('search-game-selector'))).height,
      44,
    );
    expect(tester.getSize(find.byKey(const Key('search-tabs'))).height, 44);
    final viewportWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getRect(find.byKey(const Key('search-field'))).left, 20);
    expect(
      tester.getRect(find.byKey(const Key('search-field'))).right,
      viewportWidth - 20,
    );
    expect(
      tester.getRect(find.byKey(const Key('search-card-squirtle'))).left,
      tester.getRect(find.byKey(const Key('search-field'))).left,
    );
    expect(
      tester.getRect(find.byKey(const Key('search-card-charizard-ex'))).right,
      tester.getRect(find.byKey(const Key('search-field'))).right,
    );
    final squirtlePriceRow = find.byKey(const Key('search-price-row-squirtle'));
    final squirtlePrice = find.descendant(
      of: squirtlePriceRow,
      matching: find.text(r'$32.13'),
    );
    final squirtleChange = find.descendant(
      of: squirtlePriceRow,
      matching: find.text('+4.76%'),
    );
    expect(
      tester.getRect(squirtlePrice).right,
      closeTo(tester.getRect(squirtlePriceRow).right, 0.01),
    );
    expect(
      tester.getRect(squirtleChange).right,
      closeTo(tester.getRect(squirtlePriceRow).right, 0.01),
    );
    expect(find.text('Qty: 0'), findsWidgets);
    expect(find.byKey(const Key('search-collect-squirtle')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-collect-squirtle')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('search-wishlist-charizard-ex')), findsNothing);
    expect(find.byKey(const Key('search-wishlist-squirtle')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-collect-charizard-ex')),
        matching: find.byTooltip('Add another item'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('search-collect-charizard-ex')),
        matching: find.byKey(
          const ValueKey('assets/search/collection_off.svg'),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Collect'), findsNothing);

    ProviderScope.containerOf(tester.element(find.byType(SearchPage)))
        .read(selectedCurrencyProvider.notifier)
        .select(AppCurrency.eur.withUsdRate(0.91));
    await tester.pump();

    expect(find.text('€29.24'), findsOneWidget);
    expect(find.text(r'$32.13'), findsNothing);
  });

  testWidgets('pull refresh keeps Search content and shows one spinner', (
    tester,
  ) async {
    final repository = _BlockingRefreshSearchRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [searchRepositoryProvider.overrideWithValue(repository)],
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    final indicator = find.byKey(const Key('search-pull-to-refresh'));
    final refresh = tester.state<RefreshIndicatorState>(indicator).show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.loadCatalogCalls, 1);
    expect(repository.searchCardsCalls, 1);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    expect(find.byType(KandoLoadingBlock), findsNothing);
    expect(find.text('Squirtle'), findsOneWidget);

    await repository.completeRefresh();
    await refresh;
    await tester.pumpAndSettle();

    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets(
    'Search content uses the standard top spacing below the safe area',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _searchOverrides(),
          child: const _SearchTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      final header = tester.widget<Padding>(
        find.byKey(const Key('search-fixed-header')),
      );

      expect(
        header.padding,
        const EdgeInsets.fromLTRB(20, KandoLayout.mainTabTopPadding, 20, 16),
      );
    },
  );

  testWidgets(
    'Search controls stay pinned while results move because filters must remain available during browsing',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _searchOverrides(),
          child: const _SearchTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      final scrollView = find.byType(CustomScrollView);
      await tester.drag(scrollView, const Offset(0, -80));
      await tester.pump();

      final searchTop = tester
          .getTopLeft(find.byKey(const Key('search-field')))
          .dy;
      final gameTop = tester
          .getTopLeft(find.byKey(const Key('search-game-selector')))
          .dy;
      final tabsTop = tester
          .getTopLeft(find.byKey(const Key('search-tabs')))
          .dy;
      final cardTop = tester
          .getTopLeft(find.byKey(const Key('search-card-squirtle')))
          .dy;

      await tester.drag(scrollView, const Offset(0, -80));
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(const Key('search-field'))).dy,
        searchTop,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('search-game-selector'))).dy,
        gameTop,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('search-tabs'))).dy,
        tabsTop,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('search-card-squirtle'))).dy,
        lessThan(cardTop),
      );
    },
  );

  testWidgets(
    'Search renders backend card art because Figma cards are not placeholders',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchRepositoryProvider.overrideWithValue(
              const _ImageSearchRepository(),
            ),
          ],
          child: const _SearchTestApp(),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is NetworkImage,
        ),
        findsOneWidget,
      );
      final imageContainer = find.byKey(
        const Key('search-card-image-container-9359'),
      );
      final cardTile = find.byKey(const Key('search-card-9359'));
      final imageClip = find.byKey(const Key('search-card-image-clip-9359'));
      final actionButton = find.byKey(const Key('search-collect-9359'));
      final imageDecoration =
          tester.widget<Container>(imageContainer).decoration as BoxDecoration;
      expect(imageDecoration.border, isNull);
      expect(
        tester.getRect(imageContainer).top,
        tester.getRect(cardTile).top + 14,
      );
      expect(tester.getSize(cardTile), const Size(170, 378));
      expect(tester.getSize(imageContainer).height, 186);
      expect(
        tester.getRect(actionButton).top,
        tester.getRect(imageContainer).top,
      );
      expect(
        tester.widget<ClipRRect>(imageClip).borderRadius,
        BorderRadius.circular(6),
      );
      expect(find.text('Escape Artist'), findsOneWidget);
      expect(find.text('Escape Artist (English)'), findsNothing);
      expect(find.text('Pikachu (JP)'), findsOneWidget);
      expect(find.text('Psyduck (CN)'), findsOneWidget);
      expect(find.text('TCG · Odyssey'), findsOneWidget);
      expect(find.text('Common · 123'), findsOneWidget);
      expect(
        find.descendant(of: cardTile, matching: find.text('Normal')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cardTile, matching: find.text('Qty: 0')),
        findsOneWidget,
      );
      expect(find.text('Near Mint (NM)'), findsNothing);
      expect(find.byIcon(Icons.trending_up), findsNothing);
      expect(
        tester.getRect(imageClip).top,
        greaterThan(tester.getRect(imageContainer).top),
        reason: 'The image must not cover the card frame top edge.',
      );
      expect(
        tester.getRect(imageClip).bottom,
        lessThan(tester.getRect(imageContainer).bottom),
        reason: 'The image must not cover the card frame bottom edge.',
      );
    },
  );

  testWidgets('page failure shows Refresh and restores search content', (
    tester,
  ) async {
    final repository = _FailingThenSuccessfulSearchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [searchRepositoryProvider.overrideWithValue(repository)],
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-content-list')), findsOneWidget);
    expect(find.byType(KandoFailureBlock), findsOneWidget);
    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
    expect(find.byKey(const Key('search-no-results')), findsNothing);
    expect(find.text('Search'), findsWidgets);
    expect(repository.calls, 1);

    await tester.tap(find.text(refreshText));
    await tester.pumpAndSettle();

    expect(find.text('Squirtle'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets(
    'next page failure keeps cards and offers a local retry because partial Search results remain usable',
    (tester) async {
      final repository = _FailingPaginatedSearchRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [searchRepositoryProvider.overrideWithValue(repository)],
          child: const _SearchTestApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
      );
      final controller = container.read(searchControllerProvider.notifier);

      await controller.loadNextCardPage();
      await tester.pumpAndSettle();

      expect(repository.requestedPages, [2]);
      expect(
        container.read(searchControllerProvider).visibleCards,
        hasLength(40),
      );
      expect(find.text('Card 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('search-retry-card-page')),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('search-retry-card-page')), findsOneWidget);

      final retry = find.byKey(const Key('search-retry-card-page'));
      await tester.pumpAndSettle();
      expect(repository.requestedPages, [2]);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(repository.requestedPages, [2, 2]);
      expect(
        container.read(searchControllerProvider).visibleCards,
        hasLength(41),
      );
      expect(find.text('Card 41'), findsOneWidget);
      expect(find.byKey(const Key('search-retry-card-page')), findsNothing);
    },
  );

  testWidgets(
    'Search lazily builds card results so route transitions do not relayout every loaded card',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchRepositoryProvider.overrideWithValue(
              _FailingPaginatedSearchRepository(),
            ),
          ],
          child: const _SearchTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
      );
      expect(
        container.read(searchControllerProvider).visibleCards,
        hasLength(40),
      );
      expect(find.byType(SearchCardTile).evaluate().length, lessThan(40));
    },
  );

  testWidgets('search and clear update current tab results', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'charizard');
    await tester.pumpAndSettle();
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Squirtle'), findsNothing);

    await tester.tap(find.byKey(const Key('search-clear-button')));
    await tester.pumpAndSettle();
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets('tapping outside the search field dismisses its focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-field')));
    await tester.enterText(find.byKey(const Key('search-field')), 'charizard');
    final searchFocusNode = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(searchFocusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('search-game-selector')));
    await tester.pumpAndSettle();

    expect(searchFocusNode.hasFocus, isFalse);
  });

  testWidgets('search results wait for the controller debounce', (
    tester,
  ) async {
    final repository = _TrackingSearchRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [searchRepositoryProvider.overrideWithValue(repository)],
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();
    final initialCardCalls = repository.cardCalls;

    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'charizard');
    await tester.pump(
      Duration(milliseconds: searchDebounceDuration.inMilliseconds ~/ 2),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    expect(container.read(searchControllerProvider).searchText, 'charizard');
    expect(repository.cardCalls, initialCardCalls);

    await tester.pump(
      Duration(milliseconds: searchDebounceDuration.inMilliseconds ~/ 2),
    );
    await tester.pump();

    expect(container.read(searchControllerProvider).searchText, 'charizard');
    expect(repository.cardCalls, initialCardCalls + 1);
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Squirtle'), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets(
    'Cards query failure keeps Sets available and Refresh retries Cards',
    (tester) async {
      final repository = _FailingCardSearchRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [searchRepositoryProvider.overrideWithValue(repository)],
          child: const _SearchTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'squirtle');
      await tester.pump(searchDebounceDuration);
      await tester.pump();
      expect(find.text(noContentAvailableText), findsOneWidget);
      expect(find.text(refreshText), findsOneWidget);
      expect(find.text('Sets'), findsOneWidget);

      await tester.tap(find.text('Sets'));
      await tester.pumpAndSettle();
      expect(find.text('Mega Evolution Promos'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);

      await tester.tap(find.text('Cards').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(refreshText));
      await tester.pump(searchDebounceDuration);
      await tester.pump();

      expect(repository.cardCalls, 2);
      expect(find.text('Squirtle'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);
    },
  );

  testWidgets('Sets tab keeps its own search state', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
      listen: false,
    );
    container
        .read(pendingCollectionProvider.notifier)
        .add(
          const PendingCollectionCard(
            id: 'pending-search-tabs',
            name: 'Pending card',
            game: 'Pokemon',
            setName: 'Base Set',
            metadataLine: '#1',
            variantLine: 'Normal',
          ),
        );
    await tester.pump();
    expect(find.byKey(const Key('pending-collection-notice')), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'charizard');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sets'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pending-collection-notice')), findsOneWidget);
    expect(find.text('Mega Evolution Promos'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Mega Evolution Promos')).style?.fontFamily,
      'Fraunces',
    );
    expect(
      tester
          .getSize(find.byKey(const Key('search-set-mega-evolution-promos')))
          .width,
      350,
    );
    expect(
      tester.getSize(
        find.byKey(const Key('search-set-image-mega-evolution-promos')),
      ),
      const Size(50, 50),
    );
    final setSubtitle = tester.widget<Text>(
      find.text('Pokemon promotional cards'),
    );
    expect(setSubtitle.style?.fontSize, 10);
    expect(setSubtitle.style?.color, const Color(0xFF92927D));
    await tester.enterText(find.byType(TextFormField), 'flames');
    await tester.pumpAndSettle();
    expect(find.text('Obsidian Flames'), findsOneWidget);

    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pending-collection-notice')), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);
  });

  testWidgets('Game selector refreshes cards', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchRepositoryProvider.overrideWithValue(
            const _CurrentGameSearchRepository(),
          ),
        ],
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pokemon'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-game-filter-sheet')), findsOneWidget);
    final sheet = tester.widget<Container>(
      find.byKey(const Key('search-game-filter-sheet')),
    );
    expect((sheet.decoration! as BoxDecoration).color, KandoColors.surface);
    expect(
      tester.getRect(find.byKey(const Key('search-game-filter-sheet'))).bottom,
      844,
    );
    expect(
      tester.getRect(find.byKey(const Key('search-game-apply-filter'))).bottom,
      lessThanOrEqualTo(844 - 34),
    );
    expect(find.text('GAME / IP'), findsOneWidget);
    expect(find.text('APPLY FILTERS'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-game-filter-lorcana')));
    await tester.pump();
    expect(find.text('Squirtle'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-game-apply-filter')));
    await tester.pumpAndSettle();

    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.text('Squirtle'), findsNothing);

    await tester.enterText(find.byKey(const Key('search-field')), 'Elsa');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), '');
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    expect(
      container.read(searchControllerProvider).selectedGame.label,
      'Lorcana',
    );
    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.byKey(const Key('search-no-results')), findsNothing);
  });

  testWidgets(
    'switching game shows loading instead of empty state because results are still in flight',
    (tester) async {
      final repository = _BlockingGameSearchRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [searchRepositoryProvider.overrideWithValue(repository)],
          child: const _SearchTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pokemon'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-game-filter-lorcana')));
      await tester.tap(find.byKey(const Key('search-game-apply-filter')));
      await tester.pump();

      expect(find.byKey(const Key('search-results-loading')), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);
      expect(find.byKey(const Key('search-empty-refresh')), findsNothing);
      expect(find.byKey(const Key('search-no-results')), findsNothing);
      expect(find.byKey(const Key('search-failure')), findsNothing);

      await repository.completeCardSearch();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-results-loading')), findsNothing);
      expect(find.text('Lorcana Elsa'), findsOneWidget);
    },
  );

  testWidgets('Collect creates a pending item without changing persisted Qty', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-wishlist-squirtle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('assets/search/wishlist_on.svg')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);

    final collectButton = find.byKey(const Key('search-collect-squirtle'));
    await tester.ensureVisible(collectButton);
    await tester.pumpAndSettle();
    await tester.tap(collectButton);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('search-card-squirtle')),
        matching: find.byTooltip('Pending collection item'),
      ),
      findsOneWidget,
    );
    expect(find.text('Collected'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-card-squirtle')),
        matching: find.byKey(const ValueKey('assets/search/collection_on.svg')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('search-card-squirtle')),
        matching: find.text('Qty: 0'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assets/search/wishlist_on.svg')),
      findsNothing,
    );
    expect(find.byKey(const Key('search-wishlist-squirtle')), findsNothing);
    expect(find.text('1 card waiting for details'), findsOneWidget);
    expect(find.text('Tap to Review and edit it'), findsOneWidget);
    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
  });

  testWidgets('Search card action buttons do not open CardDetail', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-wishlist-squirtle')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byKey(const Key('card-detail-hero')), findsNothing);
    expect(
      find.byKey(const ValueKey('assets/search/wishlist_on.svg')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('search-collect-squirtle')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byKey(const Key('card-detail-hero')), findsNothing);
    expect(find.byKey(const Key('search-wishlist-squirtle')), findsNothing);
  });

  testWidgets(
    'gray collect button starts another pending Item without changing saved Qty',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      final collect = find.byKey(const Key('search-collect-charizard-ex'));
      await tester.tap(collect);
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.byKey(const Key('card-detail-hero')), findsNothing);
      expect(find.text('1 card waiting for details'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('search-card-charizard-ex')),
          matching: find.text('Qty: 1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('search-wishlist-charizard-ex')),
        findsNothing,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
        listen: false,
      );
      expect(container.read(pendingCollectionProvider).single.quantity, 1);

      await tester.tap(collect);
      await tester.pumpAndSettle();
      final pendingItems = container.read(pendingCollectionProvider);
      expect(pendingItems, hasLength(2));
      expect(pendingItems.map((item) => item.quantity), everyElement(1));
      expect(find.text('2 cards waiting for details'), findsOneWidget);
      expect(
        container
            .read(searchControllerProvider)
            .cardById('charizard-ex')
            .quantity,
        1,
      );
    },
  );

  testWidgets('the twenty-first collect tap shows the PRD limit warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
      listen: false,
    );
    for (var index = 0; index < pendingCollectionItemLimit; index++) {
      container
          .read(pendingCollectionProvider.notifier)
          .add(
            PendingCollectionCard(
              id: 'queued-$index',
              name: 'Queued $index',
              game: 'Pokemon',
              setName: 'Set',
              metadataLine: '#$index',
              variantLine: 'Normal',
            ),
          );
    }
    await tester.pump();

    await tester.tap(find.byKey(const Key('search-collect-squirtle')));
    await tester.pump();

    expect(container.read(pendingCollectionProvider), hasLength(20));
    expect(find.text('You can add up to 20 cards at a time.'), findsOneWidget);
    await tester.pump(kandoTopToastDuration);
    await tester.pump();
  });

  testWidgets('repeated unowned card clicks create separate pending Items', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final collect = find.byKey(const Key('search-collect-squirtle'));
    await tester.tap(collect);
    await tester.tap(collect);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
      listen: false,
    );
    final pendingItems = container.read(pendingCollectionProvider);
    expect(pendingItems, hasLength(2));

    await tester.tap(find.byKey(const Key('pending-collection-notice')));
    await tester.pumpAndSettle();

    final reviewSheet = find.byKey(const Key('card-detail-add-item-sheet'));
    expect(reviewSheet, findsOneWidget);
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getSize(reviewSheet).height,
      closeTo(viewportHeight * 0.93, 0.01),
    );
    expect(tester.getRect(reviewSheet).bottom, closeTo(viewportHeight, 0.01));
    expect(
      tester.getRect(find.byKey(const Key('card-detail-item-submit'))).bottom,
      lessThanOrEqualTo(viewportHeight - 34),
    );
    expect(
      find.byKey(const Key('pending-collection-card-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('pending-collection-item-${pendingItems[0].id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('pending-collection-item-${pendingItems[1].id}')),
      findsOneWidget,
    );

    Finder field(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(TextFormField),
    );
    String displayedText(String key) {
      final editable = find.descendant(
        of: field(key),
        matching: find.byType(EditableText),
      );
      return tester.widget<EditableText>(editable).controller.text;
    }

    Future<void> enterField(String key, String value) async {
      final target = field(key);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.enterText(target, value);
    }

    expect(displayedText('card-detail-item-quantity'), '1');
    await enterField('card-detail-item-quantity', '3');
    await enterField('card-detail-item-purchase-price', '12.34');
    await enterField('card-detail-item-notes', 'first card note');

    await tester.tap(
      find.byKey(Key('pending-collection-item-${pendingItems[1].id}')),
    );
    await tester.pumpAndSettle();
    expect(
      [
        displayedText('card-detail-item-quantity'),
        displayedText('card-detail-item-purchase-price'),
        displayedText('card-detail-item-notes'),
      ],
      ['1', '', ''],
    );
    await enterField('card-detail-item-quantity', '4');
    await enterField('card-detail-item-purchase-price', '56.78');
    await enterField('card-detail-item-notes', 'second card note');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('pending-collection-notice')));
    await tester.pumpAndSettle();

    expect(
      [
        displayedText('card-detail-item-quantity'),
        displayedText('card-detail-item-purchase-price'),
        displayedText('card-detail-item-notes'),
      ],
      ['3', '12.34', 'first card note'],
    );
    await tester.tap(
      find.byKey(Key('pending-collection-item-${pendingItems[1].id}')),
    );
    await tester.pumpAndSettle();
    expect(
      [
        displayedText('card-detail-item-quantity'),
        displayedText('card-detail-item-purchase-price'),
        displayedText('card-detail-item-notes'),
      ],
      ['4', '56.78', 'second card note'],
    );

    await tester.tap(find.byKey(const Key('pending-collection-delete')));
    await tester.pumpAndSettle();

    expect(find.byType(QuickCollectionReviewPage), findsOneWidget);
    expect(container.read(pendingCollectionProvider), hasLength(1));

    await tester.tap(find.byKey(const Key('pending-collection-delete')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byKey(const Key('pending-collection-notice')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-card-squirtle')),
        matching: find.text('Qty: 0'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('search-wishlist-squirtle')), findsOneWidget);
  });

  testWidgets(
    'pending Review aligns the folder entry and actions with the content right edge',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final contentRight =
          tester
              .getRect(find.byKey(const Key('card-detail-add-item-sheet')))
              .right -
          20;
      final folderEntry = find.byKey(
        const Key('card-detail-add-item-portfolio'),
      );
      final folderArrow = find.descendant(
        of: folderEntry,
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      );
      expect(tester.getRect(folderArrow).right, closeTo(contentRight, 0.01));
      expect(
        tester
            .getRect(find.byKey(const Key('pending-collection-delete')))
            .right,
        closeTo(contentRight, 0.01),
      );
    },
  );

  testWidgets('pending Review top scrim closes the bottom-aligned sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-collect-squirtle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pending-collection-notice')));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('card-detail-add-item-sheet'))).top,
      greaterThan(0),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byType(QuickCollectionReviewPage), findsNothing);
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byKey(const Key('pending-collection-notice')), findsOneWidget);
  });

  testWidgets('pending Review failure keeps the drag handle above Try again', (
    tester,
  ) async {
    final repository = _TrackingReviewLoadRepository();
    final portfolioApi = _CountingFolderPortfolioApi()..folders = const [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._searchOverrides(),
          ..._localAuthOverrides(),
          cardDetailRepositoryProvider.overrideWithValue(repository),
          portfolioApiClientProvider.overrideWithValue(portfolioApi),
        ],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-collect-squirtle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pending-collection-notice')));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.byKey(const Key('quick-collection-review-handle')),
      findsOneWidget,
    );
    expect(
      tester
          .getRect(find.byKey(const Key('quick-collection-review-handle')))
          .bottom,
      lessThan(tester.getRect(find.text('Try again')).top),
    );
  });

  testWidgets(
    'pending Review keeps its action area fixed when the keyboard opens',
    (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('card-detail-add-item-sheet'));
      final submit = find.byKey(const Key('card-detail-item-submit'));
      final notes = find.descendant(
        of: find.byKey(const Key('card-detail-item-notes')),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(notes);
      await tester.showKeyboard(notes);
      await tester.pump();
      final sheetBottomBefore = tester.getRect(sheet).bottom;
      final submitBottomBefore = tester.getRect(submit).bottom;
      final scrollable = find.descendant(
        of: find.byKey(const Key('card-detail-add-item-scroll')),
        matching: find.byType(Scrollable),
      );
      final scrollPosition = tester
          .state<ScrollableState>(scrollable.first)
          .position;
      final scrollOffsetBefore = scrollPosition.pixels;

      tester.view.viewInsets = FakeViewPadding(
        bottom: 300 * tester.view.devicePixelRatio,
      );
      tester.view.padding = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(tester.getRect(sheet).bottom, closeTo(sheetBottomBefore, 0.01));
      expect(tester.getRect(submit).bottom, closeTo(submitBottomBefore, 0.01));
      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(scrollPosition.pixels, greaterThan(scrollOffsetBefore));
      expect(
        tester.getRect(notes).bottom,
        lessThanOrEqualTo(viewportHeight - 300),
      );
    },
  );

  testWidgets(
    'multiple pending Review keeps its taller action area fixed when the keyboard opens',
    (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      final collect = find.byKey(const Key('search-collect-squirtle'));
      await tester.tap(collect);
      await tester.tap(collect);
      await tester.pump();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('card-detail-add-item-sheet'));
      final deleteAll = find.byKey(const Key('pending-collection-delete-all'));
      final sheetBottomBefore = tester.getRect(sheet).bottom;
      final deleteAllBottomBefore = tester.getRect(deleteAll).bottom;

      tester.view.viewInsets = FakeViewPadding(
        bottom: 300 * tester.view.devicePixelRatio,
      );
      tester.view.padding = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(tester.getRect(sheet).bottom, closeTo(sheetBottomBefore, 0.01));
      expect(
        tester.getRect(deleteAll).bottom,
        closeTo(deleteAllBottomBefore, 0.01),
      );
    },
  );

  testWidgets(
    'pending Review opens as a transient sheet without changing the Search route',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithoutPendingRoute(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.pump();
      final router = GoRouter.of(tester.element(find.byType(SearchPage)));
      expect(router.routeInformationProvider.value.uri.path, '/search');

      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      expect(find.byType(QuickCollectionReviewPage), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/search');
    },
  );

  testWidgets(
    'pending Review drag isolates the editor repaint and closes the sheet',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('card-detail-add-item-sheet'));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
        listen: false,
      );
      final pendingItem = container.read(pendingCollectionProvider).single;
      final editorProvider = quickCollectionCardDetailControllerProvider(
        pendingItem.card.id,
      );
      final repaintBoundary = find.byKey(
        const Key('quick-collection-review-repaint-boundary'),
      );
      expect(repaintBoundary, findsOneWidget);
      expect(
        tester.renderObject<RenderObject>(repaintBoundary).isRepaintBoundary,
        isTrue,
      );
      final settledTop = tester.getRect(sheet).top;
      await tester.drag(
        find.byKey(const Key('quick-collection-review-handle')),
        const Offset(0, 80),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QuickCollectionReviewPage), findsOneWidget);
      expect(tester.getRect(sheet).top, closeTo(settledTop, 0.01));

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const Key('quick-collection-review-handle')),
        ),
      );
      for (var step = 0; step < 8; step += 1) {
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.getRect(sheet).top, greaterThan(settledTop + 340));
      await gesture.up();
      await tester.pump();

      expect(find.byType(QuickCollectionReviewPage), findsOneWidget);
      expect(container.read(editorProvider).collectionItemDraft, isNotNull);
      expect(container.read(pendingCollectionProvider).single.draft, isNull);
      final exitFrameOffsets = <double>[];
      var previousTop = tester.getRect(sheet).top;
      for (var frame = 0; frame < 8; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
        if (sheet.evaluate().isEmpty) break;
        final nextTop = tester.getRect(sheet).top;
        exitFrameOffsets.add(nextTop - previousTop);
        previousTop = nextTop;
      }
      expect(
        exitFrameOffsets,
        everyElement(greaterThan(0.5)),
        reason: 'The sheet must keep moving on every exit frame after release.',
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickCollectionReviewPage), findsNothing);
      expect(container.read(editorProvider).collectionItemDraft, isNull);
      expect(container.read(pendingCollectionProvider).single.draft, isNotNull);
      expect(find.byType(SearchPage), findsOneWidget);
      expect(
        find.byKey(const Key('pending-collection-notice')),
        findsOneWidget,
      );
    },
  );

  testWidgets('multiple pending cards use card strip and batch actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-collect-squirtle')));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
      listen: false,
    );
    container
        .read(pendingCollectionProvider.notifier)
        .add(
          const PendingCollectionCard(
            id: 'mystery-promo',
            name: 'Mystery Promo',
            game: 'Pokemon',
            setName: 'Promo',
            metadataLine: 'Promo #001',
            variantLine: 'Normal',
          ),
        );
    await tester.pumpAndSettle();

    final pendingItems = container.read(pendingCollectionProvider);
    expect(find.text('2 cards waiting for details'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pending-collection-notice')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('pending-collection-card-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('pending-collection-item-${pendingItems[0].id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('pending-collection-item-${pendingItems[1].id}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pending-collection-add-all')), findsOneWidget);
    expect(
      find.byKey(const Key('pending-collection-delete-all')),
      findsOneWidget,
    );
  });

  testWidgets(
    'pending Review Delete All requires confirmation before clearing drafts',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
        listen: false,
      );
      container
          .read(pendingCollectionProvider.notifier)
          .add(
            const PendingCollectionCard(
              id: 'mystery-promo',
              name: 'Mystery Promo',
              game: 'Pokemon',
              setName: 'Promo',
              metadataLine: 'Promo #001',
              variantLine: 'Normal',
            ),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pending-collection-delete-all')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('kando-modal-frame')), findsOneWidget);
      expect(find.text('Delete all cards ?'), findsOneWidget);
      expect(
        find.text(
          'This action will permanently delete all these cards and cannot be undone',
        ),
        findsOneWidget,
      );
      expect(container.read(pendingCollectionProvider), hasLength(2));
      expect(find.byType(QuickCollectionReviewPage), findsOneWidget);

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kando-modal-frame')), findsNothing);
      expect(container.read(pendingCollectionProvider), hasLength(2));
      expect(find.byType(QuickCollectionReviewPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('pending-collection-delete-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DELETE'));
      await tester.pump();

      expect(
        find.byKey(const Key('kando-danger-modal-loading')),
        findsOneWidget,
      );
      expect(find.byType(QuickCollectionReviewPage), findsOneWidget);

      await tester.pumpAndSettle();

      expect(container.read(pendingCollectionProvider), isEmpty);
      expect(find.byType(QuickCollectionReviewPage), findsNothing);
      expect(find.byKey(const Key('pending-collection-notice')), findsNothing);
      expect(find.byType(SearchPage), findsOneWidget);
    },
  );

  testWidgets(
    'pending Review keeps Delete All Cards on one line on narrow phones',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
        listen: false,
      );
      container
          .read(pendingCollectionProvider.notifier)
          .add(
            const PendingCollectionCard(
              id: 'mystery-promo',
              name: 'Mystery Promo',
              game: 'Pokemon',
              setName: 'Promo',
              metadataLine: 'Promo #001',
              variantLine: 'Normal',
            ),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.text('DELETE ALL CARDS')).height,
        lessThanOrEqualTo(20),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending Review preloads adjacent editor data without full Card Detail requests so a warm switch stays interactive',
    (tester) async {
      final repository = _TrackingReviewLoadRepository();
      final portfolioApi = _CountingFolderPortfolioApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            ..._localAuthOverrides(),
            cardDetailRepositoryProvider.overrideWithValue(repository),
            portfolioApiClientProvider.overrideWithValue(portfolioApi),
          ],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.tap(find.byKey(const Key('search-collect-charizard-ex')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      expect(repository.coreCardIds.toSet(), {'squirtle', 'charizard-ex'});
      expect(portfolioApi.listFoldersCount, 1);
      expect(repository.marketPriceCardIds.toSet(), {
        'squirtle',
        'charizard-ex',
      });
      expect(repository.assetStateLoadCount, 0);
      expect(repository.priceSeriesLoadCount, 0);
      expect(repository.soldListingsLoadCount, 0);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(QuickCollectionReviewPage)),
        listen: false,
      );
      final pendingItems = container.read(pendingCollectionProvider);
      await tester.tap(
        find.byKey(Key('pending-collection-item-${pendingItems[1].id}')),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('card-detail-add-item-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pending-collection-card-strip')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pending Review reloads folders and starts from the shared Home selection each time it opens',
    (tester) async {
      final repository = _TrackingReviewLoadRepository();
      final portfolioApi = _CountingFolderPortfolioApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            ..._localAuthOverrides(),
            cardDetailRepositoryProvider.overrideWithValue(repository),
            portfolioApiClientProvider.overrideWithValue(portfolioApi),
          ],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(QuickCollectionReviewPage)),
        listen: false,
      );
      final editorProvider = quickCollectionCardDetailControllerProvider(
        'squirtle',
      );
      expect(find.text('Adding to Main'), findsOneWidget);

      Navigator.of(
        tester.element(find.byType(QuickCollectionReviewPage)),
      ).pop();
      await tester.pumpAndSettle();

      portfolioApi.folders = const [
        PortfolioFolderDto(
          id: 'main',
          name: 'Main',
          isDefault: true,
          sortOrder: 0,
        ),
        PortfolioFolderDto(
          id: 'trade',
          name: 'Trade',
          isDefault: false,
          sortOrder: 1,
        ),
      ];
      container.invalidate(collectionEditorFoldersProvider);
      container.read(selectedPortfolioFolderProvider.notifier).select('trade');

      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      expect(find.text('Adding to Trade'), findsOneWidget);
      expect(
        container
            .read(editorProvider)
            .detail
            .portfolioFolders
            .map((folder) => folder.name),
        ['Main', 'Trade'],
      );

      Navigator.of(
        tester.element(find.byType(QuickCollectionReviewPage)),
      ).pop();
      await tester.pumpAndSettle();

      portfolioApi.folders = const [
        PortfolioFolderDto(
          id: 'main',
          name: 'Main',
          isDefault: true,
          sortOrder: 0,
        ),
      ];
      container.invalidate(collectionEditorFoldersProvider);
      container.read(selectedPortfolioFolderProvider.notifier).select('main');

      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      expect(find.text('Adding to Main'), findsOneWidget);
      expect(find.text('Adding to Trade'), findsNothing);
      expect(
        container
            .read(editorProvider)
            .detail
            .portfolioFolders
            .map((folder) => folder.name),
        ['Main'],
      );
    },
  );

  testWidgets(
    'pending Review keeps the chosen folder after close and defaults later cards to it',
    (tester) async {
      final repository = _TrackingReviewLoadRepository();
      final portfolioApi = _CountingFolderPortfolioApi()
        ..folders = const [
          PortfolioFolderDto(
            id: 'main',
            name: 'Main',
            isDefault: true,
            sortOrder: 0,
          ),
          PortfolioFolderDto(
            id: 'trade',
            name: 'Trade',
            isDefault: false,
            sortOrder: 1,
          ),
        ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            ..._localAuthOverrides(),
            cardDetailRepositoryProvider.overrideWithValue(repository),
            portfolioApiClientProvider.overrideWithValue(portfolioApi),
          ],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(QuickCollectionReviewPage)),
        listen: false,
      );
      expect(find.text('Adding to Main'), findsOneWidget);
      await tester.tap(find.byKey(const Key('card-detail-add-item-portfolio')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trade').last);
      await tester.pumpAndSettle();

      expect(find.text('Adding to Trade'), findsOneWidget);
      expect(container.read(selectedPortfolioFolderProvider), 'trade');

      Navigator.of(
        tester.element(find.byType(QuickCollectionReviewPage)),
      ).pop();
      await tester.pumpAndSettle();
      expect(
        container.read(pendingCollectionProvider).single.draft?.portfolioName,
        'Trade',
      );

      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();
      expect(find.text('Adding to Trade'), findsOneWidget);

      Navigator.of(
        tester.element(find.byType(QuickCollectionReviewPage)),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-collect-charizard-ex')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final pendingItems = container.read(pendingCollectionProvider);
      await tester.tap(
        find.byKey(Key('pending-collection-item-${pendingItems[1].id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Adding to Trade'), findsOneWidget);
    },
  );

  testWidgets(
    'pending Add this card shows validation in a top toast because its fixed action stays visible while the form error is below',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('card-detail-item-quantity')),
          matching: find.byType(TextFormField),
        ),
        '0',
      );
      await tester.tap(find.byKey(const Key('card-detail-item-submit')));
      await tester.pump();

      final toast = find.byKey(const Key('kando-top-toast'));
      expect(toast, findsOneWidget);
      expect(
        find.descendant(
          of: toast,
          matching: find.text('Quantity must be at least 1.'),
        ),
        findsOneWidget,
      );
      expect(find.byType(QuickCollectionReviewPage), findsOneWidget);

      await tester.pump(kandoTopToastDuration);
      await tester.pump();
    },
  );

  testWidgets('saving repeated clicks creates separate variant Items', (
    tester,
  ) async {
    final repository = _RecordingPendingCreateRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._searchOverrides(),
          ..._localAuthOverrides(),
          cardDetailRepositoryProvider.overrideWithValue(repository),
        ],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final collect = find.byKey(const Key('search-collect-squirtle'));
    await tester.tap(collect);
    await tester.tap(collect);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pending-collection-notice')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuickCollectionReviewPage)),
      listen: false,
    );
    final pendingItems = container.read(pendingCollectionProvider);
    await tester.tap(
      find.byKey(Key('pending-collection-item-${pendingItems[1].id}')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-item-state-graded')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-detail-item-state-graded')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('BGS').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('BGS').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pending-collection-add-all')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
    expect(container.read(pendingCollectionProvider), isEmpty);
    final detail = container.read(
      quickCollectionCardDetailControllerProvider('squirtle'),
    );
    expect(detail.detail.quantity, 2);
    expect(detail.detail.collectionItems, hasLength(2));
    expect(detail.detail.collectionItems.map((item) => item.grader).toSet(), {
      'Raw',
      'BGS',
    });
    expect(repository.idempotencyKeys, pendingItems.map((item) => item.id));
    expect(repository.idempotencyKeys.toSet(), hasLength(2));
    expect(detail.detail.isWishlisted, isFalse);
    expect(
      find.byKey(const Key('kando-centered-success-toast')),
      findsOneWidget,
    );
    expect(find.text('2 cards added to your portfolio'), findsOneWidget);
    await tester.pump(kandoCenteredSuccessToastDuration);
    await tester.pump();
  });

  testWidgets(
    'Add All keeps every pending card visible until the batch settles because progress must not look like individual removal',
    (tester) async {
      final repository = _BlockingBatchCreateRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            ..._localAuthOverrides(),
            cardDetailRepositoryProvider.overrideWithValue(repository),
          ],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      final collect = find.byKey(const Key('search-collect-squirtle'));
      await tester.tap(collect);
      await tester.tap(collect);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(QuickCollectionReviewPage)),
        listen: false,
      );
      final pendingItems = container.read(pendingCollectionProvider);
      await tester.tap(find.byKey(const Key('pending-collection-add-all')));
      await tester.pump();

      expect(repository.pendingCreates, hasLength(1));
      repository.completeNext();
      await tester.pump();
      await tester.pump();

      expect(repository.pendingCreates, hasLength(2));
      expect(container.read(pendingCollectionProvider), hasLength(2));
      for (final item in pendingItems) {
        expect(
          find.byKey(Key('pending-collection-item-${item.id}')),
          findsOneWidget,
        );
      }

      repository.completeNext();
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget);
      expect(container.read(pendingCollectionProvider), isEmpty);
      expect(find.text('2 cards added to your portfolio'), findsOneWidget);
      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pump();
    },
  );

  testWidgets(
    'Add All keeps the selected editor stable and runs up to three different cards concurrently with visible progress',
    (tester) async {
      final repository = _BlockingBatchCreateRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            ..._localAuthOverrides(),
            cardDetailRepositoryProvider.overrideWithValue(repository),
          ],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-squirtle')));
      await tester.tap(find.byKey(const Key('search-collect-charizard-ex')));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
        listen: false,
      );
      container
          .read(pendingCollectionProvider.notifier)
          .add(
            const PendingCollectionCard(
              id: 'one-piece-luffy',
              name: 'One Piece Manga Luffy',
              game: 'One Piece',
              setName: 'Romance Dawn',
              metadataLine: 'Manga Rare · 001',
              variantLine: 'Japanese',
            ),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pending-collection-add-all')));
      await tester.pump();
      await tester.pump();

      expect(repository.pendingCreates, hasLength(3));
      expect(find.text('Saving 0 of 3'), findsOneWidget);
      expect(
        find.byKey(const Key('card-detail-add-item-sheet')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<InkWell>(
              find.byKey(
                Key(
                  'pending-collection-item-${container.read(pendingCollectionProvider)[1].id}',
                ),
              ),
            )
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('pending-collection-close')),
            )
            .onPressed,
        isNull,
      );

      repository.completeNext();
      await tester.pump();
      expect(find.text('Saving 1 of 3'), findsOneWidget);
      expect(
        find.byKey(const Key('card-detail-add-item-sheet')),
        findsOneWidget,
      );

      repository.completeNext();
      repository.completeNext();
      await tester.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.text('3 cards added to your portfolio'), findsOneWidget);
      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pump();
    },
  );

  testWidgets(
    'Add All returns to the non-default Game and refreshes Search once because portfolio updates must preserve browsing context',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 600);
      addTearDown(tester.view.reset);
      final searchRepository = _CountingSearchRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchRepositoryProvider.overrideWithValue(searchRepository),
            ..._localAuthOverrides(),
            cardDetailRepositoryProvider.overrideWithValue(
              _RecordingPendingCreateRepository(),
            ),
          ],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pokemon'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-game-filter-one-piece')));
      await tester.tap(find.byKey(const Key('search-game-apply-filter')));
      await tester.pumpAndSettle();
      expect(find.text('One Piece Manga Luffy'), findsOneWidget);

      final refreshBaseline = searchRepository.loadCatalogCount;
      final collect = find.byKey(const Key('search-collect-one-piece-luffy'));
      await tester.tap(collect);
      await tester.tap(collect);
      await tester.pumpAndSettle();
      final searchScrollable = find.descendant(
        of: find.byKey(const Key('search-content-scroll')),
        matching: find.byType(Scrollable),
      );
      final searchPosition = tester
          .state<ScrollableState>(searchScrollable.first)
          .position;
      searchPosition.jumpTo(searchPosition.maxScrollExtent);
      await tester.pump();
      expect(searchPosition.pixels, greaterThan(0));
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-collection-add-all')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
        listen: false,
      );
      expect(
        container.read(searchControllerProvider).selectedGame.label,
        'One Piece',
      );
      expect(searchRepository.loadCatalogCount, refreshBaseline + 1);
      expect(searchPosition.pixels, 0);
      expect(find.text('2 cards added to your portfolio'), findsOneWidget);
      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pump();
    },
  );

  testWidgets('batch save keeps failed Items and reports partial success', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._searchOverrides(),
          ..._localAuthOverrides(),
          cardDetailRepositoryProvider.overrideWithValue(
            const _FailBgsCardDetailRepository(),
          ),
        ],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final collect = find.byKey(const Key('search-collect-squirtle'));
    await tester.tap(collect);
    await tester.tap(collect);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pending-collection-notice')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuickCollectionReviewPage)),
      listen: false,
    );
    final pendingItems = container.read(pendingCollectionProvider);
    await tester.tap(
      find.byKey(Key('pending-collection-item-${pendingItems[1].id}')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-item-state-graded')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-detail-item-state-graded')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('BGS').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('BGS').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pending-collection-add-all')));
    await tester.pumpAndSettle();

    expect(find.text('1 card added, 1 failed.'), findsOneWidget);
    expect(container.read(pendingCollectionProvider), hasLength(1));
    expect(
      container.read(pendingCollectionProvider).single.id,
      pendingItems[1].id,
    );
    expect(
      container.read(pendingCollectionProvider).single.draft?.grader,
      'BGS',
    );
    final detail = container.read(
      quickCollectionCardDetailControllerProvider('squirtle'),
    );
    expect(detail.detail.quantity, 1);
    expect(detail.detail.collectionItems, hasLength(1));
    expect(detail.detail.collectionItems.single.grader, 'Raw');
    await tester.pump(kandoTopToastDuration);
    await tester.pump();
  });

  testWidgets(
    'saving another Item on an owned card preserves the existing Item and increases Qty',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-charizard-ex')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(QuickCollectionReviewPage)),
        listen: false,
      );
      await tester.tap(find.byKey(const Key('card-detail-item-submit')));
      await tester.pumpAndSettle();

      final detail = container.read(
        quickCollectionCardDetailControllerProvider('charizard-ex'),
      );
      expect(detail.detail.quantity, 2);
      expect(detail.detail.collectionItems, hasLength(2));
      expect(
        detail.detail.collectionItems
            .singleWhere((item) => item.id == 'item-charizard')
            .quantity,
        1,
      );
      expect(container.read(pendingCollectionProvider), isEmpty);
      expect(find.byType(SearchPage), findsOneWidget);
      expect(
        find.byKey(const Key('kando-centered-success-toast')),
        findsOneWidget,
      );
      expect(find.text(portfolioCardAddedToastText), findsOneWidget);
      expect(
        find.byKey(const Key('search-wishlist-charizard-ex')),
        findsNothing,
      );
      expect(
        container
            .read(searchControllerProvider)
            .cardById('charizard-ex')
            .quantity,
        2,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('search-card-charizard-ex')),
          matching: find.text('Qty: 2'),
        ),
        findsOneWidget,
      );
      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pump();
    },
  );

  testWidgets('Search card action failures do not show a toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          searchRepositoryProvider.overrideWithValue(
            const _FailingActionSearchRepository(),
          ),
        ],
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-wishlist-squirtle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
    expect(find.byKey(const Key('kando-floating-toast')), findsNothing);

    await tester.tap(find.byKey(const Key('search-collect-squirtle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kando-top-toast')), findsNothing);
    expect(find.byKey(const Key('kando-floating-toast')), findsNothing);
  });

  testWidgets('no matching results state is shown', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'missing');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-no-results')), findsOneWidget);
    expect(find.text('No results found'), findsOneWidget);
    expect(find.text('Try a different keyword'), findsOneWidget);
    expect(
      find.byKey(const Key('search-no-results-magnifier-outer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('search-no-results-magnifier-inner')),
      findsOneWidget,
    );
    expect(find.text(noContentAvailableText), findsNothing);
    expect(find.byKey(const Key('search-empty-refresh')), findsNothing);
  });

  testWidgets('scanner action opens Scan workflow', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate((widget) {
        return widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.photo_camera_outlined;
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });

  testWidgets(
    'Search bottom navigation can open Home, Collection, and Profile',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            ..._localAuthOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
          ],
          child: const _SearchTestAppWithRoutes(),
        ),
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kando-tab-collection')));
      await tester.pumpAndSettle();
      expect(find.text('Portfolio'), findsWidgets);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in / Sign up'), findsOneWidget);
    },
  );

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kando-tab-scan')));
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
  });

  testWidgets('tapping a Search card opens CardDetail', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final squirtleCard = find.byKey(const Key('search-card-squirtle'));
    await tester.ensureVisible(squirtleCard);
    await tester.pumpAndSettle();
    await tester.tap(squirtleCard);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-detail-hero')), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(
      tester.widget<CardDetailPage>(find.byType(CardDetailPage)).preview?.name,
      'Squirtle',
    );
    expect(
      find.byKey(const Key('card-detail-add-to-portfolio-squirtle')),
      findsOneWidget,
    );
    expect(find.text('Add to Portfolio'), findsNothing);
    expect(find.text('Collect'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Mega Evolution Promos'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Mega Evolution Promos'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-price-chart')),
      400,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Price'), findsOneWidget);
    expect(find.byKey(const Key('card-detail-price-chart')), findsOneWidget);
  });

  testWidgets(
    'returning from CardDetail restores the selected Search card position',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      final searchScroll = find
          .descendant(
            of: find.byType(SearchPage),
            matching: find.byType(Scrollable),
          )
          .first;
      final selectedCard = find.byKey(const Key('search-card-mystery-promo'));
      await tester.scrollUntilVisible(
        selectedCard,
        300,
        scrollable: searchScroll,
      );
      await tester.ensureVisible(selectedCard);
      await tester.pumpAndSettle();
      final offsetBeforeOpening = tester
          .state<ScrollableState>(searchScroll)
          .position
          .pixels;
      expect(offsetBeforeOpening, greaterThan(0));

      await tester.tap(selectedCard);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-back')));
      await tester.pumpAndSettle();

      final restoredSearchScroll = find
          .descendant(
            of: find.byType(SearchPage),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(
        tester.state<ScrollableState>(restoredSearchScroll).position.pixels,
        closeTo(offsetBeforeOpening, 0.01),
      );
      expect(selectedCard, findsOneWidget);
    },
  );

  testWidgets('tapping an owned Search card opens owned CardDetail', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._searchOverrides(),
          ..._localAuthOverrides(),
          cardDetailRepositoryProvider.overrideWithValue(
            const _MultiFolderCardDetailRepository(),
          ),
        ],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final charizardCard = find.byKey(const Key('search-card-charizard-ex'));
    await tester.ensureVisible(charizardCard);
    await tester.pumpAndSettle();
    await tester.tap(charizardCard);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-detail-hero')), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('card-detail-add-to-portfolio-charizard-ex')),
    );
    await tester.pumpAndSettle();
    final detailContainer = ProviderScope.containerOf(
      tester.element(find.byType(CardDetailPage)),
      listen: false,
    );
    expect(detailContainer.read(pendingCollectionProvider), isEmpty);
    expect(find.byKey(const Key('card-detail-add-item-sheet')), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-detail-owned-tabs')), findsNothing);
    expect(find.text('In Your Portfolio'), findsOneWidget);
    expect(
      find.byKey(const Key('card-detail-portfolio-item-item-charizard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('card-detail-portfolio-item-item-charizard-sealed')),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-portfolio-item-item-charizard')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('card-detail-portfolio-item-item-charizard')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('card-detail-edit-item-sheet')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('card-detail-item-quantity')),
      '3',
    );
    await tester.tap(find.byKey(const Key('card-detail-edit-item-sheet-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card-detail-edit-item-sheet')), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CardDetailPage)),
      listen: false,
    );
    expect(
      container
          .read(cardDetailControllerProvider('charizard-ex'))
          .detail
          .collectionItems
          .singleWhere((item) => item.id == 'item-charizard')
          .quantity,
      3,
    );
  });
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

_cardDetailOverrides() {
  return [
    ..._localAuthOverrides(),
    cardDetailRepositoryProvider.overrideWithValue(
      const MockCardDetailRepository(),
    ),
  ];
}

class _SearchTestApp extends StatelessWidget {
  const _SearchTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SearchPage());
  }
}

class _SearchTestAppWithoutPendingRoute extends StatelessWidget {
  const _SearchTestAppWithoutPendingRoute();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
        ],
      ),
    );
  }
}

class _SearchTestAppWithRoutes extends StatelessWidget {
  const _SearchTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => const CollectionPage(),
          ),
          GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
          GoRoute(
            path: '/cards/:cardId',
            builder: (context, state) {
              final extra = state.extra;
              return CardDetailPage(
                cardId: state.pathParameters['cardId'] ?? '',
                preview: extra is CardDetailPreview ? extra : null,
                collectionItemId: state.uri.queryParameters['item_id'],
              );
            },
          ),
          GoRoute(
            path: '/collection-items/pending',
            pageBuilder: (context, state) => KandoBottomSheetPage<void>(
              key: state.pageKey,
              barrierColor: const Color(0xB8000000),
              isDismissible: true,
              heightFactor: 0.93,
              child: const QuickCollectionReviewPage(heightFactor: 1),
            ),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
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

class _FailingThenSuccessfulSearchRepository implements SearchRepository {
  var calls = 0;

  @override
  Future<SearchCatalog> loadCatalog() async {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock search unavailable');
    }
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    return const MockSearchRepository().searchCards(query);
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query);
  }
}

class _FailingPaginatedSearchRepository
    implements SearchRepository, PaginatedSearchRepository {
  final requestedPages = <int>[];
  var _failedPageTwo = false;

  @override
  Future<SearchCatalog> loadCatalog() async {
    return SearchCatalog(
      games: const [SearchGame(id: 'pokemon', label: 'Pokemon')],
      cards: List.generate(40, (index) => _card(index + 1)),
      sets: const [],
    );
  }

  @override
  Future<List<SearchCard>> searchCardPage(
    String query, {
    String? game,
    required int page,
  }) async {
    requestedPages.add(page);
    if (page == 2 && !_failedPageTwo) {
      _failedPageTwo = true;
      throw StateError('mock next page unavailable');
    }
    return page == 2 ? [_card(41)] : const [];
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) async {
    return (await loadCatalog()).cards;
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) async {
    return const [];
  }

  static SearchCard _card(int index) {
    return SearchCard(
      id: 'card-$index',
      gameId: 'pokemon',
      type: SearchCardType.tcg,
      name: 'Card $index',
      priceUsd: index.toDouble(),
      previous30dPriceUsd: index.toDouble(),
      setName: 'Test Set',
      metadataLine: '#$index',
      variantLine: 'Normal',
      quantity: 0,
      isWishlisted: false,
      changePercent: null,
    );
  }
}

class _TrackingSearchRepository implements SearchRepository {
  var cardCalls = 0;

  @override
  Future<SearchCatalog> loadCatalog() {
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    cardCalls += 1;
    return const MockSearchRepository().searchCards(query, game: game);
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query, game: game);
  }
}

class _BlockingRefreshSearchRepository implements SearchRepository {
  final _refresh = Completer<List<SearchCard>>();
  var loadCatalogCalls = 0;
  var searchCardsCalls = 0;

  @override
  Future<SearchCatalog> loadCatalog() {
    loadCatalogCalls += 1;
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    searchCardsCalls += 1;
    return _refresh.future;
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query, game: game);
  }

  Future<void> completeRefresh() async {
    _refresh.complete(
      await const MockSearchRepository().searchCards('', game: 'Pokemon'),
    );
  }
}

class _CountingSearchRepository extends MockSearchRepository {
  var loadCatalogCount = 0;

  @override
  Future<SearchCatalog> loadCatalog() {
    loadCatalogCount += 1;
    return super.loadCatalog();
  }
}

class _BlockingGameSearchRepository implements SearchRepository {
  final _cards = Completer<List<SearchCard>>();

  @override
  Future<SearchCatalog> loadCatalog() {
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    return _cards.future;
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query, game: game);
  }

  Future<void> completeCardSearch() async {
    _cards.complete(
      await const MockSearchRepository().searchCards('', game: 'Lorcana'),
    );
  }
}

class _CurrentGameSearchRepository implements SearchRepository {
  const _CurrentGameSearchRepository();

  @override
  Future<SearchCatalog> loadCatalog() async {
    final catalog = await const MockSearchRepository().loadCatalog();
    return SearchCatalog(
      games: catalog.games,
      cards: catalog.cards.where((card) => card.gameId == 'pokemon').toList(),
      sets: catalog.sets,
    );
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    return const MockSearchRepository().searchCards(query, game: game);
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query, game: game);
  }
}

class _FailingCardSearchRepository implements SearchRepository {
  var cardCalls = 0;

  @override
  Future<SearchCatalog> loadCatalog() {
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) async {
    cardCalls += 1;
    if (cardCalls == 1) {
      throw StateError('mock card search unavailable');
    }
    return const MockSearchRepository().searchCards(query);
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query);
  }
}

class _ImageSearchRepository implements SearchRepository {
  const _ImageSearchRepository();

  @override
  Future<SearchCatalog> loadCatalog() async {
    return const SearchCatalog(
      games: [SearchGame(id: 'tcg', label: 'TCG')],
      cards: [
        SearchCard(
          id: '9359',
          gameId: 'tcg',
          type: SearchCardType.tcg,
          name: 'Escape Artist',
          priceUsd: 0.21,
          previous30dPriceUsd: 0.17,
          setName: 'Odyssey',
          metadataLine: 'Common #123',
          variantLine: 'Normal',
          quantity: 0,
          isWishlisted: false,
          changePercent: null,
          language: 'English',
          finish: 'Normal',
          imageUrl: 'https://api.tcgcard.fun/api/v1/cards/9359/image',
        ),
        SearchCard(
          id: 'jp-pikachu',
          gameId: 'tcg',
          type: SearchCardType.tcg,
          name: 'Pikachu',
          priceUsd: null,
          previous30dPriceUsd: null,
          setName: 'Promo',
          metadataLine: 'Promo · 001',
          variantLine: 'Normal',
          quantity: 0,
          isWishlisted: false,
          changePercent: null,
          language: 'Japanese',
        ),
        SearchCard(
          id: 'cn-psyduck',
          gameId: 'tcg',
          type: SearchCardType.tcg,
          name: 'Psyduck',
          priceUsd: null,
          previous30dPriceUsd: null,
          setName: 'Promo',
          metadataLine: 'Promo · 002',
          variantLine: 'Normal',
          quantity: 0,
          isWishlisted: false,
          changePercent: null,
          language: 'Chinese',
        ),
      ],
      sets: [],
    );
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) async {
    return (await loadCatalog()).cards;
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) async =>
      const [];
}

class _FailBgsCardDetailRepository extends MockCardDetailRepository {
  const _FailBgsCardDetailRepository();

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
    String? idempotencyKey,
  }) {
    if (item.grader == 'BGS') {
      throw StateError('BGS create unavailable');
    }
    return super.createCollectionItem(
      session,
      detail: detail,
      item: item,
      idempotencyKey: idempotencyKey,
    );
  }
}

class _TrackingReviewLoadRepository extends MockCardDetailRepository
    implements CardDetailSectionRepository {
  final List<String> coreCardIds = [];
  final List<String> marketPriceCardIds = [];
  var assetStateLoadCount = 0;
  var priceSeriesLoadCount = 0;
  var soldListingsLoadCount = 0;

  static const _session = AuthSession(
    ownerType: OwnerType.anonymous,
    accessToken: 'test-access',
    refreshToken: 'test-refresh',
  );

  @override
  Future<CardDetail> loadCoreDetail(String cardId) async {
    coreCardIds.add(cardId);
    return super.loadDetail(_session, cardId);
  }

  @override
  Future<CardDetail> loadBaseDetail(AuthSession session, String cardId) async {
    final detail = await loadCoreDetail(cardId);
    return loadAssetState(session, detail);
  }

  @override
  Future<CardDetail> loadAssetState(
    AuthSession session,
    CardDetail detail,
  ) async {
    assetStateLoadCount += 1;
    return detail;
  }

  @override
  Future<CardDetailMarketData> loadMarketPrices(
    String cardId, {
    String? finish,
    String? language,
  }) async {
    marketPriceCardIds.add(cardId);
    return const CardDetailMarketData(prices: [], marketPrices: []);
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
    priceSeriesLoadCount += 1;
    return const CardDetailSeriesData(
      marketPrices: [],
      rawSeriesByRange: {},
      rawSeries: [],
      gradedSeriesByRange: {},
      gradedSeries: [],
    );
  }

  @override
  Future<List<CardSoldListing>> loadSoldListings(String cardId) async {
    soldListingsLoadCount += 1;
    return const [];
  }
}

class _CountingFolderPortfolioApi extends PortfolioApiClient {
  _CountingFolderPortfolioApi()
    : folders = const [
        PortfolioFolderDto(
          id: 'main',
          name: 'Main',
          isDefault: true,
          sortOrder: 0,
        ),
      ],
      super(Dio());

  var listFoldersCount = 0;
  List<PortfolioFolderDto> folders;

  @override
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session) async {
    listFoldersCount += 1;
    return folders;
  }
}

class _RecordingPendingCreateRepository extends MockCardDetailRepository {
  final List<String?> idempotencyKeys = [];

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
    String? idempotencyKey,
  }) {
    idempotencyKeys.add(idempotencyKey);
    return super.createCollectionItem(
      session,
      detail: detail,
      item: item,
      idempotencyKey: idempotencyKey,
    );
  }
}

class _BlockingBatchCreateRepository extends MockCardDetailRepository {
  final List<
    ({
      CardDetail detail,
      CardCollectionItem item,
      Completer<CardCollectionItem> completer,
    })
  >
  pendingCreates = [];

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
    String? idempotencyKey,
  }) {
    final completer = Completer<CardCollectionItem>();
    pendingCreates.add((detail: detail, item: item, completer: completer));
    return completer.future;
  }

  void completeNext() {
    final pending = pendingCreates.firstWhere(
      (request) => !request.completer.isCompleted,
    );
    pending.completer.complete(
      pending.item.copyWith(cardRef: pending.detail.id),
    );
  }
}

class _MultiFolderCardDetailRepository extends MockCardDetailRepository {
  const _MultiFolderCardDetailRepository();

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await super.loadDetail(session, cardId);
    final source = detail.collectionItems.first;
    return detail.copyWith(
      quantity: detail.quantity + 1,
      collectionItems: [
        ...detail.collectionItems,
        CardCollectionItem(
          id: 'item-charizard-sealed',
          cardRef: source.cardRef,
          folderId: 'sealed',
          portfolioName: 'Sealed',
          quantity: 1,
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          language: source.language,
          finish: source.finish,
          purchasePriceUsd: source.purchasePriceUsd,
          notes: source.notes,
        ),
      ],
    );
  }
}

class _FailingActionSearchRepository implements SearchAssetRepository {
  const _FailingActionSearchRepository();

  @override
  Future<SearchCatalog> loadCatalog() {
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    return const MockSearchRepository().searchCards(query, game: game);
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query, game: game);
  }

  @override
  Future<SearchAssetSnapshot> loadAssets(
    AuthSession session, {
    String? selectedFolderId,
  }) async {
    return const SearchAssetSnapshot(
      folderId: 'folder-main',
      statesByCardRef: {},
    );
  }

  @override
  Future<WishlistItemDto> addWishlist(AuthSession session, String cardRef) {
    throw StateError('mock wishlist unavailable');
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) async {}
}

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}
