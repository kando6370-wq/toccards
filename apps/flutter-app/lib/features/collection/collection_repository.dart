import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
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
  const HttpCollectionRepository(this._api, {CardDataApi? cardDataApi})
    : _cardDataApi = cardDataApi;

  final PortfolioApi _api;
  final CardDataApi? _cardDataApi;

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
    final presentations = await _loadPresentations(items, wishlist);

    return CollectionDashboard(
      folders: folders.map(_folderFromDto).toList(),
      portfolioItems: items
          .map(
            (item) => _collectionItemFromPortfolioDto(
              item,
              presentations[item.cardRef],
            ),
          )
          .toList(),
      wishlistItems: wishlist
          .map(
            (item) => _collectionItemFromWishlistDto(
              item,
              presentations[item.cardRef],
            ),
          )
          .toList(),
    );
  }

  Future<Map<String, _CollectionPresentation>> _loadPresentations(
    List<PortfolioItemDto> items,
    List<WishlistItemDto> wishlist,
  ) async {
    final api = _cardDataApi;
    if (api == null) {
      return const {};
    }

    final cardRefs = <String>{
      for (final item in items) item.cardRef,
      for (final item in wishlist) item.cardRef,
    };
    final presentations = <String, _CollectionPresentation>{};
    for (final cardRef in cardRefs) {
      final CardDataCardDto card;
      try {
        card = await api.getCard(cardRef);
      } catch (_) {
        continue;
      }
      var prices = const <CardDataMarketPriceDto>[];
      try {
        prices = await api.getMarketPrices(cardRef);
      } catch (_) {
      }
      presentations[cardRef] = _presentationFromCardData(card, prices);
    }
    return presentations;
  }
}

CollectionFolder _folderFromDto(PortfolioFolderDto dto) {
  return CollectionFolder(id: dto.id, name: dto.name, isDefault: dto.isDefault);
}

CollectionItem _collectionItemFromPortfolioDto(
  PortfolioItemDto dto,
  _CollectionPresentation? presentation,
) {
  final fallback = presentation ?? _presentationFor(dto.cardRef);
  final marketValue = _marketValueFor(
    fallback.prices,
    grader: dto.grader,
    grade: dto.grade,
    condition: dto.condition,
  );
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
    marketValueUsd: marketValue ?? fallback.marketValueUsd,
    previous30dPriceUsd: fallback.previous30dPriceUsd,
    createdAtSort: dto.createdAt.millisecondsSinceEpoch,
  );
}

CollectionItem _collectionItemFromWishlistDto(
  WishlistItemDto dto,
  _CollectionPresentation? presentation,
) {
  final fallback = presentation ?? _presentationFor(dto.cardRef);
  final marketValue = _marketValueFor(
    fallback.prices,
    grader: 'Raw',
    grade: null,
    condition: 'Near Mint (NM)',
  );
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
    marketValueUsd: marketValue ?? fallback.marketValueUsd,
    previous30dPriceUsd: fallback.previous30dPriceUsd,
    createdAtSort: dto.createdAt.millisecondsSinceEpoch,
  );
}

_CollectionPresentation _presentationFromCardData(
  CardDataCardDto card,
  List<CardDataMarketPriceDto> prices,
) {
  return _CollectionPresentation(
    name: card.name,
    setName: card.setName,
    number: '#${card.cardNumber}',
    game: _gameLabelFromObjectType(card.objectType),
    language: card.language ?? 'Unknown',
    finish: card.finish ?? 'Unknown',
    marketValueUsd: null,
    previous30dPriceUsd: null,
    prices: prices,
  );
}

double? _marketValueFor(
  List<CardDataMarketPriceDto> prices, {
  required String grader,
  required double? grade,
  required String? condition,
}) {
  if (prices.isEmpty) {
    return null;
  }

  for (final price in prices) {
    if (_matchesMarketPrice(
      price,
      grader: grader,
      grade: grade,
      condition: condition,
    )) {
      return price.price;
    }
  }

  for (final price in prices) {
    if (price.grader.toLowerCase() == 'raw') {
      return price.price;
    }
  }

  return prices.first.price;
}

bool _matchesMarketPrice(
  CardDataMarketPriceDto price, {
  required String grader,
  required double? grade,
  required String? condition,
}) {
  if (price.grader.toLowerCase() != grader.toLowerCase()) {
    return false;
  }
  if (grade != null && price.grade != grade) {
    return false;
  }
  if (condition != null &&
      price.condition?.toLowerCase() != condition.toLowerCase()) {
    return false;
  }
  return true;
}

String _gameLabelFromObjectType(String objectType) {
  return switch (objectType.trim().toLowerCase()) {
    'tcg' => 'TCG',
    'sports' => 'Sports',
    'sealed' => 'Sealed',
    _ => 'Other',
  };
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
        prices: const [],
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
    this.prices = const [],
  });

  final String name;
  final String setName;
  final String number;
  final String game;
  final String language;
  final String finish;
  final double? marketValueUsd;
  final double? previous30dPriceUsd;
  final List<CardDataMarketPriceDto> prices;
}
