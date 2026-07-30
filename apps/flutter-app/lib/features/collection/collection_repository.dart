import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_image/card_image_url.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'collection_models.dart';

abstract interface class CollectionRepository {
  Future<CollectionDashboard> loadDashboard(AuthSession session);
  Future<CollectionFolder> createFolder(AuthSession session, String name);
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

class HttpCollectionRepository
    implements CollectionRepository, CollectionGameCatalogRepository {
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
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name,
  ) async {
    return _folderFromDto(await _managementApi.createFolder(session, name));
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
    game: dto.game,
    language: dto.language,
    finish: dto.finish,
    grader: dto.grader,
    condition: dto.condition,
    grade: dto.grade,
    quantity: dto.quantity,
    marketValueUsd: dto.marketPriceUsd,
    previous30dPriceUsd: dto.previous30dPriceUsd,
    addedAtSort: dto.folderJoinedAt.millisecondsSinceEpoch,
    imageUrl: cardImageUrl(dto.cardRef, CardImageVariant.thumbnail),
  );
}
