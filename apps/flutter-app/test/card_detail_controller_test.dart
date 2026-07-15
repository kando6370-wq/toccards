import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_models.dart';
import 'package:kando_app/features/card_detail/card_detail_repository.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
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
        10,
        reason:
            'Card Detail must not serialize every market qualifier and chart range into a network waterfall.',
      );
      expect(detail.id, 'catalog:pikachu-025');
      expect(detail.type, CardDetailType.tcg);
      expect(detail.name, 'Pikachu');
      expect(detail.game, 'Pokemon');
      expect(detail.imageUrl, 'https://img.example/pikachu.jpg');
      expect(detail.setName, 'Base Set');
      expect(detail.identityLine, 'Common #025');
      expect(detail.finish, 'Holofoil');
      expect(detail.language, 'English');
      expect(detail.marketPrices.map((price) => price.label), [
        'Raw Near Mint',
        'PSA 10',
      ]);
      expect(detail.marketPrices.first.priceUsd, 15);
      expect(detail.marketPrices.first.previous30dPriceUsd, 10);
      expect(detail.marketPrices.first.previous7dPriceUsd, 14);
      expect(
        detail.priceSeriesByRange[CardPriceRange.oneMonth]!.first.dateLabel,
        '2026-06-10',
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

      container.read(selectedCurrencyProvider.notifier).select(AppCurrency.eur);
      await container
          .read(cardDetailControllerProvider('squirtle').notifier)
          .loadComplete;
      final state = container.read(cardDetailControllerProvider('squirtle'));

      expect(
        state.marketPriceText,
        CurrencyFormatter(currency: AppCurrency.eur).formatUsd(32.13),
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
    'new Collection Item draft follows PRD field defaults and condition list',
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
      expect(draft.totalText, '--');
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
    'editing a Collection Item switches graded state to Raw state',
    () async {
      final repository = _RecordingCardDetailRepository();
      final container = _cardDetailContainer(repository: repository);
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'charizard-ex');

      controller.startEditingCollectionItem('item-charizard');
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
    'invalid Collection Item draft stays open with validation copy',
    () async {
      final container = _cardDetailContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');
      final controller = container.read(provider.notifier);
      await _loadedState(container, 'charizard-ex');

      controller.startEditingCollectionItem('item-charizard');
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
      ]);
      expect(state.selectedPriceChartMode, CardPriceChartMode.raw);
      expect(state.selectedPriceRange, CardPriceRange.oneMonth);
      expect(state.priceSeriesRows.last.dateLabel, 'Today');
      expect(state.priceSeriesRows.last.priceText, r'$215.00');
      expect(state.priceTabMarketRows.first.label, 'PSA 10');
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
      final state = container.read(provider);

      expect(state.selectedPriceChartMode, CardPriceChartMode.graded);
      expect(state.selectedPriceRange, CardPriceRange.threeMonths);
      expect(state.priceSeriesRows.first.dateLabel, '90 days ago');
      expect(state.priceSeriesRows.last.priceText, r'$780.00');
      expect(state.priceTabMarketRows.first.label, 'PSA 10');
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

class _WishlistWithoutIdCardDetailRepository
    extends _RecordingCardDetailRepository {
  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await super.loadDetail(session, cardId);
    return detail.copyWith(isWishlisted: true, wishlistItemId: null);
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
}) {
  final storage = InMemoryAuthStorage();
  return ProviderContainer(
    overrides: [
      authStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(storage),
      ),
      cardDetailRepositoryProvider.overrideWithValue(repository),
    ],
  );
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

class _FakeCardDataApi implements CardDataApi {
  _FakeCardDataApi({this.card = _pikachuCard});

  final CardDataCardDto card;
  final List<String> cardRefs = [];
  var activeSeriesRequests = 0;
  var maxConcurrentSeriesRequests = 0;

  @override
  Future<List<CardDataCardDto>> searchCards(String query) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataSetDto>> searchSets(String query) async {
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
  Future<List<CardDataMarketPriceDto>> getMarketPrices(String cardRef) async {
    return const [
      CardDataMarketPriceDto(
        grader: 'Raw',
        grade: null,
        condition: 'Near Mint',
        price: 15,
      ),
      CardDataMarketPriceDto(
        grader: 'PSA',
        grade: 10,
        condition: null,
        price: 70,
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
  }) async {
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
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef) async {
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

const _pikachuCard = CardDataCardDto(
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
