import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_repository.dart';

class MockCollectionRepository implements CollectionRepository {
  const MockCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    return const CollectionDashboard(
      folders: [
        CollectionFolder(id: 'main', name: 'Main', isDefault: true),
        CollectionFolder(id: 'sealed', name: 'Sealed', isDefault: false),
        CollectionFolder(id: 'empty', name: 'Empty', isDefault: false),
      ],
      portfolioItems: [
        CollectionItem(
          id: 'item-charizard',
          cardRef: 'charizard-ex',
          folderId: 'main',
          name: 'Charizard ex',
          setName: 'Obsidian Flames',
          number: '#223',
          game: 'Pokemon',
          language: 'English',
          finish: 'Holofoil',
          grader: 'PSA',
          condition: null,
          grade: 10,
          quantity: 1,
          marketValueUsd: 780,
          previous30dPriceUsd: 721.55,
          addedAtSort: 3,
        ),
        CollectionItem(
          id: 'item-umbreon',
          cardRef: 'umbreon-vmax',
          folderId: 'main',
          name: 'Umbreon VMAX',
          setName: 'Evolving Skies',
          number: '#215',
          game: 'Pokemon',
          language: 'English',
          finish: 'Alternate Art',
          grader: 'BGS',
          condition: null,
          grade: 9,
          quantity: 1,
          marketValueUsd: 410,
          previous30dPriceUsd: 365.42,
          addedAtSort: 2,
        ),
        CollectionItem(
          id: 'item-pikachu',
          cardRef: 'pikachu-promo',
          folderId: 'main',
          name: 'Pikachu Promo',
          setName: 'Scarlet & Violet Promos',
          number: '#088',
          game: 'Pokemon',
          language: 'Japanese',
          finish: 'Promo',
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          quantity: 2,
          marketValueUsd: 27.5,
          previous30dPriceUsd: 27.89,
          addedAtSort: 1,
        ),
        CollectionItem(
          id: 'item-sealed-box',
          cardRef: 'evolving-skies-booster-box',
          folderId: 'sealed',
          name: 'Evolving Skies Booster Box',
          setName: 'Sword & Shield',
          number: '36 Packs',
          game: 'Pokemon',
          language: 'English',
          finish: 'Sealed',
          grader: 'Raw',
          condition: 'Sealed',
          grade: null,
          quantity: 1,
          marketValueUsd: 620,
          previous30dPriceUsd: 588.24,
          addedAtSort: 4,
        ),
      ],
      wishlistItems: [
        CollectionItem(
          id: 'wish-elsa',
          cardRef: 'lorcana-elsa',
          folderId: null,
          name: 'Lorcana Elsa',
          setName: 'The First Chapter',
          number: '#212',
          game: 'Lorcana',
          language: 'English',
          finish: 'Enchanted',
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          quantity: 1,
          marketValueUsd: 480,
          previous30dPriceUsd: 449.86,
          addedAtSort: 2,
        ),
        CollectionItem(
          id: 'wish-luffy',
          cardRef: 'one-piece-luffy',
          folderId: null,
          name: 'One Piece Manga Luffy',
          setName: 'Romance Dawn',
          number: '#001',
          game: 'One Piece',
          language: 'Japanese',
          finish: 'Manga',
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          quantity: 1,
          marketValueUsd: 330,
          previous30dPriceUsd: 306.69,
          addedAtSort: 1,
        ),
      ],
    );
  }

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name,
  ) async {
    return CollectionFolder(
      id: 'folder-${name.toLowerCase().replaceAll(' ', '-')}',
      name: name,
      isDefault: false,
    );
  }

  @override
  Future<CollectionFolder> renameFolder(
    AuthSession session,
    String folderId,
    String name,
  ) async {
    return CollectionFolder(id: folderId, name: name, isDefault: false);
  }

  @override
  Future<void> setDefaultFolder(AuthSession session, String folderId) async {}

  @override
  Future<void> reorderFolders(
    AuthSession session,
    List<String> folderIds,
  ) async {}

  @override
  Future<void> deleteFolder(AuthSession session, String folderId) async {}

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {}
}
