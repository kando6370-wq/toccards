import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';

const _searchCardFieldUnset = Object();

enum SearchTab { cards, sets }

enum SearchCardType { tcg, sports, sealed, other }

class SearchGame {
  const SearchGame({required this.id, required this.label});

  final String id;
  final String label;
}

class SearchCard {
  const SearchCard({
    required this.id,
    required this.gameId,
    required this.type,
    required this.name,
    required this.priceUsd,
    required this.previous30dPriceUsd,
    required this.setName,
    required this.metadataLine,
    required this.variantLine,
    required this.quantity,
    required this.isWishlisted,
    this.collectionItemCount = 0,
    this.collectionItemId,
    this.wishlistItemId,
    this.collectionInfo,
    this.language,
    this.finish,
    this.imageUrl,
  });

  final String id;
  final String gameId;
  final SearchCardType type;
  final String name;
  final double? priceUsd;
  final double? previous30dPriceUsd;
  final String setName;
  final String metadataLine;
  final String variantLine;
  final int quantity;
  final bool isWishlisted;
  final int collectionItemCount;
  final String? collectionItemId;
  final String? wishlistItemId;
  final String? collectionInfo;
  final String? language;
  final String? finish;
  final String? imageUrl;

  bool get isCollected => quantity > 0;

  String get searchableText {
    return '$name $setName $metadataLine $variantLine ${language ?? ''}'
        .toLowerCase();
  }

  String priceText(AppCurrency currency) {
    return CurrencyFormatter(currency: currency).formatUsd(priceUsd);
  }

  String get changeText {
    return MarketChange.fromPrices(
      current: priceUsd,
      previous: previous30dPriceUsd,
    ).percentText;
  }

  SearchCard copyWith({
    int? quantity,
    bool? isWishlisted,
    int? collectionItemCount,
    Object? collectionItemId = _searchCardFieldUnset,
    Object? wishlistItemId = _searchCardFieldUnset,
    Object? collectionInfo = _searchCardFieldUnset,
  }) {
    return SearchCard(
      id: id,
      gameId: gameId,
      type: type,
      name: name,
      priceUsd: priceUsd,
      previous30dPriceUsd: previous30dPriceUsd,
      setName: setName,
      metadataLine: metadataLine,
      variantLine: variantLine,
      quantity: quantity ?? this.quantity,
      isWishlisted: isWishlisted ?? this.isWishlisted,
      collectionItemCount: collectionItemCount ?? this.collectionItemCount,
      collectionItemId: collectionItemId == _searchCardFieldUnset
          ? this.collectionItemId
          : collectionItemId as String?,
      wishlistItemId: wishlistItemId == _searchCardFieldUnset
          ? this.wishlistItemId
          : wishlistItemId as String?,
      collectionInfo: collectionInfo == _searchCardFieldUnset
          ? this.collectionInfo
          : collectionInfo as String?,
      language: language,
      finish: finish,
      imageUrl: imageUrl,
    );
  }
}

class SearchSet {
  const SearchSet({
    required this.id,
    required this.gameId,
    required this.name,
    required this.subtitle,
    required this.releaseText,
    required this.cardCountText,
    this.game = 'TCG',
    this.imageUrl,
  });

  final String id;
  final String gameId;
  final String name;
  final String subtitle;
  final String releaseText;
  final String cardCountText;
  final String game;
  final String? imageUrl;

  String get searchableText {
    return '$name $subtitle $releaseText'.toLowerCase();
  }
}

class SearchCatalog {
  const SearchCatalog({
    required this.games,
    required this.cards,
    required this.sets,
  });

  final List<SearchGame> games;
  final List<SearchCard> cards;
  final List<SearchSet> sets;

  SearchGame get defaultGame => games.first;
}
