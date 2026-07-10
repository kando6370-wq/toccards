import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
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
            id: 'item-squirtle',
            folderId: 'main',
            cardRef: 'squirtle',
          ),
        ],
        wishlist: [
          WishlistItemDto(
            id: 'wish-luffy',
            cardRef: 'one-piece-luffy',
            createdAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
          ),
        ],
      );

      final dashboard = await HttpCollectionRepository(
        api,
      ).loadDashboard(_session);

      expect(dashboard.defaultFolder.id, 'main');
      expect(dashboard.portfolioItems.single.cardRef, 'squirtle');
      expect(dashboard.portfolioItems.single.name, 'Squirtle');
      expect(dashboard.wishlistItems.single.cardRef, 'one-piece-luffy');
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

PortfolioItemDto _portfolioItem({
  required String id,
  required String folderId,
  required String cardRef,
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
