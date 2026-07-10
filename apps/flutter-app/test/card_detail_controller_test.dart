import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_models.dart';
import 'package:kando_app/features/card_detail/card_detail_repository.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
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
        presentationRepository: const MockCardDetailRepository(),
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
      ).quickCollect(_session, detail);

      expect(api.quickCollectCardRefs, ['squirtle']);
      expect(api.quickCollectDrafts.single.folderId, 'main');
      expect(saved.id, 'backend-item-squirtle');
      expect(saved.cardRef, 'squirtle');
    },
  );

  test('uncollected detail exposes card identity and price overview', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(cardDetailControllerProvider('squirtle'));

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
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container
            .read(cardDetailControllerProvider('squirtle'))
            .marketPriceText,
        r'$32.13',
      );

      container.read(selectedCurrencyProvider.notifier).select(AppCurrency.eur);
      final state = container.read(cardDetailControllerProvider('squirtle'));

      expect(
        state.marketPriceText,
        CurrencyFormatter(currency: AppCurrency.eur).formatUsd(32.13),
      );
      expect(state.changeText, '+4.76%');
    },
  );

  test('missing price and change use CardDetail fallback copy', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(cardDetailControllerProvider('mystery-promo'));

    expect(state.detail.name, 'Mystery Promo');
    expect(state.marketPriceText, '--');
    expect(state.changeText, '-/-');
    expect(state.marketRows.single.priceText, '--');
    expect(state.marketRows.single.changeText, '-/-');
  });

  test('missing Price Tab data exposes section fallback state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(cardDetailControllerProvider('mystery-promo'));

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

  test('quick Collect marks card collected and clears Wishlist', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('one-piece-luffy');
    final controller = container.read(provider.notifier);

    expect(container.read(provider).detail.isWishlisted, isTrue);

    controller.quickCollect();
    final collected = container.read(provider).detail;

    expect(collected.quantity, 1);
    expect(collected.isCollected, isTrue);
    expect(collected.isWishlisted, isFalse);
  });

  test('owned detail exposes collection item rows', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(cardDetailControllerProvider('charizard-ex'));

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
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('one-piece-luffy');

      container.read(provider.notifier).quickCollect();
      final state = container.read(provider);

      expect(state.detail.isCollected, isTrue);
      expect(state.detail.isWishlisted, isFalse);
      expect(state.collectionItemRows.single.portfolioName, 'Main');
      expect(
        state.collectionItemRows.single.statusText,
        'Raw / Near Mint (NM)',
      );
      expect(state.collectionItemRows.single.purchasePriceText, '--');
    },
  );

  test('adding a Collection Item appends an owned row and clears Wishlist', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('squirtle');
    final controller = container.read(provider.notifier);

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

    expect(controller.saveCollectionItemDraft(), isTrue);
    final state = container.read(provider);

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
  });

  test(
    'new Collection Item draft follows PRD field defaults and condition list',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('squirtle');

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

  test('changing grader resets grade options to the selected grader scale', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('squirtle');
    final controller = container.read(provider.notifier);

    controller.startAddingCollectionItem();
    controller.updateCollectionItemDraft(grader: 'BGS');
    final draft = container.read(provider).collectionItemDraft!;

    expect(draft.grade, '10');
    expect(cardCollectionGradeLabelsFor('BGS').take(3), [
      'BGS 10',
      'BGS 9.5',
      'BGS 9',
    ]);
  });

  test('editing a Collection Item switches graded state to Raw state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('charizard-ex');
    final controller = container.read(provider.notifier);

    controller.startEditingCollectionItem('item-charizard');
    controller.updateCollectionItemDraft(
      quantityText: '3',
      grader: 'Raw',
      condition: 'Near Mint (NM)',
      purchasePriceText: '640',
      notes: 'Cracked slab for binder.',
    );

    expect(controller.saveCollectionItemDraft(), isTrue);
    final row = container.read(provider).collectionItemRows.single;

    expect(row.quantityText, 'Qty: 3');
    expect(row.statusText, 'Raw / Near Mint (NM)');
    expect(row.purchasePriceText, r'$640.00');
    expect(row.notes, 'Cracked slab for binder.');
  });

  test('invalid Collection Item draft stays open with validation copy', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('charizard-ex');
    final controller = container.read(provider.notifier);

    controller.startEditingCollectionItem('item-charizard');
    controller.updateCollectionItemDraft(quantityText: '0');

    expect(controller.saveCollectionItemDraft(), isFalse);
    final state = container.read(provider);

    expect(state.collectionItemDraft, isNotNull);
    expect(state.collectionItemFormError, 'Quantity must be at least 1.');
    expect(state.collectionItemRows.single.quantityText, 'Qty: 1');
  });

  test(
    'removing the final Collection Item returns detail to uncollected state',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');

      container.read(provider.notifier).removeCollectionItem('item-charizard');
      final state = container.read(provider);

      expect(state.detail.isCollected, isFalse);
      expect(state.detail.quantity, 0);
      expect(state.collectionItemRows, isEmpty);
    },
  );

  test(
    'price tab exposes default range series, market rows, and sold listings',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(
        cardDetailControllerProvider('charizard-ex'),
      );

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

  test('selecting a price range changes only the visible series rows', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('charizard-ex');

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
  });

  test('repository failure shows failure state and refresh recovers', () {
    final repository = _FailingThenSuccessfulCardDetailRepository();
    final container = ProviderContainer(
      overrides: [cardDetailRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('squirtle');

    final failed = container.read(provider);

    expect(failed.loadStatus, KandoLoadStatus.failure);
    expect(failed.isUnavailable, isTrue);
    expect(repository.calls, 1);

    container.read(provider.notifier).refresh();
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
  dynamic loadDetail(Object sessionOrCardId, [String? cardId]) {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock detail unavailable');
    }
    return const MockCardDetailRepository().loadDetail(sessionOrCardId, cardId);
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

class _FakePortfolioApiClient implements PortfolioApi {
  _FakePortfolioApiClient({
    required this.folders,
    required this.items,
    required this.wishlist,
    this.quickCollectResult,
    this.createResult,
    this.updateResult,
    this.addWishlistResult,
  });

  final List<PortfolioFolderDto> folders;
  final List<PortfolioItemDto> items;
  final List<WishlistItemDto> wishlist;
  final PortfolioItemDto? quickCollectResult;
  final PortfolioItemDto? createResult;
  final PortfolioItemDto? updateResult;
  final WishlistItemDto? addWishlistResult;
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
    return createResult ??
        _portfolioItem(
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
    return updateResult ??
        _portfolioItem(
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
    return addWishlistResult ??
        WishlistItemDto(
          id: 'wish-$cardRef',
          cardRef: cardRef,
          createdAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
        );
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) async {}
}

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
