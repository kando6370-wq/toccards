import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_image/card_image_url.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'collection_models.dart';

abstract interface class CollectionRepository {
  Future<CollectionDashboard> loadDashboard(AuthSession session);
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  });
  Future<CollectionFolder> renameFolder(
    AuthSession session,
    String folderId,
    String name,
  );
  Future<void> setDefaultFolder(AuthSession session, String folderId);
  Future<void> reorderFolders(AuthSession session, List<String> folderIds);
  Future<void> deleteFolder(AuthSession session, String folderId);
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  });
}

abstract interface class CollectionGameCatalogRepository {
  Future<List<String>> loadGameOptions();
}

abstract interface class CollectionPagedRepository {
  bool get supportsPaging;

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
  });
  Future<CollectionSummaryResult> loadSummary(AuthSession session);
}

class HttpCollectionRepository
    implements CollectionRepository, CollectionGameCatalogRepository, CollectionPagedRepository {
  const HttpCollectionRepository(
    this._api, {
    required PortfolioManagementApi managementApi,
    SetCatalogApi? gameCatalogApi,
  }) : _managementApi = managementApi,
       _gameCatalogApi = gameCatalogApi;

  final CollectionDashboardApi _api;
  final PortfolioManagementApi _managementApi;
  final SetCatalogApi? _gameCatalogApi;

  @override
  bool get supportsPaging => _api is CollectionPagedApi;

  @override
  Future<List<String>> loadGameOptions() async {
    final games = await _gameCatalogApi?.listGames();
    return games?.map((game) => game.name).toSet().toList() ?? const [];
  }

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await _api.getCollectionDashboard(session);

    return CollectionDashboard(
      folders: dashboard.folders.map(_folderFromDto).toList(),
      portfolioItems: dashboard.portfolioItems
          .map(_collectionItemFromDto)
          .toList(),
      wishlistItems: dashboard.wishlistItems
          .map(_collectionItemFromDto)
          .toList(),
      currencyCode: dashboard.preference.currency,
      amountHidden: dashboard.preference.amountHidden,
    );
  }

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
    final api = _api as CollectionPagedApi;
    final result = await api.getCollectionPage(
      session,
      tab: tab.name,
      folderId: folderId,
      query: query,
      sort: switch (sort) {
        CollectionSort.newest => 'newest',
        CollectionSort.valueDesc => 'value_desc',
        CollectionSort.valueAsc => 'value_asc',
        CollectionSort.changeDesc => 'change_desc',
        CollectionSort.nameAsc => 'name_asc',
        CollectionSort.performanceDesc => 'performance_desc',
      },
      page: page,
      games: games.toList()..sort(),
      languages: languages.toList()..sort(),
      performanceItemIds: performanceItemIds,
    );
    final items = result.items.map(_collectionItemFromDto).toList();
    return CollectionPageResult(
      dashboard: CollectionDashboard(
        folders: result.folders.map(_folderFromDto).toList(),
        portfolioItems: tab == CollectionTab.portfolio ? items : const [],
        wishlistItems: tab == CollectionTab.wishlist ? items : const [],
        currencyCode: result.preference.currency,
        amountHidden: result.preference.amountHidden,
      ),
      folderId: result.folderId,
      total: result.total,
      baseCount: result.baseCount,
      page: result.page,
      pageSize: result.pageSize,
    );
  }

  @override
  Future<CollectionSummaryResult> loadSummary(AuthSession session) async {
    final result = await (_api as CollectionPagedApi).getCollectionSummary(session);
    return CollectionSummaryResult(
      folders: {
        for (final folder in result.folders)
          folder.folderId: CollectionFolderTotals(
            folderId: folder.folderId,
            itemCount: folder.itemCount,
            cardCount: folder.cardCount,
            gradedCount: folder.gradedCount,
            totalValueUsd: folder.totalValueUsd,
            languages: folder.languages,
          ),
      },
      wishlistCount: result.wishlistCount,
      wishlistLanguages: result.wishlistLanguages,
      games: result.games,
    );
  }

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  }) async {
    return _folderFromDto(
      await _managementApi.createFolder(
        session,
        name,
        localPremiumVerified: localPremiumVerified,
      ),
    );
  }

  @override
  Future<CollectionFolder> renameFolder(
    AuthSession session,
    String folderId,
    String name,
  ) async {
    return _folderFromDto(
      await _managementApi.renameFolder(session, folderId, name),
    );
  }

  @override
  Future<void> setDefaultFolder(AuthSession session, String folderId) {
    return _managementApi.setDefaultFolder(session, folderId);
  }

  @override
  Future<void> reorderFolders(AuthSession session, List<String> folderIds) {
    return _managementApi.reorderFolders(session, folderIds);
  }

  @override
  Future<void> deleteFolder(AuthSession session, String folderId) {
    return _managementApi.deleteFolder(session, folderId);
  }

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    await _managementApi.updatePreferences(
      session,
      currency: currency,
      amountHidden: amountHidden,
      lastSelectedFolderId: lastSelectedFolderId,
    );
  }
}

CollectionFolder _folderFromDto(PortfolioFolderDto dto) {
  return CollectionFolder(id: dto.id, name: dto.name, isDefault: dto.isDefault);
}

CollectionItem _collectionItemFromDto(CollectionDashboardItemDto dto) {
  return CollectionItem(
    id: dto.id,
    cardRef: dto.cardRef,
    folderId: dto.folderId,
    name: dto.name,
    setName: dto.setName,
    number: dto.cardNumber.isEmpty ? '--' : '#${dto.cardNumber}',
    rarity: dto.rarity.isEmpty ? '--' : dto.rarity,
    game: dto.game,
    language: dto.language,
    finish: dto.finish,
    grader: dto.grader,
    condition: dto.condition,
    grade: dto.grade,
    quantity: dto.quantity,
    marketValueUsd: dto.marketPriceUsd,
    previous30dPriceUsd: dto.previous30dPriceUsd,
    increasePercent: dto.increasePercent,
    addedAtSort: dto.folderJoinedAt.millisecondsSinceEpoch,
    imageUrl: cardImageUrl(dto.cardRef, CardImageVariant.thumbnail),
  );
}
