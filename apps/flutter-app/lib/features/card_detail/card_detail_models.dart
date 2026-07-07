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

  bool get isCollected => quantity > 0;

  CardDetail copyWith({int? quantity, bool? isWishlisted}) {
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
    );
  }
}
