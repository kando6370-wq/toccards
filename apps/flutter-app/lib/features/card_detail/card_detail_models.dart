enum CardDetailType { tcg, sports, sealed, other }

class CardMarketPrice {
  const CardMarketPrice({
    required this.label,
    required this.priceUsd,
    required this.previous30dPriceUsd,
  });

  final String label;
  final double? priceUsd;
  final double? previous30dPriceUsd;
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
    );
  }
}
