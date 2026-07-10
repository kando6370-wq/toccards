import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'collection_models.dart';

abstract interface class CollectionRepository {
  Future<CollectionDashboard> loadDashboard(AuthSession session);
}

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
          createdAtSort: 3,
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
          createdAtSort: 2,
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
          createdAtSort: 1,
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
          createdAtSort: 4,
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
          createdAtSort: 2,
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
          createdAtSort: 1,
        ),
      ],
    );
  }
}

class HttpCollectionRepository implements CollectionRepository {
  const HttpCollectionRepository(this._api);

  final PortfolioApi _api;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final results = await Future.wait([
      _api.listFolders(session),
      _api.listCollectionItems(session),
      _api.listWishlistItems(session),
    ]);
    final folders = results[0] as List<PortfolioFolderDto>;
    final items = results[1] as List<PortfolioItemDto>;
    final wishlist = results[2] as List<WishlistItemDto>;

    return CollectionDashboard(
      folders: folders.map(_folderFromDto).toList(),
      portfolioItems: items.map(_collectionItemFromPortfolioDto).toList(),
      wishlistItems: wishlist.map(_collectionItemFromWishlistDto).toList(),
    );
  }
}

CollectionFolder _folderFromDto(PortfolioFolderDto dto) {
  return CollectionFolder(id: dto.id, name: dto.name, isDefault: dto.isDefault);
}

CollectionItem _collectionItemFromPortfolioDto(PortfolioItemDto dto) {
  final fallback = _presentationFor(dto.cardRef);
  return CollectionItem(
    id: dto.id,
    cardRef: dto.cardRef,
    folderId: dto.folderId,
    name: fallback.name,
    setName: fallback.setName,
    number: fallback.number,
    game: fallback.game,
    language: dto.language ?? fallback.language,
    finish: dto.finish ?? fallback.finish,
    grader: dto.grader,
    condition: dto.condition,
    grade: dto.grade,
    quantity: dto.quantity,
    marketValueUsd: fallback.marketValueUsd,
    previous30dPriceUsd: fallback.previous30dPriceUsd,
    createdAtSort: dto.createdAt.millisecondsSinceEpoch,
  );
}

CollectionItem _collectionItemFromWishlistDto(WishlistItemDto dto) {
  final fallback = _presentationFor(dto.cardRef);
  return CollectionItem(
    id: dto.id,
    cardRef: dto.cardRef,
    folderId: null,
    name: fallback.name,
    setName: fallback.setName,
    number: fallback.number,
    game: fallback.game,
    language: fallback.language,
    finish: fallback.finish,
    grader: 'Raw',
    condition: 'Near Mint (NM)',
    grade: null,
    quantity: 1,
    marketValueUsd: fallback.marketValueUsd,
    previous30dPriceUsd: fallback.previous30dPriceUsd,
    createdAtSort: dto.createdAt.millisecondsSinceEpoch,
  );
}

_CollectionPresentation _presentationFor(String cardRef) {
  return _fallbackCatalog[cardRef] ??
      _CollectionPresentation(
        name: _readableCardRef(cardRef),
        setName: 'Unknown Set',
        number: cardRef,
        game: 'Unknown',
        language: 'English',
        finish: 'Standard',
        marketValueUsd: null,
        previous30dPriceUsd: null,
      );
}

String _readableCardRef(String cardRef) {
  return cardRef
      .split(RegExp(r'[-_\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

const _fallbackCatalog = {
  'charizard-ex': _CollectionPresentation(
    name: 'Charizard ex',
    setName: 'Obsidian Flames',
    number: '#223',
    game: 'Pokemon',
    language: 'English',
    finish: 'Holofoil',
    marketValueUsd: 780,
    previous30dPriceUsd: 721.55,
  ),
  'umbreon-vmax': _CollectionPresentation(
    name: 'Umbreon VMAX',
    setName: 'Evolving Skies',
    number: '#215',
    game: 'Pokemon',
    language: 'English',
    finish: 'Alternate Art',
    marketValueUsd: 410,
    previous30dPriceUsd: 365.42,
  ),
  'pikachu-promo': _CollectionPresentation(
    name: 'Pikachu Promo',
    setName: 'Scarlet & Violet Promos',
    number: '#088',
    game: 'Pokemon',
    language: 'Japanese',
    finish: 'Promo',
    marketValueUsd: 27.5,
    previous30dPriceUsd: 27.89,
  ),
  'evolving-skies-booster-box': _CollectionPresentation(
    name: 'Evolving Skies Booster Box',
    setName: 'Sword & Shield',
    number: '36 Packs',
    game: 'Pokemon',
    language: 'English',
    finish: 'Sealed',
    marketValueUsd: 620,
    previous30dPriceUsd: 588.24,
  ),
  'lorcana-elsa': _CollectionPresentation(
    name: 'Lorcana Elsa',
    setName: 'The First Chapter',
    number: '#212',
    game: 'Lorcana',
    language: 'English',
    finish: 'Enchanted',
    marketValueUsd: 480,
    previous30dPriceUsd: 449.86,
  ),
  'one-piece-luffy': _CollectionPresentation(
    name: 'One Piece Manga Luffy',
    setName: 'Romance Dawn',
    number: '#001',
    game: 'One Piece',
    language: 'Japanese',
    finish: 'Manga',
    marketValueUsd: 330,
    previous30dPriceUsd: 306.69,
  ),
  'squirtle': _CollectionPresentation(
    name: 'Squirtle',
    setName: 'Pokemon 151',
    number: '#007',
    game: 'Pokemon',
    language: 'English',
    finish: 'Holofoil',
    marketValueUsd: 18,
    previous30dPriceUsd: 17.25,
  ),
};

class _CollectionPresentation {
  const _CollectionPresentation({
    required this.name,
    required this.setName,
    required this.number,
    required this.game,
    required this.language,
    required this.finish,
    required this.marketValueUsd,
    required this.previous30dPriceUsd,
  });

  final String name;
  final String setName;
  final String number;
  final String game;
  final String language;
  final String finish;
  final double? marketValueUsd;
  final double? previous30dPriceUsd;
}
