import 'package:kando_app/shared/market/market_change.dart';

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

  bool get isCollected => quantity > 0;

  String get searchableText {
    return '$name $setName $metadataLine $variantLine'.toLowerCase();
  }

  String get priceText {
    final value = priceUsd;
    if (value == null) {
      return '--';
    }

    return r'$' + value.toStringAsFixed(2);
  }

  String get changeText {
    return MarketChange.fromPrices(
      current: priceUsd,
      previous: previous30dPriceUsd,
    ).percentText;
  }

  SearchCard copyWith({int? quantity, bool? isWishlisted}) {
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
  });

  final String id;
  final String gameId;
  final String name;
  final String subtitle;
  final String releaseText;
  final String cardCountText;

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
