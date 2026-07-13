import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  test(
    'http repository maps real portfolio rows into collection dashboard because Collection must show backend-owned assets',
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
            id: 'item-pikachu',
            folderId: 'main',
            cardRef: 'catalog:pikachu-025',
          ),
          _portfolioItem(
            id: 'item-pikachu-psa',
            folderId: 'main',
            cardRef: 'catalog:pikachu-025',
            grader: 'PSA',
            condition: null,
            grade: 10,
          ),
        ],
        wishlist: [
          WishlistItemDto(
            id: 'wish-luffy',
            cardRef: 'catalog:luffy-001',
            createdAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
          ),
        ],
      );
      final cardDataApi = _FakeCardDataApi(
        cards: const {
          'catalog:pikachu-025': CardDataCardDto(
            cardRef: 'catalog:pikachu-025',
            name: 'Pikachu',
            setName: 'Base Set',
            setCode: 'BS',
            cardNumber: '025',
            finish: 'Holofoil',
            language: 'English',
            objectType: 'tcg',
            imageUrl: null,
            rarity: 'Common',
          ),
          'catalog:luffy-001': CardDataCardDto(
            cardRef: 'catalog:luffy-001',
            name: 'Monkey D. Luffy',
            setName: 'Romance Dawn',
            setCode: 'OP01',
            cardNumber: '001',
            finish: 'Normal',
            language: 'Japanese',
            objectType: 'tcg',
            imageUrl: null,
            rarity: 'Manga Rare',
          ),
        },
        prices: const {
          'catalog:pikachu-025': [
            CardDataMarketPriceDto(
              grader: 'Raw',
              grade: null,
              condition: 'Near Mint (NM)',
              price: 12.5,
            ),
            CardDataMarketPriceDto(
              grader: 'PSA',
              grade: 10,
              condition: null,
              price: 90,
            ),
          ],
          'catalog:luffy-001': [
            CardDataMarketPriceDto(
              grader: 'Raw',
              grade: null,
              condition: 'Near Mint (NM)',
              price: 330,
            ),
          ],
        },
      );

      final dashboard = await HttpCollectionRepository(
        api,
        cardDataApi: cardDataApi,
      ).loadDashboard(_session);

      expect(dashboard.defaultFolder.id, 'main');
      expect(cardDataApi.cardRefs, [
        'catalog:pikachu-025',
        'catalog:luffy-001',
      ]);
      expect(cardDataApi.marketPriceRefs, [
        'catalog:pikachu-025',
        'catalog:luffy-001',
      ]);
      expect(dashboard.portfolioItems.first.cardRef, 'catalog:pikachu-025');
      expect(dashboard.portfolioItems.first.name, 'Pikachu');
      expect(dashboard.portfolioItems.first.setName, 'Base Set');
      expect(dashboard.portfolioItems.first.number, '#025');
      expect(dashboard.portfolioItems.first.game, 'TCG');
      expect(dashboard.portfolioItems.first.marketValueUsd, 12.5);
      expect(dashboard.portfolioItems.first.previous30dPriceUsd, isNull);
      expect(dashboard.portfolioItems.last.marketValueUsd, 90);
      expect(dashboard.wishlistItems.single.cardRef, 'catalog:luffy-001');
      expect(dashboard.wishlistItems.single.name, 'Monkey D. Luffy');
      expect(dashboard.wishlistItems.single.marketValueUsd, 330);
    },
  );

  test(
    'http repository keeps owned rows when card-data enrichment partially fails because portfolio is the source of truth',
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
            id: 'item-charizard',
            folderId: 'main',
            cardRef: 'charizard-ex',
          ),
          _portfolioItem(
            id: 'item-pikachu',
            folderId: 'main',
            cardRef: 'catalog:pikachu-025',
          ),
        ],
        wishlist: const [],
      );
      final cardDataApi = _FakeCardDataApi(
        cards: const {
          'catalog:pikachu-025': CardDataCardDto(
            cardRef: 'catalog:pikachu-025',
            name: 'Pikachu',
            setName: 'Base Set',
            setCode: 'BS',
            cardNumber: '025',
            finish: 'Holofoil',
            language: 'English',
            objectType: 'tcg',
            imageUrl: null,
            rarity: 'Common',
          ),
        },
        prices: const {},
        cardFailures: {'charizard-ex'},
        priceFailures: {'catalog:pikachu-025'},
      );

      final dashboard = await HttpCollectionRepository(
        api,
        cardDataApi: cardDataApi,
      ).loadDashboard(_session);

      expect(dashboard.portfolioItems.map((item) => item.name), [
        'Charizard ex',
        'Pikachu',
      ]);
      expect(dashboard.portfolioItems.first.marketValueUsd, 780);
      expect(dashboard.portfolioItems.last.marketValueUsd, isNull);
    },
  );

  test('defaults to Portfolio tab and Main folder summary', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    final state = await _loadedState(container);

    expect(state.selectedTab, CollectionTab.portfolio);
    expect(state.selectedFolder.name, 'Main');
    expect(state.portfolioSummary.totalValueText, r'$1,245.00');
    expect(state.portfolioSummary.cardCount, 3);
    expect(state.portfolioSummary.gradedCount, 2);
    expect(state.visibleItems.map((item) => item.name), [
      'Charizard ex',
      'Umbreon VMAX',
      'Pikachu Promo',
    ]);
    expect(state.visibleItems.first.valueText, r'$780.00');
    expect(state.visibleItems.first.source.previous30dPriceUsd, 721.55);
    expect(state.visibleItems.first.changeText, '+8.10%');
  });

  test(
    'shared selected currency converts collection money while preserving percentages',
    () async {
      final container = _collectionContainer();
      addTearDown(container.dispose);
      await _loadedState(container);

      expect(
        container
            .read(collectionControllerProvider)
            .portfolioSummary
            .totalValueText,
        r'$1,245.00',
      );

      container.read(selectedCurrencyProvider.notifier).select(AppCurrency.eur);
      await container.read(collectionControllerProvider.notifier).loadComplete;
      final state = container.read(collectionControllerProvider);

      expect(state.portfolioSummary.totalValueText, '€1,132.95');
      expect(state.visibleItems.first.valueText, '€709.80');
      expect(state.visibleItems.first.changeText, '+8.10%');
    },
  );

  test(
    'repository failure shows page failure and refresh restores collection',
    () async {
      final repository = _FailingThenSuccessfulCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);

      final failed = await _loadedState(container);

      expect(failed.loadStatus, KandoLoadStatus.failure);
      expect(failed.isUnavailable, isTrue);
      expect(repository.calls, 1);

      await container.read(collectionControllerProvider.notifier).refresh();
      final restored = container.read(collectionControllerProvider);

      expect(restored.loadStatus, KandoLoadStatus.content);
      expect(restored.isUnavailable, isFalse);
      expect(restored.portfolioSummary.totalValueText, r'$1,245.00');
      expect(repository.calls, 2);
    },
  );

  test('switching folders changes only Portfolio scoped items', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.selectFolder('sealed');
    final sealed = container.read(collectionControllerProvider);

    expect(sealed.selectedFolder.name, 'Sealed');
    expect(sealed.visibleItems.map((item) => item.name), [
      'Evolving Skies Booster Box',
    ]);

    controller.selectTab(CollectionTab.wishlist);
    final wishlist = container.read(collectionControllerProvider);

    expect(wishlist.visibleItems.map((item) => item.name), [
      'Lorcana Elsa',
      'One Piece Manga Luffy',
    ]);
  });

  test('search is scoped per tab and current folder', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.updateSearch('umbreon');
    expect(
      container.read(collectionControllerProvider).visibleItems.single.name,
      'Umbreon VMAX',
    );

    controller.selectTab(CollectionTab.wishlist);
    expect(container.read(collectionControllerProvider).searchText, '');

    controller.updateSearch('luffy');
    expect(
      container.read(collectionControllerProvider).visibleItems.single.name,
      'One Piece Manga Luffy',
    );
  });

  test('sort and filters combine for the selected tab', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.applySortAndFilters(
      sort: CollectionSort.valueDesc,
      games: {'Pokemon'},
      languages: {'English'},
    );
    final filtered = container.read(collectionControllerProvider);

    expect(filtered.visibleItems.map((item) => item.name), [
      'Charizard ex',
      'Umbreon VMAX',
    ]);
  });

  test('amount hiding masks money but leaves percentages readable', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.toggleAmountHidden();
    final state = container.read(collectionControllerProvider);

    expect(state.portfolioSummary.totalValueText, hiddenMoneyText);
    expect(state.visibleItems.first.valueText, hiddenMoneyText);
    expect(state.visibleItems.first.changeText, '+8.10%');
  });

  test('empty and no-match states are distinct', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.selectFolder('empty');
    expect(container.read(collectionControllerProvider).isEmpty, isTrue);
    expect(container.read(collectionControllerProvider).isNoMatch, isFalse);

    controller.selectFolder('main');
    controller.updateSearch('missing');
    expect(container.read(collectionControllerProvider).isEmpty, isFalse);
    expect(container.read(collectionControllerProvider).isNoMatch, isTrue);
  });
}

ProviderContainer _collectionContainer({
  CollectionRepository repository = const MockCollectionRepository(),
}) {
  final storage = InMemoryAuthStorage();
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(storage),
      ),
      collectionRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

Future<CollectionState> _loadedState(ProviderContainer container) async {
  await container.read(authControllerProvider.notifier).startupComplete;
  await container.read(collectionControllerProvider.notifier).loadComplete;
  return container.read(collectionControllerProvider);
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
}

class _FakePortfolioApiClient implements PortfolioApi {
  const _FakePortfolioApiClient({
    required this.folders,
    required this.items,
    required this.wishlist,
  });

  final List<PortfolioFolderDto> folders;
  final List<PortfolioItemDto> items;
  final List<WishlistItemDto> wishlist;

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
  Future<WishlistItemDto> addWishlist(
    AuthSession session,
    String cardRef,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PortfolioItemDto> createCollectionItem(
    AuthSession session,
    PortfolioItemDraftDto draft,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) async {
    throw UnimplementedError();
  }

  @override
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PortfolioItemDto> updateCollectionItem(
    AuthSession session, {
    required String itemId,
    required PortfolioItemDraftDto draft,
  }) async {
    throw UnimplementedError();
  }
}

class _FakeCardDataApi implements CardDataApi {
  _FakeCardDataApi({
    required this.cards,
    required this.prices,
    this.cardFailures = const {},
    this.priceFailures = const {},
  });

  final Map<String, CardDataCardDto> cards;
  final Map<String, List<CardDataMarketPriceDto>> prices;
  final Set<String> cardFailures;
  final Set<String> priceFailures;
  final List<String> cardRefs = [];
  final List<String> marketPriceRefs = [];

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
    if (cardFailures.contains(cardRef)) {
      throw StateError('card-data card unavailable');
    }
    return cards[cardRef]!;
  }

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(String cardRef) async {
    marketPriceRefs.add(cardRef);
    if (priceFailures.contains(cardRef)) {
      throw StateError('card-data prices unavailable');
    }
    return prices[cardRef] ?? const [];
  }

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef) async {
    throw UnimplementedError();
  }
}

PortfolioItemDto _portfolioItem({
  required String id,
  required String folderId,
  required String cardRef,
  String grader = 'Raw',
  String? condition = 'Near Mint (NM)',
  double? grade,
}) {
  final now = DateTime.parse('2026-01-01T00:00:00.000Z');
  return PortfolioItemDto(
    id: id,
    folderId: folderId,
    cardRef: cardRef,
    objectType: 'tcg',
    grader: grader,
    condition: condition,
    grade: grade,
    language: 'English',
    finish: 'Holofoil',
    quantity: 1,
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
