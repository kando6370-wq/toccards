import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_models.dart';
import 'package:kando_app/features/card_detail/card_detail_repository.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_performance_controller.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'support/in_memory_auth_storage.dart';
import 'support/local_placeholder_auth_repository.dart';
import 'support/mock_card_detail_repository.dart';
import 'support/mock_collection_repository.dart';
import 'support/mock_home_repository.dart';
import 'support/mock_search_repository.dart';

void main() {
  test(
    'collection grading options and database buckets stay aligned because every saved graded card must be priceable',
    () {
      expect(cardCollectionGraders, ['Raw', 'PSA', 'BGS', 'CGC', 'SGC']);
      expect(cardCollectionGradeValuesFor('PSA'), [
        '10',
        '9',
        '8.5',
        '8',
        '7.5',
        '7',
      ]);
      expect(cardCollectionGradeValuesFor('CGC'), ['10']);
      expect(
        cardCollectionPriceMatches(
          grader: 'PSA',
          grade: 7.5,
          marketGrader: 'Grade',
          marketGrade: 7,
        ),
        isTrue,
      );
      expect(
        cardCollectionPriceMatches(
          grader: 'PSA',
          grade: 9,
          marketGrader: 'GENERIC',
          marketGrade: 9,
        ),
        isTrue,
        reason:
            'PostgreSQL GENERIC and the existing Grade API bucket represent the same shared grade price.',
      );
      expect(
        cardCollectionPriceMatches(
          grader: 'PSA',
          grade: 10,
          marketGrader: 'SGC',
          marketGrade: 10,
        ),
        isFalse,
      );
    },
  );

  test(
    'PSA 7.5 draft uses the shared Grade 7 market bucket because total value must reflect the selected graded price',
    () {
      const state = CardDetailState(
        cardId: '656259',
        detail: CardDetail(
          id: '656259',
          type: CardDetailType.tcg,
          name: 'Test Card',
          game: 'Pokemon',
          setName: 'Test Set',
          identityLine: '#656259',
          finish: 'Normal',
          language: 'English',
          quantity: 0,
          isWishlisted: false,
          marketPrices: [
            CardMarketPrice(
              label: '7/7.5',
              grader: 'Grade',
              grade: 7,
              gradeLabel: '7/7.5',
              priceUsd: 14.76,
              previous30dPriceUsd: null,
            ),
          ],
        ),
        currency: AppCurrency.usd,
        collectionItemDraft: CardCollectionItemDraft(
          quantityText: '2',
          portfolioName: 'Main',
          grader: 'PSA',
          condition: '',
          grade: '7.5',
          language: 'English',
          finish: 'Normal',
          purchasePriceText: '',
          notes: '',
        ),
      );

      expect(state.collectionItemDraftMarketPriceText, r'$14.76');
      expect(state.collectionItemDraftTotalText, r'$29.52');
    },
  );

  test(
    'http detail repository loads card-data presentation rows before portfolio overlay because card identity and prices are catalog-owned',
    () async {
      final cardDataApi = _FakeCardDataApi();
      final detail = await HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [],
          items: const [],
          wishlist: const [],
        ),
        cardDataApi: cardDataApi,
      ).loadDetail(_session, 'catalog:pikachu-025');

      expect(cardDataApi.cardRefs, ['catalog:pikachu-025']);
      expect(
        cardDataApi.maxConcurrentSeriesRequests,
        5,
        reason:
            'Card Detail must not serialize every market qualifier and chart range into a network waterfall.',
      );
      expect(
        cardDataApi.totalSeriesRequests,
        5,
        reason:
            'Market prices must reuse the full chart load instead of requesting 7d and 30d series twice.',
      );
      expect(cardDataApi.priceSeriesBatchCalls, 1);
      expect(detail.id, 'catalog:pikachu-025');
      expect(detail.type, CardDetailType.tcg);
      expect(detail.name, 'Pikachu');
      expect(detail.game, 'Pokemon');
      expect(
        detail.imageUrl,
        'https://image.tcgcard.fun/cards/catalog%3Apikachu-025.jpg',
      );
      expect(detail.setName, 'Base Set');
      expect(detail.identityLine, 'Common #025');
      expect(detail.finish, 'Holofoil');
      expect(detail.language, 'English');
      expect(detail.collectionLanguageOptions, ['English', 'Japanese']);
      expect(detail.collectionFinishOptions, ['Holofoil', 'Normal']);
      expect(detail.marketPrices.map((price) => price.label), [
        'Raw Near Mint',
        'PSA 10',
      ]);
      expect(detail.marketPrices.first.priceUsd, 15);
      expect(detail.marketPrices.first.previous30dPriceUsd, 10);
      expect(detail.marketPrices.first.previous7dPriceUsd, 14);
      expect(
        detail.marketPrices.last.previous7dPriceUsd,
        65,
        reason:
            'Graded 7D change must use its own price history and an inclusive seven-day window.',
      );
      expect(
        detail.priceSeriesByRange[CardPriceRange.oneMonth]!.first.dateLabel,
        '2026-06-10',
      );
      expect(
        detail.rawPriceSeries.map((series) => series.label),
        ['Near Mint'],
        reason: 'RAW chart legends must describe condition without Raw.',
      );
      expect(
        detail.gradedPriceSeries.map((series) => series.label),
        ['PSA 10'],
        reason: 'GRADED chart legends must not repeat the card material.',
      );
      expect(
        detail
            .gradedPriceSeriesByRange[CardPriceRange.threeMonths]!
            .last
            .priceUsd,
        70,
      );
      expect(detail.soldListings.single.platform, 'eBay');
      expect(detail.isCollected, isFalse);
      expect(detail.isWishlisted, isFalse);
    },
  );

  test(
    'http detail repository isolates optional endpoint failures because the PRD keeps base card information available',
    () async {
      final failingOptionalApi = _FakeCardDataApi(
        card: _pricedPikachuCard,
        failMarketPrices: true,
        failSoldListings: true,
      );
      final repository = HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [],
          items: const [],
          wishlist: const [],
        ),
        cardDataApi: failingOptionalApi,
      );

      final base = await repository.loadBaseDetail(
        _session,
        'catalog:pikachu-025',
      );

      expect(base.name, 'Pikachu');
      expect(base.marketPrices.single.previous7dPriceUsd, 14);
      expect(base.marketPrices.single.increasePercent, 7.14);
      await expectLater(
        repository.loadMarketPrices('catalog:pikachu-025'),
        throwsStateError,
      );
      await expectLater(
        repository.loadSoldListings('catalog:pikachu-025'),
        throwsStateError,
      );

      final failingSeriesRepository = HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [],
          items: const [],
          wishlist: const [],
        ),
        cardDataApi: _FakeCardDataApi(failPriceSeries: true),
      );
      await expectLater(
        failingSeriesRepository.loadPriceSeries('catalog:pikachu-025'),
        throwsStateError,
      );
    },
  );

  test(
    'core card renders before portfolio state because slow user data must not block detail navigation',
    () async {
      final portfolioApi = _BlockingPortfolioApiClient();
      final repository = HttpCardDetailRepository(
        api: portfolioApi,
        cardDataApi: _FakeCardDataApi(),
      );
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;
      final provider = cardDetailControllerProvider('catalog:pikachu-025');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      subscription.read();
      await portfolioApi.started.future;
      await Future<void>.delayed(Duration.zero);

      final firstContent = container.read(provider);
      expect(firstContent.loadStatus, KandoLoadStatus.content);
      expect(firstContent.detail.name, 'Pikachu');
      expect(firstContent.assetStateStatus, KandoLoadStatus.loading);

      portfolioApi.release();
      await container.read(provider.notifier).loadComplete;
      await _drainSectionLoads();

      final complete = container.read(provider);
      expect(complete.assetStateStatus, KandoLoadStatus.content);
      expect(complete.marketPricesStatus, KandoLoadStatus.content);
      expect(complete.priceSeriesStatus, KandoLoadStatus.content);
      expect(complete.soldListingsStatus, KandoLoadStatus.content);
      expect(complete.detail.marketPrices.first.previous30dPriceUsd, 10);
    },
  );

  test(
    'http detail repository overlays backend collection rows onto local card detail because ownership state is backend-owned',
    () async {
      final api = _FakePortfolioApiClient(
        folders: const [
          PortfolioFolderDto(
            id: 'main',
            name: 'Main',
            isDefault: true,
            sortOrder: 100,
          ),
        ],
        items: [
          _portfolioItem(
            id: 'backend-item',
            folderId: 'main',
            cardRef: 'squirtle',
            quantity: 2,
          ),
        ],
        wishlist: const [],
      );

      final detail = await HttpCardDetailRepository(
        api: api,
        cardDataApi: _FakeCardDataApi(card: _squirtleCard),
      ).loadDetail(_session, 'squirtle');

      expect(detail.name, 'Squirtle');
      expect(detail.quantity, 2);
      expect(detail.collectionItems.single.id, 'backend-item');
      expect(detail.collectionItems.single.cardRef, 'squirtle');
      expect(detail.collectionItems.single.folderId, 'main');
      expect(detail.collectionItems.single.portfolioName, 'Main');
      expect(detail.isWishlisted, isFalse);
      expect(detail.wishlistItemId, isNull);
    },
  );

  test(
    'price series falls back to single requests because mobile and Workers releases are not atomic',
    () async {
      final cardDataApi = _FakeCardDataApi(failPriceSeriesBatch: true);
      final detail = await HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [],
          items: const [],
          wishlist: const [],
        ),
        cardDataApi: cardDataApi,
      ).loadDetail(_session, 'catalog:pikachu-025');

      expect(cardDataApi.priceSeriesBatchCalls, 1);
      expect(cardDataApi.totalSeriesRequests, 5);
      expect(detail.priceSeriesByRange, isNotEmpty);
    },
  );

  test(
    'http detail repository overlays wishlist id because wishlist deletion needs the backend row id',
    () async {
      final detail = await HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [],
          items: const [],
          wishlist: [
            WishlistItemDto(
              id: 'wish-squirtle',
              cardRef: 'squirtle',
              createdAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
            ),
          ],
        ),
        cardDataApi: _FakeCardDataApi(card: _squirtleCard),
      ).loadDetail(_session, 'squirtle');

      expect(detail.isWishlisted, isTrue);
      expect(detail.wishlistItemId, 'wish-squirtle');
    },
  );

  test(
    'quick collect delegates to portfolio api because Card Detail must not invent item ids',
    () async {
      final api = _FakePortfolioApiClient(
        folders: const [
          PortfolioFolderDto(
            id: 'main',
            name: 'Main',
            isDefault: true,
            sortOrder: 100,
          ),
        ],
        items: const [],
        wishlist: const [],
        quickCollectResult: _portfolioItem(
          id: 'backend-item-squirtle',
          folderId: 'main',
          cardRef: 'squirtle',
        ),
      );
      final detail = await const MockCardDetailRepository().loadDetail(
        _session,
        'squirtle',
      );

      final saved = await HttpCardDetailRepository(
        api: api,
        cardDataApi: _FakeCardDataApi(),
      ).quickCollect(_session, detail);

      expect(api.quickCollectCardRefs, ['squirtle']);
      expect(api.quickCollectDrafts.single.folderId, 'main');
      expect(saved.id, 'backend-item-squirtle');
      expect(saved.cardRef, 'squirtle');
    },
  );

  test('uncollected detail exposes card identity and price overview', () async {
    final container = _cardDetailContainer();
    addTearDown(container.dispose);

    final state = await _loadedState(container, 'squirtle');

    expect(state.isUnavailable, isFalse);
    expect(state.detail.name, 'Squirtle');
    expect(state.detail.game, 'Pokemon');
    expect(state.detail.setName, 'Mega Evolution Promos');
    expect(state.detail.identityLine, 'Promo #039');
    expect(state.detail.finish, 'Holofoil');
    expect(state.detail.language, 'English');
    expect(state.marketPriceText, r'$32.13');
    expect(state.changeText, '+4.76%');
    expect(state.detail.isCollected, isFalse);
  });

  test(
    'selected currency converts market price without changing percentage',
    () async {
      final container = _cardDetailContainer();
      addTearDown(container.dispose);
      await _loadedState(container, 'squirtle');

      expect(
        container
            .read(cardDetailControllerProvider('squirtle'))
            .marketPriceText,
        r'$32.13',
      );

      container
          .read(selectedCurrencyProvider.notifier)
          .select(AppCurrency.eur.withUsdRate(0.91));
      await container
          .read(cardDetailControllerProvider('squirtle').notifier)
          .loadComplete;
      final state = container.read(cardDetailControllerProvider('squirtle'));

      expect(
        state.marketPriceText,
        CurrencyFormatter(
          currency: AppCurrency.eur.withUsdRate(0.91),
        ).formatUsd(32.13),
      );
      expect(state.changeText, '+4.76%');
    },
  );

  test('missing price and change use CardDetail fallback copy', () async {
    final container = _cardDetailContainer();
    addTearDown(container.dispose);

    final state = await _loadedState(container, 'mystery-promo');

    expect(state.detail.name, 'Mystery Promo');
    expect(state.marketPriceText, '--');
    expect(state.changeText, '-/-');
    expect(state.marketRows.single.priceText, '--');
    expect(state.marketRows.single.changeText, '-/-');
  });

  test('missing Price Tab data exposes section fallback state', () async {
    final container = _cardDetailContainer();
    addTearDown(container.dispose);

    final state = await _loadedState(container, 'mystery-promo');

    expect(state.priceTabMarketRows.single.label, 'Raw');
    expect(state.priceTabMarketRows.single.priceText, '--');
    expect(state.priceTabMarketRows.single.changeText, '-/-');
    expect(state.priceSeriesRows, isEmpty);
    expect(state.hasPriceSeriesRows, isFalse);
    expect(state.priceSeriesFallbackText, 'No price data available.');
    expect(state.soldListingRows, isEmpty);
    expect(state.hasSoldListingRows, isFalse);
    expect(state.soldListingsFallbackText, 'No sold listings available.');
  });

  test(
    'Grade market rows omit product subtype because the grade column must contain only the score',
    () {
      const state = CardDetailState(
        cardId: 'pikachu',
        detail: CardDetail(
          id: 'pikachu',
          type: CardDetailType.tcg,
          name: 'Pikachu',
          game: 'Pokemon',
          setName: 'Base Set',
          identityLine: '58/102',
          finish: 'Normal',
          language: 'English',
          quantity: 0,
          isWishlisted: false,
          marketPrices: [
            CardMarketPrice(
              label: '7/7.5',
              grader: 'Grade',
              grade: 7.25,
              gradeLabel: '7/7.5',
              productSubType: '1st Edition',
              priceUsd: 253.24,
              previous30dPriceUsd: 253.24,
            ),
          ],
        ),
        currency: AppCurrency.usd,
        selectedMarketPriceCategory: CardMarketPriceCategory.grade,
      );

      expect(state.priceTabMarketRows.single.label, '7/7.5');
    },
  );

  test(
    'quick Collect updates from repository result and clears Wishlist because backend owns the item id',
    () async {
      final repository = _RecordingCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('one-piece-luffy');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'one-piece-luffy');

      expect(container.read(provider).detail.isWishlisted, isTrue);

      await controller.quickCollect();
      final collected = container.read(provider).detail;

      expect(repository.quickCollectCardRefs, ['one-piece-luffy']);
      expect(
        collected.collectionItems.single.id,
        'backend-item-one-piece-luffy',
      );
      expect(collected.quantity, 1);
      expect(collected.isCollected, isTrue);
      expect(collected.isWishlisted, isFalse);
    },
  );

  test(
    'wishlist toggle persists through repository because Wishlist must survive refresh',
    () async {
      final repository = _RecordingCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('squirtle');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'squirtle');

      await controller.toggleWishlist();

      expect(repository.addedWishlistCardRefs, ['squirtle']);
      expect(container.read(provider).detail.isWishlisted, isTrue);
      expect(
        container.read(provider).detail.wishlistItemId,
        'backend-wish-squirtle',
      );

      await controller.toggleWishlist();

      expect(repository.deletedWishlistItemIds, ['backend-wish-squirtle']);
      expect(container.read(provider).detail.isWishlisted, isFalse);
      expect(container.read(provider).detail.wishlistItemId, isNull);
    },
  );

  test(
    'asset mutation invalidates Home Collection and Search because portfolio state is shared across pages',
    () async {
      final container = _cardDetailContainer(includeAssetConsumers: true);
      addTearDown(container.dispose);
      final detailProvider = cardDetailControllerProvider('squirtle');
      final detailController = container.read(detailProvider.notifier);
      await _loadedState(container, 'squirtle');

      final homeState = container.read(homeControllerProvider);
      final collectionController = container.read(
        collectionControllerProvider.notifier,
      );
      await collectionController.loadComplete;
      final collectionState = container.read(collectionControllerProvider);
      final searchController = container.read(
        searchControllerProvider.notifier,
      );
      await searchController.loadComplete;
      final searchState = container.read(searchControllerProvider);

      await detailController.toggleWishlist();

      expect(container.read(homeControllerProvider), isNot(same(homeState)));
      expect(
        container.read(collectionControllerProvider),
        isNot(same(collectionState)),
      );
      expect(
        container.read(searchControllerProvider),
        isNot(same(searchState)),
      );
    },
  );

  test(
    'wishlist toggle keeps state when backend wishlist id is missing because delete needs a row id',
    () async {
      final repository = _WishlistWithoutIdCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('squirtle');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'squirtle');

      expect(container.read(provider).detail.isWishlisted, isTrue);
      expect(container.read(provider).detail.wishlistItemId, isNull);

      await controller.toggleWishlist();

      expect(repository.deletedWishlistItemIds, isEmpty);
      expect(container.read(provider).detail.isWishlisted, isTrue);
      expect(container.read(provider).detail.wishlistItemId, isNull);
    },
  );

  test(
    'quick Collect drops stale result after refresh because backend state may have changed while mutation was in flight',
    () async {
      final repository = _BlockingQuickCollectCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('one-piece-luffy');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'one-piece-luffy');

      final mutation = controller.quickCollect();
      await repository.quickCollectStarted.future;

      await controller.refresh();
      expect(container.read(provider).detail.isCollected, isFalse);
      expect(container.read(provider).detail.isWishlisted, isTrue);

      repository.completeQuickCollect();
      await mutation;

      final detail = container.read(provider).detail;
      expect(detail.isCollected, isFalse);
      expect(detail.collectionItems, isEmpty);
      expect(detail.isWishlisted, isTrue);
    },
  );

  test('owned detail exposes collection item rows', () async {
    final container = _cardDetailContainer();
    addTearDown(container.dispose);

    final state = await _loadedState(container, 'charizard-ex');

    expect(state.detail.isCollected, isTrue);
    expect(state.detail.quantity, 1);
    expect(state.collectionItemRows.single.portfolioName, 'Main');
    expect(state.collectionItemRows.single.quantityText, 'Qty: 1');
    expect(state.collectionItemRows.single.statusText, 'PSA 10');
    expect(state.collectionItemRows.single.purchasePriceText, r'$650.00');
    expect(
      state.collectionItemRows.single.marketPriceText,
      r'$780.00',
      reason:
          'Ownership summary must value the saved card state, not its cost.',
    );
    expect(state.collectionItemRows.single.notes, contains('Obsidian Flames'));
  });

  test(
    'quick Collect creates a default collection item and clears Wishlist',
    () async {
      final repository = _RecordingCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('one-piece-luffy');
      await _loadedState(container, 'one-piece-luffy');

      await container.read(provider.notifier).quickCollect();
      final state = container.read(provider);

      expect(repository.quickCollectCardRefs, ['one-piece-luffy']);
      expect(state.detail.isCollected, isTrue);
      expect(state.detail.isWishlisted, isFalse);
      expect(
        state.detail.collectionItems.single.id,
        'backend-item-one-piece-luffy',
      );
      expect(state.collectionItemRows.single.portfolioName, 'Main');
      expect(
        state.collectionItemRows.single.statusText,
        'Raw / Near Mint (NM)',
      );
      expect(state.collectionItemRows.single.purchasePriceText, '--');
    },
  );

  test(
    'adding a Collection Item appends an owned row and clears Wishlist',
    () async {
      final repository = _RecordingCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('squirtle');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'squirtle');

      controller.startAddingCollectionItem();
      controller.updateCollectionItemDraft(
        quantityText: '2',
        portfolioName: 'Sealed',
        grader: 'Raw',
        condition: 'Lightly Played (LP)',
        language: 'Japanese',
        finish: 'Reverse Holofoil',
        purchasePriceText: '12.50',
        notes: 'Second binder copy.',
      );

      expect(await controller.saveCollectionItemDraft(), isTrue);
      final state = container.read(provider);

      expect(repository.createdItemCardRefs, ['squirtle']);
      expect(state.detail.isCollected, isTrue);
      expect(state.detail.quantity, 2);
      expect(state.detail.isWishlisted, isFalse);
      expect(state.collectionItemRows.single.portfolioName, 'Sealed');
      expect(state.collectionItemRows.single.quantityText, 'Qty: 2');
      expect(
        state.collectionItemRows.single.statusText,
        'Raw / Lightly Played (LP)',
      );
      expect(state.collectionItemRows.single.languageText, 'Japanese');
      expect(state.collectionItemRows.single.finishText, 'Reverse Holofoil');
      expect(state.collectionItemRows.single.purchasePriceText, r'$12.50');
      expect(state.collectionItemRows.single.totalText, r'$25.00');
      expect(state.collectionItemRows.single.notes, 'Second binder copy.');
      expect(state.collectionItemDraft, isNull);
    },
  );

  test(
    'adding a Collection Item uses backend folder ids because folder names are presentation only',
    () async {
      final repository = _FolderAwareCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('squirtle');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'squirtle');

      controller.startAddingCollectionItem();
      controller.updateCollectionItemDraft(portfolioName: 'Sealed');

      expect(await controller.saveCollectionItemDraft(), isTrue);

      expect(repository.createdItems.single.folderId, 'folder-sealed-db');
      expect(
        container.read(provider).collectionItemRows.single.portfolioName,
        'Sealed',
      );
    },
  );

  test(
    'duplicate card finish and language keeps the draft open with a clear error',
    () async {
      final container = _cardDetailContainer(
        repository: _DuplicateCollectionItemRepository(),
      );
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('squirtle');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'squirtle');

      controller.startAddingCollectionItem();

      expect(await controller.saveCollectionItemDraft(), isFalse);
      final state = container.read(provider);
      expect(state.collectionItemDraft, isNotNull);
      expect(state.collectionItemFormError, duplicateCollectionItemMessage);
    },
  );

  test(
    'new Collection Item uses the shared selected folder because Card Detail must continue the Collection and Search context',
    () async {
      final container = _cardDetailContainer(
        repository: _FolderAwareCardDetailRepository(),
      );
      addTearDown(container.dispose);
      container
          .read(selectedPortfolioFolderProvider.notifier)
          .select('folder-sealed-db');
      final provider = cardDetailControllerProvider('squirtle');
      await _loadedState(container, 'squirtle');

      container.read(provider.notifier).startAddingCollectionItem();

      expect(
        container.read(provider).collectionItemDraft!.portfolioName,
        'Sealed',
      );
    },
  );

  test(
    'new Collection Item values the selected market condition times quantity',
    () async {
      final container = _cardDetailContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('squirtle');
      await _loadedState(container, 'squirtle');

      container.read(provider.notifier).startAddingCollectionItem();
      final draft = container.read(provider).collectionItemDraft!;

      expect(cardCollectionConditions, [
        'Near Mint (NM)',
        'Lightly Played (LP)',
        'Moderately Played (MP)',
        'Heavily Played (HP)',
        'Damaged (D)',
      ]);
      expect(cardCollectionConditions, isNot(contains('Nearly Mint (NM)')));
      expect(draft.portfolioName, 'Main');
      expect(draft.language, 'English');
      expect(draft.finish, 'Holofoil');
      expect(
        container.read(provider).collectionItemDraftSelectionText,
        'Holofoil · Raw · Near Mint',
      );
      expect(
        container.read(provider).collectionItemDraftMarketPriceText,
        r'$32.13',
      );
      expect(container.read(provider).collectionItemDraftTotalText, r'$32.13');

      container
          .read(provider.notifier)
          .updateCollectionItemDraft(quantityText: '3');
      expect(container.read(provider).collectionItemDraftTotalText, r'$96.39');

      container
          .read(provider.notifier)
          .updateCollectionItemDraft(finish: 'Normal');
      expect(
        container.read(provider).collectionItemDraftMarketPriceText,
        '--',
        reason: 'A selected Finish must never reuse another Finish price.',
      );
    },
  );

  test(
    'new Collection Item keeps unknown qualifiers when no SKU options exist because the app must not invent variants',
    () async {
      final repository = _UnknownQualifierCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('unknown-qualifiers');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'unknown-qualifiers');

      controller.startAddingCollectionItem();
      final draft = container.read(provider).collectionItemDraft!;
      expect(draft.language, 'Unknown');
      expect(draft.finish, 'Unknown');

      expect(await controller.saveCollectionItemDraft(), isTrue);
      expect(repository.createdItems.single.language, 'Unknown');
      expect(repository.createdItems.single.finish, 'Unknown');
    },
  );

  test(
    'Purchase Price converts separately because total value remains market-based',
    () async {
      final repository = _RecordingCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final currency = AppCurrency.eur.withUsdRate(0.91);
      container.read(selectedCurrencyProvider.notifier).select(currency);
      final provider = cardDetailControllerProvider('squirtle');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'squirtle');

      controller.startAddingCollectionItem();
      controller.updateCollectionItemDraft(purchasePriceText: '91');

      expect(container.read(provider).collectionItemDraftTotalText, '€29.24');
      expect(await controller.saveCollectionItemDraft(), isTrue);
      expect(repository.createdItems.single.purchasePriceUsd, 100);
      expect(
        container.read(provider).collectionItemRows.single.purchasePriceText,
        '€91.00',
      );
    },
  );

  test(
    'changing grader resets grade options to the selected grader scale',
    () async {
      final container = _cardDetailContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('squirtle');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'squirtle');

      controller.startAddingCollectionItem();
      controller.updateCollectionItemDraft(grader: 'BGS');
      final draft = container.read(provider).collectionItemDraft!;

      expect(draft.grade, '10');
      expect(cardCollectionGradeLabelsFor('BGS').take(3), [
        'BGS 10',
        'BGS 9.5',
        'BGS 9',
      ]);
    },
  );

  test(
    'opening Collection Item edit reloads its language and finish because the total must use that exact price dimension',
    () async {
      final cardDataApi = _QualifierSwitchingCardDataApi();
      final now = DateTime.parse('2026-01-01T00:00:00.000Z');
      final repository = HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [
            PortfolioFolderDto(
              id: 'main',
              name: 'Main',
              isDefault: true,
              sortOrder: 0,
            ),
          ],
          items: [
            PortfolioItemDto(
              id: 'item-japanese',
              folderId: 'main',
              cardRef: 'catalog:pikachu-025',
              objectType: 'tcg',
              grader: 'PSA',
              condition: null,
              grade: 9,
              language: 'Japanese',
              finish: 'Normal',
              quantity: 2,
              purchasePrice: null,
              purchaseCurrency: null,
              notes: null,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          wishlist: const [],
        ),
        cardDataApi: cardDataApi,
      );
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('catalog:pikachu-025');
      await _loadedState(container, 'catalog:pikachu-025');
      await _drainSectionLoads();

      await container
          .read(provider.notifier)
          .startEditingCollectionItem('item-japanese');

      final edited = container.read(provider);
      expect(cardDataApi.marketSelections.last, ('Normal', 'Japanese'));
      expect(edited.marketPricesStatus, KandoLoadStatus.content);
      expect(edited.priceFinish, 'Normal');
      expect(edited.collectionItemDraft?.grader, 'PSA');
      expect(edited.collectionItemDraft?.grade, '9');
      expect(edited.collectionItemDraft?.language, 'Japanese');
      expect(
        edited.detail.marketPrices,
        contains(
          isA<CardMarketPrice>()
              .having((price) => price.grader, 'grader', 'GENERIC')
              .having((price) => price.grade, 'grade', 9)
              .having((price) => price.priceUsd, 'price', 42),
        ),
      );
      expect(edited.collectionItemDraftMarketPriceText, r'$42.00');
      expect(edited.collectionItemDraftTotalText, r'$84.00');
    },
  );

  test(
    'late initial prices cannot overwrite Collection Item qualifiers because the editor total must stay on the selected variant',
    () async {
      final cardDataApi = _LateInitialQualifierCardDataApi();
      final now = DateTime.parse('2026-01-01T00:00:00.000Z');
      final repository = HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [
            PortfolioFolderDto(
              id: 'main',
              name: 'Main',
              isDefault: true,
              sortOrder: 0,
            ),
          ],
          items: [
            PortfolioItemDto(
              id: 'item-japanese',
              folderId: 'main',
              cardRef: 'catalog:pikachu-025',
              objectType: 'tcg',
              grader: 'PSA',
              condition: null,
              grade: 9,
              language: 'Japanese',
              finish: 'Normal',
              quantity: 2,
              purchasePrice: null,
              purchaseCurrency: null,
              notes: null,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          wishlist: const [],
        ),
        cardDataApi: cardDataApi,
      );
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('catalog:pikachu-025');
      await _loadedState(container, 'catalog:pikachu-025');
      await cardDataApi.initialMarketRequested.future;
      await _drainSectionLoads();

      await container
          .read(provider.notifier)
          .startEditingCollectionItem('item-japanese');
      expect(container.read(provider).collectionItemDraftTotalText, r'$84.00');

      cardDataApi.completeInitialMarket();
      await _drainSectionLoads();

      final edited = container.read(provider);
      expect(edited.priceFinish, 'Normal');
      expect(edited.collectionItemDraft?.language, 'Japanese');
      expect(edited.collectionItemDraftMarketPriceText, r'$42.00');
      expect(edited.collectionItemDraftTotalText, r'$84.00');
    },
  );

  test(
    'editing a Collection Item switches graded state to Raw state',
    () async {
      final repository = _RecordingCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'charizard-ex');

      await controller.startEditingCollectionItem('item-charizard');
      controller.updateCollectionItemDraft(
        quantityText: '3',
        grader: 'Raw',
        condition: 'Near Mint (NM)',
        purchasePriceText: '640',
        notes: 'Cracked slab for binder.',
      );

      expect(await controller.saveCollectionItemDraft(), isTrue);
      final row = container.read(provider).collectionItemRows.single;

      expect(repository.updatedItemIds, ['item-charizard']);
      expect(row.quantityText, 'Qty: 3');
      expect(row.statusText, 'Raw / Near Mint (NM)');
      expect(row.purchasePriceText, r'$640.00');
      expect(row.notes, 'Cracked slab for binder.');
    },
  );

  test(
    'a stale target Folder refreshes Collection without moving the Item because remote deletion must not leave a false move result',
    () async {
      final repository = _MissingTargetFolderCardDetailRepository();
      final container = _cardDetailContainer(
        repository: repository,
        includeAssetConsumers: true,
      );
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'charizard-ex');
      final collectionController = container.read(
        collectionControllerProvider.notifier,
      );
      await collectionController.loadComplete;
      final collectionBeforeMove = container.read(collectionControllerProvider);

      await controller.startEditingCollectionItem('item-charizard');
      controller.updateCollectionItemDraft(
        portfolioName: 'Sealed',
        notes: 'Keep this input after the failed move.',
      );

      await expectLater(
        controller.saveCollectionItemDraft(),
        throwsA(
          isA<PortfolioApiException>().having(
            (error) => error.code,
            'code',
            'NOT_FOUND',
          ),
        ),
      );
      final state = container.read(provider);

      expect(state.collectionItemRows.single.portfolioName, 'Main');
      expect(state.collectionItemDraft, isNotNull);
      expect(
        state.collectionItemDraft!.notes,
        'Keep this input after the failed move.',
      );
      expect(state.isSavingCollectionItemDraft, isFalse);
      expect(
        container.read(collectionControllerProvider),
        isNot(same(collectionBeforeMove)),
      );
    },
  );

  test(
    'a successful Folder Move invalidates Source and Target Performance because both folder histories changed',
    () async {
      final performanceApi = _ImmediatePerformanceApi();
      final container = _cardDetailContainer(
        repository: _FolderAwareCardDetailRepository(),
        includeAssetConsumers: true,
        portfolioApi: performanceApi,
      );
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'charizard-ex');
      await container
          .read(homePerformanceControllerProvider.notifier)
          .load(folderId: 'folder-main-db', localPremiumVerified: true);
      expect(container.read(homePerformanceControllerProvider).hasLoaded, true);

      await controller.startEditingCollectionItem('item-charizard');
      controller.updateCollectionItemDraft(portfolioName: 'Sealed');

      expect(await controller.saveCollectionItemDraft(), isTrue);
      expect(
        container.read(provider).collectionItemRows.single.portfolioName,
        'Sealed',
      );
      expect(
        container.read(homePerformanceControllerProvider).hasLoaded,
        false,
      );
    },
  );

  test(
    'invalid Collection Item draft stays open with validation copy',
    () async {
      final container = _cardDetailContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'charizard-ex');

      await controller.startEditingCollectionItem('item-charizard');
      controller.updateCollectionItemDraft(quantityText: '0');

      expect(await controller.saveCollectionItemDraft(), isFalse);
      final state = container.read(provider);

      expect(state.collectionItemDraft, isNotNull);
      expect(state.collectionItemFormError, 'Quantity must be at least 1.');
      expect(state.collectionItemRows.single.quantityText, 'Qty: 1');
    },
  );

  test(
    'removing the final Collection Item returns detail to uncollected state',
    () async {
      final repository = _RecordingCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');
      await _loadedState(container, 'charizard-ex');

      await container
          .read(provider.notifier)
          .removeCollectionItem('item-charizard');
      final state = container.read(provider);

      expect(repository.deletedCollectionItemIds, ['item-charizard']);
      expect(state.detail.isCollected, isFalse);
      expect(state.detail.quantity, 0);
      expect(state.collectionItemRows, isEmpty);
    },
  );

  test(
    'price tab exposes default range series, market rows, and sold listings',
    () async {
      final container = _cardDetailContainer();
      addTearDown(container.dispose);

      final state = await _loadedState(container, 'charizard-ex');

      expect(CardPriceRange.values.map((range) => range.label), [
        '1d',
        '7d',
        '15d',
        '1m',
        '3m',
        '1y',
      ]);
      expect(state.selectedPriceChartMode, CardPriceChartMode.raw);
      expect(state.selectedPriceRange, CardPriceRange.oneMonth);
      expect(
        state.selectedMarketPriceCategory,
        CardMarketPriceCategory.ungraded,
      );
      expect(state.priceSeriesRows.last.dateLabel, 'Today');
      expect(state.priceSeriesRows.last.priceText, r'$215.00');
      expect(state.priceTabMarketRows.first.label, 'Near Mint (NM)');
      expect(state.priceTabMarketRows.first.changeText, startsWith('+'));
      expect(state.soldListingRows.first.platform, 'eBay');
      expect(state.soldListingRows.first.priceText, r'$780.00');
    },
  );

  test(
    'selecting a price range changes only the visible series rows',
    () async {
      final container = _cardDetailContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');
      await _loadedState(container, 'charizard-ex');

      container
          .read(provider.notifier)
          .selectPriceChartMode(CardPriceChartMode.graded);
      container
          .read(provider.notifier)
          .selectPriceRange(CardPriceRange.threeMonths);
      container
          .read(provider.notifier)
          .selectMarketPriceCategory(CardMarketPriceCategory.psa);
      final state = container.read(provider);

      expect(state.selectedPriceChartMode, CardPriceChartMode.graded);
      expect(state.selectedPriceRange, CardPriceRange.threeMonths);
      expect(state.priceSeriesRows.first.dateLabel, '90 days ago');
      expect(state.priceSeriesRows.last.priceText, r'$780.00');
      expect(state.selectedMarketPriceCategory, CardMarketPriceCategory.psa);
      expect(state.priceTabMarketRows.first.label, '10');
    },
  );

  test('repository failure shows failure state and refresh recovers', () async {
    final repository = _FailingThenSuccessfulCardDetailRepository();
    final container = _cardDetailContainer(repository: repository);
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('squirtle');

    final failed = await _loadedState(container, 'squirtle');

    expect(failed.loadStatus, KandoLoadStatus.failure);
    expect(failed.isUnavailable, isTrue);
    expect(repository.calls, 1);

    await container.read(provider.notifier).refresh();
    final restored = container.read(provider);

    expect(restored.loadStatus, KandoLoadStatus.content);
    expect(restored.isUnavailable, isFalse);
    expect(restored.detail.name, 'Squirtle');
    expect(repository.calls, 2);
  });

  test(
    'switching finish replaces both Raw condition charts and market rows because materials must never share prices',
    () async {
      final cardDataApi = _FinishSwitchingCardDataApi();
      final repository = HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [],
          items: const [],
          wishlist: const [],
        ),
        cardDataApi: cardDataApi,
      );
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('catalog:pikachu-025');

      await _loadedState(container, 'catalog:pikachu-025');
      await _drainSectionLoads();
      expect(container.read(provider).priceFinish, 'Holofoil');

      await container.read(provider.notifier).selectPriceFinish('Normal');
      final normal = container.read(provider);

      expect(normal.priceFinish, 'Normal');
      expect(normal.detail.rawPriceSeries.map((series) => series.label), [
        'Near Mint',
        'Lightly Played',
        'Moderately Played',
      ]);
      expect(normal.priceTabMarketRows.map((row) => row.priceText), [
        r'$25.00',
        r'$20.00',
        r'$15.00',
      ]);
      expect(
        normal.priceTabMarketRows.first.changeText,
        '+25.00%',
        reason:
            '7D change must use the PostgreSQL snapshot baseline (25 vs 20), not a sparse chart point (25 vs 24).',
      );
      expect(cardDataApi.marketFinishes.last, 'Normal');
      expect(
        cardDataApi.seriesFinishes.whereType<String>().toSet(),
        contains('Normal'),
      );
    },
  );

  test(
    'sectioned detail load completes after base detail because optional endpoints render independently',
    () async {
      final repository = _BlockingOptionalSectionRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');

      await container.read(authControllerProvider.notifier).startupComplete;
      final controller = container.read(provider.notifier);
      await controller.loadComplete.timeout(const Duration(milliseconds: 100));

      final baseLoaded = container.read(provider);
      expect(baseLoaded.loadStatus, KandoLoadStatus.content);
      expect(baseLoaded.detail.name, 'Charizard ex');
      expect(baseLoaded.marketPricesStatus, KandoLoadStatus.loading);
      expect(baseLoaded.priceSeriesStatus, KandoLoadStatus.loading);
      expect(baseLoaded.soldListingsStatus, KandoLoadStatus.loading);

      repository.completeOptionalSections();
      await Future<void>.delayed(Duration.zero);

      final sectionsLoaded = container.read(provider);
      expect(sectionsLoaded.marketPricesStatus, KandoLoadStatus.content);
      expect(sectionsLoaded.priceSeriesStatus, KandoLoadStatus.content);
      expect(sectionsLoaded.soldListingsStatus, KandoLoadStatus.content);
    },
  );

  test(
    'optional detail sections recover independently because one endpoint must not replace the base card with a page failure',
    () async {
      final cardDataApi = _RecoveringSectionCardDataApi();
      final repository = HttpCardDetailRepository(
        api: _FakePortfolioApiClient(
          folders: const [],
          items: const [],
          wishlist: const [],
        ),
        cardDataApi: cardDataApi,
      );
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('catalog:pikachu-025');

      final failedSections = await _loadedState(
        container,
        'catalog:pikachu-025',
      );
      await _drainSectionLoads();

      expect(failedSections.loadStatus, KandoLoadStatus.content);
      expect(failedSections.detail.name, 'Pikachu');
      final failedSectionState = container.read(provider);
      expect(failedSectionState.marketPricesStatus, KandoLoadStatus.failure);
      expect(failedSectionState.priceSeriesStatus, KandoLoadStatus.failure);
      expect(failedSectionState.soldListingsStatus, KandoLoadStatus.failure);

      final controller = container.read(provider.notifier);
      await controller.refreshMarketPrices();
      expect(
        container.read(provider).marketPricesStatus,
        KandoLoadStatus.content,
      );
      expect(
        container.read(provider).priceSeriesStatus,
        KandoLoadStatus.failure,
      );
      await controller.refreshPriceSeries();
      expect(
        container.read(provider).priceSeriesStatus,
        KandoLoadStatus.content,
      );
      await controller.refreshSoldListings();
      expect(
        container.read(provider).soldListingsStatus,
        KandoLoadStatus.content,
      );
    },
  );
}

class _FailingThenSuccessfulCardDetailRepository
    implements CardDetailRepository {
  var calls = 0;

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock detail unavailable');
    }
    return const MockCardDetailRepository().loadDetail(session, cardId);
  }

  @override
  Future<CardCollectionItem> quickCollect(
    AuthSession session,
    CardDetail detail,
  ) {
    return const MockCardDetailRepository().quickCollect(session, detail);
  }

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) {
    return const MockCardDetailRepository().createCollectionItem(
      session,
      detail: detail,
      item: item,
    );
  }

  @override
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) {
    return const MockCardDetailRepository().updateCollectionItem(
      session,
      detail: detail,
      item: item,
    );
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) {
    return const MockCardDetailRepository().deleteCollectionItem(
      session,
      itemId,
    );
  }

  @override
  Future<String> addWishlist(AuthSession session, String cardRef) {
    return const MockCardDetailRepository().addWishlist(session, cardRef);
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String wishlistItemId) {
    return const MockCardDetailRepository().deleteWishlist(
      session,
      wishlistItemId,
    );
  }
}

class _BlockingOptionalSectionRepository extends _RecordingCardDetailRepository
    implements CardDetailSectionRepository {
  final _marketCompleter = Completer<CardDetailMarketData>();
  final _seriesCompleter = Completer<CardDetailSeriesData>();
  final _soldListingsCompleter = Completer<List<CardSoldListing>>();

  @override
  Future<CardDetail> loadCoreDetail(String cardId) {
    return super.loadDetail(_session, cardId);
  }

  @override
  Future<CardDetail> loadAssetState(
    AuthSession session,
    CardDetail detail,
  ) async {
    return detail;
  }

  @override
  Future<CardDetail> loadBaseDetail(AuthSession session, String cardId) {
    return super.loadDetail(session, cardId);
  }

  @override
  Future<CardDetailMarketData> loadMarketPrices(
    String cardId, {
    String? finish,
    String? language,
  }) {
    return _marketCompleter.future;
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
    return _seriesCompleter.future;
  }

  @override
  Future<List<CardSoldListing>> loadSoldListings(String cardId) {
    return _soldListingsCompleter.future;
  }

  void completeOptionalSections() {
    if (!_marketCompleter.isCompleted) {
      _marketCompleter.complete(
        const CardDetailMarketData(prices: [], marketPrices: []),
      );
    }
    if (!_seriesCompleter.isCompleted) {
      _seriesCompleter.complete(
        const CardDetailSeriesData(
          marketPrices: [],
          rawSeriesByRange: {},
          gradedSeriesByRange: {},
        ),
      );
    }
    if (!_soldListingsCompleter.isCompleted) {
      _soldListingsCompleter.complete(const []);
    }
  }
}

class _RecordingCardDetailRepository implements CardDetailRepository {
  final List<String> quickCollectCardRefs = [];
  final List<String> addedWishlistCardRefs = [];
  final List<String> deletedWishlistItemIds = [];
  final List<String> createdItemCardRefs = [];
  final List<CardCollectionItem> createdItems = [];
  final List<String> updatedItemIds = [];
  final List<String> deletedCollectionItemIds = [];

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) {
    return const MockCardDetailRepository().loadDetail(session, cardId);
  }

  @override
  Future<CardCollectionItem> quickCollect(
    AuthSession session,
    CardDetail detail,
  ) async {
    quickCollectCardRefs.add(detail.id);
    return CardCollectionItem(
      id: 'backend-item-${detail.id}',
      cardRef: detail.id,
      folderId: 'main',
      portfolioName: 'Main',
      quantity: 1,
      grader: 'Raw',
      condition: 'Near Mint (NM)',
      grade: null,
      language: detail.language,
      finish: detail.finish,
      purchasePriceUsd: null,
      notes: 'Quick collected from CardDetail.',
    );
  }

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    createdItemCardRefs.add(detail.id);
    createdItems.add(item);
    return item.copyWith(cardRef: detail.id, folderId: item.folderId ?? 'main');
  }

  @override
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    updatedItemIds.add(item.id);
    return item.copyWith(cardRef: detail.id);
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) async {
    deletedCollectionItemIds.add(itemId);
  }

  @override
  Future<String> addWishlist(AuthSession session, String cardRef) async {
    addedWishlistCardRefs.add(cardRef);
    return 'backend-wish-$cardRef';
  }

  @override
  Future<void> deleteWishlist(
    AuthSession session,
    String wishlistItemId,
  ) async {
    deletedWishlistItemIds.add(wishlistItemId);
  }
}

class _DuplicateCollectionItemRepository
    extends _RecordingCardDetailRepository {
  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) {
    throw const PortfolioApiException(
      duplicateCollectionItemMessage,
      code: duplicateCollectionItemErrorCode,
      statusCode: 409,
    );
  }
}

class _MissingTargetFolderCardDetailRepository
    extends _RecordingCardDetailRepository {
  @override
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) {
    throw const PortfolioApiException(
      'Not found.',
      code: 'NOT_FOUND',
      statusCode: 404,
    );
  }
}

class _WishlistWithoutIdCardDetailRepository
    extends _RecordingCardDetailRepository {
  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await super.loadDetail(session, cardId);
    return detail.copyWith(isWishlisted: true, wishlistItemId: null);
  }
}

class _UnknownQualifierCardDetailRepository
    extends _RecordingCardDetailRepository {
  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    return const CardDetail(
      id: 'unknown-qualifiers',
      type: CardDetailType.tcg,
      name: 'Oricorio ex',
      game: 'Pokemon',
      setName: 'Mega Evolution Promo',
      identityLine: 'Promo #024',
      finish: 'Unknown',
      language: 'Unknown',
      quantity: 0,
      isWishlisted: false,
      marketPrices: [
        CardMarketPrice(
          label: 'Raw Moderately Played',
          grader: 'Raw',
          condition: 'Moderately Played',
          priceUsd: 11.23,
          previous30dPriceUsd: null,
        ),
      ],
      portfolioFolders: [
        CardPortfolioFolder(id: 'main', name: 'Main', isDefault: true),
      ],
    );
  }
}

class _BlockingQuickCollectCardDetailRepository
    extends _RecordingCardDetailRepository {
  final quickCollectStarted = Completer<void>();
  final _quickCollectCompleter = Completer<CardCollectionItem>();

  @override
  Future<CardCollectionItem> quickCollect(
    AuthSession session,
    CardDetail detail,
  ) {
    quickCollectCardRefs.add(detail.id);
    if (!quickCollectStarted.isCompleted) {
      quickCollectStarted.complete();
    }
    return _quickCollectCompleter.future;
  }

  void completeQuickCollect() {
    _quickCollectCompleter.complete(
      const CardCollectionItem(
        id: 'stale-backend-item-one-piece-luffy',
        cardRef: 'one-piece-luffy',
        folderId: 'main',
        portfolioName: 'Main',
        quantity: 1,
        grader: 'Raw',
        condition: 'Near Mint (NM)',
        grade: null,
        language: 'Japanese',
        finish: 'Normal',
        purchasePriceUsd: null,
        notes: 'Stale quick collect result.',
      ),
    );
  }
}

class _FolderAwareCardDetailRepository extends _RecordingCardDetailRepository {
  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await super.loadDetail(session, cardId);
    return detail.copyWith(
      portfolioFolders: const [
        CardPortfolioFolder(
          id: 'folder-main-db',
          name: 'Main',
          isDefault: true,
        ),
        CardPortfolioFolder(id: 'folder-sealed-db', name: 'Sealed'),
      ],
    );
  }
}

ProviderContainer _cardDetailContainer({
  CardDetailRepository repository = const MockCardDetailRepository(),
  bool includeAssetConsumers = false,
  PortfolioApiClient? portfolioApi,
}) {
  final storage = InMemoryAuthStorage();
  return ProviderContainer(
    overrides: [
      authStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(storage),
      ),
      cardDetailRepositoryProvider.overrideWithValue(repository),
      if (portfolioApi != null)
        portfolioApiClientProvider.overrideWithValue(portfolioApi),
      if (includeAssetConsumers) ...[
        homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        collectionRepositoryProvider.overrideWithValue(
          const MockCollectionRepository(),
        ),
        searchRepositoryProvider.overrideWithValue(
          const MockSearchRepository(),
        ),
      ],
    ],
  );
}

class _ImmediatePerformanceApi extends PortfolioApiClient {
  _ImmediatePerformanceApi() : super(Dio());

  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
  }) async {
    final point = PerformancePointDto(
      date: '2026-08-13',
      marketValueUsd: 100,
      marketValueChangeUsd: 0,
      marketChangeUsd: 0,
      portfolioChangeUsd: 0,
      paidMarketValueUsd: 100,
      totalPaidUsd: 80,
      profitLossUsd: 20,
      profitLossChangeUsd: 0,
      returnPercent: 25,
      quantity: 1,
      quantityChange: 0,
    );
    return PortfolioPerformanceDto(
      range: range,
      rangeStart: '2026-07-13',
      rangeEnd: '2026-08-13',
      historyAvailableFrom: '2026-07-13',
      partialHistory: false,
      itemCount: 1,
      marketPriceStatus: MarketPriceStatus.available,
      purchasePriceStatus: PurchasePriceStatus.complete,
      current: point,
      series: [point],
    );
  }
}

Future<CardDetailState> _loadedState(
  ProviderContainer container,
  String cardId,
) async {
  await container.read(authControllerProvider.notifier).startupComplete;
  await container
      .read(cardDetailControllerProvider(cardId).notifier)
      .loadComplete;
  return container.read(cardDetailControllerProvider(cardId));
}

Future<void> _drainSectionLoads() async {
  for (var i = 0; i < 5; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakePortfolioApiClient implements PortfolioApi {
  _FakePortfolioApiClient({
    required this.folders,
    required this.items,
    required this.wishlist,
    this.quickCollectResult,
  });

  final List<PortfolioFolderDto> folders;
  final List<PortfolioItemDto> items;
  final List<WishlistItemDto> wishlist;
  final PortfolioItemDto? quickCollectResult;
  final List<String> quickCollectCardRefs = [];
  final List<PortfolioItemDraftDto> quickCollectDrafts = [];

  @override
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session) async {
    return folders;
  }

  @override
  Future<List<PortfolioFolderValuationDto>> getValuationHistory(
    AuthSession session, {
    int days = 90,
    bool localPremiumVerified = false,
  }) async => const [];

  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
  }) => throw UnimplementedError();

  @override
  Future<PortfolioPerformanceDto> getItemPerformance(
    AuthSession session, {
    required String itemId,
    required PerformanceRange range,
    bool localPremiumVerified = false,
  }) => throw UnimplementedError();

  @override
  Future<List<PortfolioItemDto>> listCollectionItems(
    AuthSession session,
  ) async {
    return items;
  }

  @override
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session) async {
    return wishlist;
  }

  @override
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  }) async {
    quickCollectCardRefs.add(cardRef);
    quickCollectDrafts.add(draft);
    return quickCollectResult ??
        _portfolioItem(id: 'quick-item', cardRef: cardRef);
  }

  @override
  Future<PortfolioItemDto> createCollectionItem(
    AuthSession session,
    PortfolioItemDraftDto draft,
  ) async {
    return _portfolioItem(
      id: 'created-item',
      folderId: draft.folderId,
      cardRef: draft.cardRef,
    );
  }

  @override
  Future<PortfolioItemDto> updateCollectionItem(
    AuthSession session, {
    required String itemId,
    required PortfolioItemDraftDto draft,
  }) async {
    return _portfolioItem(
      id: itemId,
      folderId: draft.folderId,
      cardRef: draft.cardRef,
    );
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) async {}

  @override
  Future<WishlistItemDto> addWishlist(
    AuthSession session,
    String cardRef,
  ) async {
    return WishlistItemDto(
      id: 'wish-$cardRef',
      cardRef: cardRef,
      createdAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
    );
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) async {}
}

class _BlockingPortfolioApiClient extends _FakePortfolioApiClient {
  _BlockingPortfolioApiClient()
    : super(folders: const [], items: const [], wishlist: const []);

  final started = Completer<void>();
  final _release = Completer<void>();

  void release() => _release.complete();

  Future<void> _wait() async {
    if (!started.isCompleted) started.complete();
    await _release.future;
  }

  @override
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session) async {
    await _wait();
    return super.listFolders(session);
  }

  @override
  Future<List<PortfolioItemDto>> listCollectionItems(
    AuthSession session,
  ) async {
    await _wait();
    return super.listCollectionItems(session);
  }

  @override
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session) async {
    await _wait();
    return super.listWishlistItems(session);
  }
}

class _FakeCardDataApi implements CardDataApi, BatchCardDataApi {
  _FakeCardDataApi({
    this.card = _pikachuCard,
    this.failMarketPrices = false,
    this.failPriceSeries = false,
    this.failPriceSeriesBatch = false,
    this.failSoldListings = false,
  });

  final CardDataCardDto card;
  final bool failMarketPrices;
  final bool failPriceSeries;
  final bool failPriceSeriesBatch;
  final bool failSoldListings;
  final List<String> cardRefs = [];
  var activeSeriesRequests = 0;
  var maxConcurrentSeriesRequests = 0;
  var totalSeriesRequests = 0;
  var priceSeriesBatchCalls = 0;

  @override
  Future<List<CardDataCardDto>> searchCards(
    String query, {
    String? game,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataSetDto>> searchSets(String query, {String? game}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataCardDto>> trendingCards() async {
    throw UnimplementedError();
  }

  @override
  Future<CardDataCardDto> getCard(String cardRef) async {
    cardRefs.add(cardRef);
    return card;
  }

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(
    String cardRef, {
    String? finish,
    String? language,
  }) async {
    if (failMarketPrices) {
      throw StateError('market prices unavailable');
    }
    return const [
      CardDataMarketPriceDto(
        grader: 'Raw',
        grade: null,
        condition: 'Near Mint',
        price: 15,
        previous7dPriceUsd: 14,
      ),
      CardDataMarketPriceDto(
        grader: 'PSA',
        grade: 10,
        gradeLabel: '10',
        condition: null,
        price: 70,
        pricechartingId: 'pc-pikachu-psa-10',
        productSubType: 'Holofoil',
        previous7dPriceUsd: 65,
        increasePercent: 7.69,
        history: [
          CardDataPricePointDto(date: '2026-04-10', price: 40),
          CardDataPricePointDto(date: '2026-06-10', price: 50),
          CardDataPricePointDto(date: '2026-07-04', price: 65),
          CardDataPricePointDto(date: '2026-07-10', price: 70),
        ],
      ),
    ];
  }

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
    String? finish,
  }) async {
    if (failPriceSeries) {
      throw StateError('price series unavailable');
    }
    totalSeriesRequests += 1;
    activeSeriesRequests += 1;
    if (activeSeriesRequests > maxConcurrentSeriesRequests) {
      maxConcurrentSeriesRequests = activeSeriesRequests;
    }
    await Future<void>.delayed(Duration.zero);
    activeSeriesRequests -= 1;
    final current = grader == 'Raw' ? 15.0 : 70.0;
    final previous = switch ((grader, days)) {
      ('Raw', 7) => 14.0,
      ('Raw', 30) => 10.0,
      ('PSA', 90) => 40.0,
      ('PSA', 30) => 50.0,
      ('PSA', 7) => 65.0,
      _ => current,
    };
    return [
      CardDataPricePointDto(date: '2026-06-10', price: previous),
      CardDataPricePointDto(date: '2026-07-10', price: current),
    ];
  }

  @override
  Future<List<List<CardDataPricePointDto>>> getPriceSeriesBatch(
    String cardRef,
    List<CardDataPriceSeriesQuery> requests,
  ) {
    priceSeriesBatchCalls += 1;
    if (failPriceSeriesBatch) {
      throw StateError('batch price series unavailable');
    }
    return Future.wait(
      requests.map(
        (request) => getPriceSeries(
          cardRef,
          days: request.days,
          grader: request.grader,
          grade: request.grade,
          condition: request.condition,
          finish: request.finish,
        ),
      ),
    );
  }

  @override
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef) async {
    if (failSoldListings) {
      throw StateError('sold listings unavailable');
    }
    return const [
      CardDataSoldListingDto(
        date: '2026-07-09',
        title: 'Pikachu Base Set Holofoil',
        price: 15,
        platform: 'eBay',
      ),
    ];
  }
}

class _FinishSwitchingCardDataApi extends _FakeCardDataApi {
  final List<String?> marketFinishes = [];
  final List<String?> seriesFinishes = [];

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(
    String cardRef, {
    String? finish,
    String? language,
  }) async {
    marketFinishes.add(finish);
    if (finish != 'Normal') {
      return super.getMarketPrices(cardRef, finish: finish);
    }
    return const [
      CardDataMarketPriceDto(
        grader: 'Raw',
        grade: null,
        condition: 'Near Mint',
        price: 25,
        previous7dPriceUsd: 20,
        increasePercent: 25,
      ),
      CardDataMarketPriceDto(
        grader: 'Raw',
        grade: null,
        condition: 'Lightly Played',
        price: 20,
      ),
      CardDataMarketPriceDto(
        grader: 'Raw',
        grade: null,
        condition: 'Moderately Played',
        price: 15,
      ),
    ];
  }

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
    String? finish,
  }) async {
    seriesFinishes.add(finish);
    final current = switch (condition) {
      'Near Mint' => 25.0,
      'Lightly Played' => 20.0,
      'Moderately Played' => 15.0,
      _ => 10.0,
    };
    return [
      CardDataPricePointDto(date: '2026-07-01', price: current - 1),
      CardDataPricePointDto(date: '2026-07-30', price: current),
    ];
  }
}

class _QualifierSwitchingCardDataApi extends _FakeCardDataApi {
  final List<(String?, String?)> marketSelections = [];

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(
    String cardRef, {
    String? finish,
    String? language,
  }) async {
    marketSelections.add((finish, language));
    if (finish == 'Normal' && language == 'Japanese') {
      return const [
        CardDataMarketPriceDto(
          grader: 'GENERIC',
          grade: 9,
          gradeLabel: '9',
          condition: null,
          price: 42,
        ),
      ];
    }
    return super.getMarketPrices(cardRef, finish: finish, language: language);
  }
}

class _LateInitialQualifierCardDataApi extends _QualifierSwitchingCardDataApi {
  final initialMarketRequested = Completer<void>();
  final _initialMarket = Completer<List<CardDataMarketPriceDto>>();

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(
    String cardRef, {
    String? finish,
    String? language,
  }) {
    if (finish == 'Holofoil' && language == 'English') {
      marketSelections.add((finish, language));
      if (!initialMarketRequested.isCompleted) {
        initialMarketRequested.complete();
      }
      return _initialMarket.future;
    }
    return super.getMarketPrices(cardRef, finish: finish, language: language);
  }

  void completeInitialMarket() {
    _initialMarket.complete(const [
      CardDataMarketPriceDto(
        grader: 'PSA',
        grade: 10,
        gradeLabel: '10',
        condition: null,
        price: 70,
      ),
    ]);
  }
}

class _RecoveringSectionCardDataApi extends _FakeCardDataApi {
  var _marketFailuresRemaining = 1;
  var _seriesFailuresRemaining = 2;
  var _soldFailuresRemaining = 1;

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(
    String cardRef, {
    String? finish,
    String? language,
  }) {
    if (_marketFailuresRemaining > 0) {
      _marketFailuresRemaining -= 1;
      throw StateError('market prices unavailable');
    }
    return super.getMarketPrices(cardRef, finish: finish);
  }

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
    String? finish,
  }) {
    if (_seriesFailuresRemaining > 0) {
      _seriesFailuresRemaining -= 1;
      throw StateError('price series unavailable');
    }
    return super.getPriceSeries(
      cardRef,
      days: days,
      grader: grader,
      grade: grade,
      condition: condition,
      finish: finish,
    );
  }

  @override
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef) {
    if (_soldFailuresRemaining > 0) {
      _soldFailuresRemaining -= 1;
      throw StateError('sold listings unavailable');
    }
    return super.getSoldListings(cardRef);
  }
}

const _pikachuCard = CardDataCardDto(
  cardRef: 'catalog:pikachu-025',
  name: 'Pikachu',
  setName: 'Base Set',
  setCode: 'BS',
  cardNumber: '025',
  finish: 'Holofoil',
  language: 'English',
  availableLanguages: ['English', 'Japanese'],
  availableFinishes: ['Holofoil', 'Normal'],
  objectType: 'tcg',
  game: 'Pokemon',
  imageUrl: 'https://img.example/pikachu.jpg',
  rarity: 'Common',
);

const _pricedPikachuCard = CardDataCardDto(
  cardRef: 'catalog:pikachu-025',
  name: 'Pikachu',
  setName: 'Base Set',
  setCode: 'BS',
  cardNumber: '025',
  finish: 'Holofoil',
  language: 'English',
  objectType: 'tcg',
  game: 'Pokemon',
  imageUrl: 'https://img.example/pikachu.jpg',
  rarity: 'Common',
  priceUsd: 15,
  previous30dPriceUsd: 10,
  previous7dPriceUsd: 14,
  priceChange1dPercent: 1.5,
  priceChange7dPercent: 7.14,
  priceChange30dPercent: 50,
);

const _squirtleCard = CardDataCardDto(
  cardRef: 'squirtle',
  name: 'Squirtle',
  setName: 'Mega Evolution Promos',
  setCode: 'MEP',
  cardNumber: '039',
  finish: 'Holofoil',
  language: 'English',
  objectType: 'tcg',
  game: 'Pokemon',
  imageUrl: 'https://img.example/squirtle.jpg',
  rarity: 'Promo',
);

PortfolioItemDto _portfolioItem({
  required String id,
  String folderId = 'main',
  required String cardRef,
  int quantity = 1,
}) {
  final now = DateTime.parse('2026-01-01T00:00:00.000Z');
  return PortfolioItemDto(
    id: id,
    folderId: folderId,
    cardRef: cardRef,
    objectType: 'tcg',
    grader: 'Raw',
    condition: 'Near Mint (NM)',
    grade: null,
    language: 'English',
    finish: 'Holofoil',
    quantity: quantity,
    purchasePrice: null,
    purchaseCurrency: null,
    notes: null,
    createdAt: now,
    updatedAt: now,
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'owner-access',
  refreshToken: 'owner-refresh',
  anonymousId: 'owner',
);
