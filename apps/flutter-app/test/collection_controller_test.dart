import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'support/in_memory_auth_storage.dart';
import 'support/local_placeholder_auth_repository.dart';
import 'support/mock_collection_repository.dart';
import 'support/mock_card_detail_repository.dart';
import 'support/mock_home_repository.dart';

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
            game: 'Pokemon',
            imageUrl: 'https://api.tcgcard.fun/api/v1/cards/25/image',
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
        previous30dPrices: const {
          'catalog:pikachu-025': 10,
          'catalog:luffy-001': 300,
        },
      );

      final dashboard = await HttpCollectionRepository(
        api,
        managementApi: api,
      ).loadDashboard(_session);

      expect(dashboard.defaultFolder.id, 'main');
      expect(cardDataApi.cardRefs, isEmpty);
      expect(cardDataApi.marketPriceRefs, isEmpty);
      expect(dashboard.portfolioItems.first.cardRef, 'catalog:pikachu-025');
      expect(dashboard.portfolioItems.first.name, 'Pikachu');
      expect(dashboard.portfolioItems.first.setName, 'Base Set');
      expect(dashboard.portfolioItems.first.number, '#025');
      expect(dashboard.portfolioItems.first.game, 'Pokemon');
      expect(dashboard.portfolioItems.first.marketValueUsd, 12.5);
      expect(dashboard.portfolioItems.first.previous30dPriceUsd, 10);
      expect(
        dashboard.portfolioItems.first.imageUrl,
        'https://image.tcgcard.fun/cdn-cgi/image/width=160,height=224,fit=scale-down,quality=60,format=auto,dpr=2/cards/catalog%3Apikachu-025.jpg',
      );
      expect(dashboard.portfolioItems.last.marketValueUsd, isNull);
      expect(dashboard.wishlistItems.single.cardRef, 'catalog:luffy-001');
      expect(dashboard.wishlistItems.single.name, 'Monkey D. Luffy');
      expect(dashboard.wishlistItems.single.marketValueUsd, 330);
    },
  );

  test(
    'http repository keeps server-enriched owned rows without calling card-data endpoints because dashboard is the source of truth',
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
        managementApi: api,
      ).loadDashboard(_session);

      expect(dashboard.portfolioItems.map((item) => item.name), [
        'charizard-ex',
        'Pikachu',
      ]);
      expect(dashboard.portfolioItems.first.marketValueUsd, isNull);
      expect(dashboard.portfolioItems.last.marketValueUsd, 12.5);
      expect(cardDataApi.cardRefs, isEmpty);
      expect(cardDataApi.marketPriceRefs, isEmpty);
    },
  );

  test(
    'http repository does not substitute another condition because Collection Item value is state specific',
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
            id: 'item-damaged',
            folderId: 'main',
            cardRef: 'catalog:pikachu-025',
            condition: 'Damaged (D)',
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
        prices: const {
          'catalog:pikachu-025': [
            CardDataMarketPriceDto(
              grader: 'Raw',
              grade: null,
              condition: 'Near Mint',
              price: 12.5,
            ),
          ],
        },
      );

      final dashboard = await HttpCollectionRepository(
        api,
        managementApi: api,
      ).loadDashboard(_session);

      expect(dashboard.portfolioItems.single.marketValueUsd, isNull);
      expect(dashboard.portfolioItems.single.previous30dPriceUsd, isNull);
      expect(cardDataApi.cardRefs, isEmpty);
      expect(cardDataApi.marketPriceRefs, isEmpty);
    },
  );

  test(
    'summary counts owned copies because quantity represents physical cards',
    () async {
      final container = _collectionContainer();
      addTearDown(container.dispose);
      final state = await _loadedState(container);

      expect(state.selectedTab, CollectionTab.portfolio);
      expect(state.selectedFolder.name, 'Main');
      expect(state.portfolioSummary.totalValueText, r'$1,245.00');
      expect(state.portfolioSummary.cardCount, 4);
      expect(state.portfolioSummary.gradedCount, 2);
      expect(state.visibleItems.map((item) => item.name), [
        'Charizard ex',
        'Umbreon VMAX',
        'Pikachu Promo',
      ]);
      expect(state.visibleItems.first.valueText, r'$780.00');
      expect(state.visibleItems.first.source.previous30dPriceUsd, 721.55);
      expect(state.visibleItems.first.changeText, '+8.10%');
    },
  );

  test(
    'graded summary counts graded copies rather than collection rows',
    () async {
      final container = _collectionContainer(
        repository: const _GradedQuantityCollectionRepository(),
      );
      addTearDown(container.dispose);

      final state = await _loadedState(container);

      expect(state.portfolioSummary.cardCount, 7);
      expect(state.portfolioSummary.gradedCount, 5);
    },
  );

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

      container
          .read(selectedCurrencyProvider.notifier)
          .select(AppCurrency.eur.withUsdRate(0.91));
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

    await controller.selectFolder('sealed');
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

  test(
    'folder selection and amount visibility persist owner preferences because Home and Collection must stay in sync',
    () async {
      final repository = _RecordingCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      expect(await controller.selectFolder('sealed'), isTrue);
      expect(await controller.toggleAmountHidden(), isTrue);

      expect(repository.selectedFolderIds, ['sealed']);
      expect(repository.amountHiddenValues, [true]);
      final state = container.read(collectionControllerProvider);
      expect(state.selectedFolder.id, 'sealed');
      expect(state.amountHidden, isTrue);
    },
  );

  test(
    'folder management updates backend state and falls back to the default after deleting the selection',
    () async {
      final repository = _RecordingCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      final created = await controller.createFolder('Trade');
      expect(created?.name, 'Trade');
      expect(
        await controller.renameFolder(created!.id, 'Trade Binder'),
        isTrue,
      );
      expect(await controller.setDefaultFolder(created.id), isTrue);
      expect(
        await controller.reorderFolders([
          created.id,
          'main',
          'sealed',
          'empty',
        ]),
        isTrue,
      );
      await controller.selectFolder('sealed');
      expect(await controller.deleteFolder('sealed'), isTrue);

      final state = container.read(collectionControllerProvider);
      expect(state.dashboard.folders.map((folder) => folder.name), [
        'Trade Binder',
        'Main',
        'Empty',
      ]);
      expect(state.dashboard.defaultFolder.id, created.id);
      expect(state.selectedFolder.id, created.id);
      expect(repository.deletedFolderIds, ['sealed']);
      expect(
        repository.selectedFolderIds,
        ['sealed'],
        reason:
            'Workers clears a deleted selected folder, so Flutter must not issue a second preference write after deletion.',
      );
    },
  );

  test(
    'folder mutation invalidates Home and Card Detail because both cache portfolio folder data',
    () async {
      final container = _collectionContainer(includeFolderConsumers: true);
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);
      final homeState = container.read(homeControllerProvider);
      final detailProvider = cardDetailControllerProvider('squirtle');
      await container.read(detailProvider.notifier).loadComplete;
      final detailState = container.read(detailProvider);

      expect(await controller.createFolder('Trade'), isNotNull);

      expect(container.read(homeControllerProvider), isNot(same(homeState)));
      expect(container.read(detailProvider), isNot(same(detailState)));
    },
  );

  test(
    'preference write failure rolls back state because local success must not disagree with Workers',
    () async {
      final repository = _RecordingCollectionRepository(failPreferences: true);
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      expect(await controller.selectFolder('sealed'), isFalse);
      expect(await controller.toggleAmountHidden(), isFalse);

      final state = container.read(collectionControllerProvider);
      expect(state.selectedFolder.id, 'main');
      expect(state.amountHidden, isFalse);
    },
  );

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

  test(
    'price ascending keeps missing values last for the Figma filter',
    () async {
      final container = _collectionContainer();
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      controller.applySortAndFilters(
        sort: CollectionSort.valueAsc,
        games: {'Pokemon'},
        languages: {'English'},
      );

      expect(
        container
            .read(collectionControllerProvider)
            .visibleItems
            .map((item) => item.name),
        ['Umbreon VMAX', 'Charizard ex'],
      );
    },
  );

  test('amount hiding masks money but leaves percentages readable', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    await controller.toggleAmountHidden();
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

    await controller.selectFolder('empty');
    expect(container.read(collectionControllerProvider).isEmpty, isTrue);
    expect(container.read(collectionControllerProvider).isNoMatch, isFalse);

    await controller.selectFolder('main');
    controller.updateSearch('missing');
    expect(container.read(collectionControllerProvider).isEmpty, isFalse);
    expect(container.read(collectionControllerProvider).isNoMatch, isTrue);
  });
}

ProviderContainer _collectionContainer({
  CollectionRepository repository = const MockCollectionRepository(),
  bool includeFolderConsumers = false,
}) {
  final storage = InMemoryAuthStorage();
  return ProviderContainer(
    overrides: [
      authStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(storage),
      ),
      collectionRepositoryProvider.overrideWithValue(repository),
      if (includeFolderConsumers) ...[
        homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        cardDetailRepositoryProvider.overrideWithValue(
          const MockCardDetailRepository(),
        ),
      ],
    ],
  );
}

Future<CollectionState> _loadedState(ProviderContainer container) async {
  await container.read(authControllerProvider.notifier).startupComplete;
  await container.read(collectionControllerProvider.notifier).loadComplete;
  return container.read(collectionControllerProvider);
}

class _RecordingCollectionRepository extends MockCollectionRepository {
  _RecordingCollectionRepository({this.failPreferences = false});

  final bool failPreferences;
  final List<String> selectedFolderIds = [];
  final List<bool> amountHiddenValues = [];
  final List<String> deletedFolderIds = [];

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name,
  ) async {
    return CollectionFolder(
      id: 'folder-${name.toLowerCase()}',
      name: name,
      isDefault: false,
    );
  }

  @override
  Future<void> deleteFolder(AuthSession session, String folderId) async {
    deletedFolderIds.add(folderId);
  }

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    if (failPreferences) throw StateError('preferences unavailable');
    if (amountHidden != null) amountHiddenValues.add(amountHidden);
    if (lastSelectedFolderId != null) {
      selectedFolderIds.add(lastSelectedFolderId);
    }
  }
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

class _GradedQuantityCollectionRepository extends MockCollectionRepository {
  const _GradedQuantityCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(
      portfolioItems: [
        ...dashboard.portfolioItems,
        const CollectionItem(
          id: 'item-graded-copies',
          cardRef: 'graded-copies',
          folderId: 'main',
          name: 'Graded copies',
          setName: 'Test Set',
          number: '#001',
          game: 'Pokemon',
          language: 'English',
          finish: 'Holofoil',
          grader: 'PSA',
          condition: null,
          grade: 10,
          quantity: 3,
          marketValueUsd: null,
          previous30dPriceUsd: null,
          addedAtSort: 5,
        ),
      ],
    );
  }
}

class _FakePortfolioApiClient
    implements PortfolioApi, PortfolioManagementApi, CollectionDashboardApi {
  const _FakePortfolioApiClient({
    required this.folders,
    required this.items,
    required this.wishlist,
  });

  final List<PortfolioFolderDto> folders;
  final List<PortfolioItemDto> items;
  final List<WishlistItemDto> wishlist;

  @override
  Future<CollectionDashboardDto> getCollectionDashboard(
    AuthSession session,
  ) async {
    return CollectionDashboardDto(
      folders: folders,
      portfolioItems: items.map((item) {
        final pikachu = item.cardRef == 'catalog:pikachu-025';
        return CollectionDashboardItemDto(
          id: item.id,
          cardRef: item.cardRef,
          folderId: item.folderId,
          name: pikachu ? 'Pikachu' : item.cardRef,
          setName: pikachu ? 'Base Set' : 'Card data unavailable',
          cardNumber: pikachu ? '025' : '',
          game: pikachu ? 'Pokemon' : 'Unknown',
          language: item.language ?? 'Unknown',
          finish: item.finish ?? 'Unknown',
          grader: item.grader,
          condition: item.condition,
          grade: item.grade,
          quantity: item.quantity,
          marketPriceUsd:
              pikachu &&
                  item.grader == 'Raw' &&
                  item.condition == 'Near Mint (NM)'
              ? 12.5
              : null,
          previous30dPriceUsd:
              pikachu &&
                  item.grader == 'Raw' &&
                  item.condition == 'Near Mint (NM)'
              ? 10
              : null,
          folderJoinedAt: item.createdAt,
          createdAt: item.createdAt,
          imageUrl: pikachu
              ? 'https://api.tcgcard.fun/api/v1/cards/25/image'
              : null,
        );
      }).toList(),
      wishlistItems: wishlist.map((item) {
        final luffy = item.cardRef == 'catalog:luffy-001';
        return CollectionDashboardItemDto(
          id: item.id,
          cardRef: item.cardRef,
          folderId: null,
          name: luffy ? 'Monkey D. Luffy' : item.cardRef,
          setName: luffy ? 'Romance Dawn' : 'Card data unavailable',
          cardNumber: luffy ? '001' : '',
          game: 'Unknown',
          language: luffy ? 'Japanese' : 'Unknown',
          finish: luffy ? 'Normal' : 'Unknown',
          grader: 'Raw',
          condition: 'Near Mint',
          grade: null,
          quantity: 1,
          marketPriceUsd: luffy ? 330 : null,
          previous30dPriceUsd: luffy ? 300 : null,
          folderJoinedAt: item.createdAt,
          createdAt: item.createdAt,
          imageUrl: null,
        );
      }).toList(),
      preference: const UserPreferenceDto(
        currency: 'USD',
        amountHidden: false,
        lastSelectedFolderId: null,
      ),
    );
  }

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
  Future<UserPreferenceDto> getPreferences(AuthSession session) async {
    return const UserPreferenceDto(
      currency: 'USD',
      amountHidden: false,
      lastSelectedFolderId: null,
    );
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCardDataApi implements CardDataApi {
  _FakeCardDataApi({
    required this.cards,
    required this.prices,
    this.cardFailures = const {},
    this.priceFailures = const {},
    this.previous30dPrices = const {},
  });

  final Map<String, CardDataCardDto> cards;
  final Map<String, List<CardDataMarketPriceDto>> prices;
  final Set<String> cardFailures;
  final Set<String> priceFailures;
  final Map<String, double> previous30dPrices;
  final List<String> cardRefs = [];
  final List<String> marketPriceRefs = [];

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
    final previous = previous30dPrices[cardRef];
    if (previous == null) {
      throw StateError('card-data series unavailable');
    }
    final current = prices[cardRef]!
        .firstWhere(
          (price) =>
              price.grader == grader &&
              (grade == null || price.grade == grade) &&
              (condition == null || price.condition == condition),
        )
        .price!;
    return [
      CardDataPricePointDto(date: '2026-06-15', price: previous),
      CardDataPricePointDto(date: '2026-07-15', price: current),
    ];
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
