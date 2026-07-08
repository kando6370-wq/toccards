enum CardDetailType { tcg, sports, sealed, other }

const _cardCollectionItemUnset = Object();

enum CardPriceRange {
  seven(7, '7D'),
  thirty(30, '30D'),
  ninety(90, '90D'),
  oneEighty(180, '180D'),
  year(365, '365D');

  const CardPriceRange(this.days, this.label);

  final int days;
  final String label;
}

class CardMarketPrice {
  const CardMarketPrice({
    required this.label,
    required this.priceUsd,
    required this.previous30dPriceUsd,
    this.previous7dPriceUsd,
  });

  final String label;
  final double? priceUsd;
  final double? previous30dPriceUsd;
  final double? previous7dPriceUsd;
}

class CardPricePoint {
  const CardPricePoint({required this.dateLabel, required this.priceUsd});

  final String dateLabel;
  final double? priceUsd;
}

class CardSoldListing {
  const CardSoldListing({
    required this.dateText,
    required this.title,
    required this.priceUsd,
    required this.platform,
  });

  final String dateText;
  final String title;
  final double? priceUsd;
  final String platform;
}

class CardCollectionItem {
  const CardCollectionItem({
    required this.id,
    required this.portfolioName,
    required this.quantity,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.purchasePriceUsd,
    required this.notes,
  });

  final String id;
  final String portfolioName;
  final int quantity;
  final String grader;
  final String? condition;
  final String? grade;
  final double? purchasePriceUsd;
  final String notes;

  CardCollectionItem copyWith({
    String? portfolioName,
    int? quantity,
    String? grader,
    Object? condition = _cardCollectionItemUnset,
    Object? grade = _cardCollectionItemUnset,
    Object? purchasePriceUsd = _cardCollectionItemUnset,
    String? notes,
  }) {
    return CardCollectionItem(
      id: id,
      portfolioName: portfolioName ?? this.portfolioName,
      quantity: quantity ?? this.quantity,
      grader: grader ?? this.grader,
      condition: condition == _cardCollectionItemUnset
          ? this.condition
          : condition as String?,
      grade: grade == _cardCollectionItemUnset ? this.grade : grade as String?,
      purchasePriceUsd: purchasePriceUsd == _cardCollectionItemUnset
          ? this.purchasePriceUsd
          : purchasePriceUsd as double?,
      notes: notes ?? this.notes,
    );
  }
}

class CardDetail {
  const CardDetail({
    required this.id,
    required this.type,
    required this.name,
    required this.game,
    required this.setName,
    required this.identityLine,
    required this.finish,
    required this.language,
    required this.quantity,
    required this.isWishlisted,
    required this.marketPrices,
    this.collectionItems = const [],
    this.priceSeriesByRange = const {},
    this.soldListings = const [],
  });

  final String id;
  final CardDetailType type;
  final String name;
  final String game;
  final String setName;
  final String identityLine;
  final String finish;
  final String language;
  final int quantity;
  final bool isWishlisted;
  final List<CardMarketPrice> marketPrices;
  final List<CardCollectionItem> collectionItems;
  final Map<CardPriceRange, List<CardPricePoint>> priceSeriesByRange;
  final List<CardSoldListing> soldListings;

  bool get isCollected => quantity > 0 || collectionItems.isNotEmpty;

  CardDetail copyWith({
    int? quantity,
    bool? isWishlisted,
    List<CardCollectionItem>? collectionItems,
  }) {
    return CardDetail(
      id: id,
      type: type,
      name: name,
      game: game,
      setName: setName,
      identityLine: identityLine,
      finish: finish,
      language: language,
      quantity: quantity ?? this.quantity,
      isWishlisted: isWishlisted ?? this.isWishlisted,
      marketPrices: marketPrices,
      collectionItems: collectionItems ?? this.collectionItems,
      priceSeriesByRange: priceSeriesByRange,
      soldListings: soldListings,
    );
  }
}
