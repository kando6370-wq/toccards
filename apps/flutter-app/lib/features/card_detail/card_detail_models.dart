enum CardDetailType { tcg, sports, sealed, other }

const _cardCollectionItemUnset = Object();

enum CardPriceRange {
  oneDay(1, '1d'),
  sevenDays(7, '7d'),
  fifteenDays(15, '15d'),
  oneMonth(30, '1m'),
  threeMonths(90, '3m');

  const CardPriceRange(this.days, this.label);

  final int days;
  final String label;
}

enum CardPriceChartMode {
  raw('RAW'),
  graded('GRADED');

  const CardPriceChartMode(this.label);

  final String label;
}

enum CardMarketPriceCategory {
  ungraded('Raw', 'Ungraded'),
  psa('PSA', 'PSA'),
  ace('ACE', 'ACE'),
  bgs('BGS', 'BGS');

  const CardMarketPriceCategory(this.grader, this.label);

  final String grader;
  final String label;
}

class CardMarketPrice {
  const CardMarketPrice({
    required this.label,
    required this.priceUsd,
    required this.previous30dPriceUsd,
    this.previous7dPriceUsd,
    this.grader = 'Raw',
    this.grade,
    this.condition,
  });

  final String label;
  final double? priceUsd;
  final double? previous30dPriceUsd;
  final double? previous7dPriceUsd;
  final String grader;
  final double? grade;
  final String? condition;
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
    this.url,
  });

  final String dateText;
  final String title;
  final double? priceUsd;
  final String platform;
  final String? url;
}

class CardPortfolioFolder {
  const CardPortfolioFolder({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final bool isDefault;
}

class CardCollectionItem {
  const CardCollectionItem({
    required this.id,
    this.cardRef = '',
    this.folderId,
    required this.portfolioName,
    required this.quantity,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.language,
    required this.finish,
    required this.purchasePriceUsd,
    required this.notes,
  });

  final String id;
  final String cardRef;
  final String? folderId;
  final String portfolioName;
  final int quantity;
  final String grader;
  final String? condition;
  final String? grade;
  final String? language;
  final String? finish;
  final double? purchasePriceUsd;
  final String notes;

  CardCollectionItem copyWith({
    String? cardRef,
    Object? folderId = _cardCollectionItemUnset,
    String? portfolioName,
    int? quantity,
    String? grader,
    Object? condition = _cardCollectionItemUnset,
    Object? grade = _cardCollectionItemUnset,
    Object? language = _cardCollectionItemUnset,
    Object? finish = _cardCollectionItemUnset,
    Object? purchasePriceUsd = _cardCollectionItemUnset,
    String? notes,
  }) {
    return CardCollectionItem(
      id: id,
      cardRef: cardRef ?? this.cardRef,
      folderId: folderId == _cardCollectionItemUnset
          ? this.folderId
          : folderId as String?,
      portfolioName: portfolioName ?? this.portfolioName,
      quantity: quantity ?? this.quantity,
      grader: grader ?? this.grader,
      condition: condition == _cardCollectionItemUnset
          ? this.condition
          : condition as String?,
      grade: grade == _cardCollectionItemUnset ? this.grade : grade as String?,
      language: language == _cardCollectionItemUnset
          ? this.language
          : language as String?,
      finish: finish == _cardCollectionItemUnset
          ? this.finish
          : finish as String?,
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
    this.imageUrl,
    required this.type,
    required this.name,
    required this.game,
    required this.setName,
    required this.identityLine,
    required this.finish,
    required this.language,
    required this.quantity,
    required this.isWishlisted,
    this.wishlistItemId,
    required this.marketPrices,
    this.portfolioFolders = const [],
    this.collectionItems = const [],
    this.priceSeriesByRange = const {},
    this.gradedPriceSeriesByRange = const {},
    this.soldListings = const [],
  });

  final String id;
  final String? imageUrl;
  final CardDetailType type;
  final String name;
  final String game;
  final String setName;
  final String identityLine;
  final String finish;
  final String language;
  final int quantity;
  final bool isWishlisted;
  final String? wishlistItemId;
  final List<CardMarketPrice> marketPrices;
  final List<CardPortfolioFolder> portfolioFolders;
  final List<CardCollectionItem> collectionItems;
  final Map<CardPriceRange, List<CardPricePoint>> priceSeriesByRange;
  final Map<CardPriceRange, List<CardPricePoint>> gradedPriceSeriesByRange;
  final List<CardSoldListing> soldListings;

  bool get isCollected => quantity > 0 || collectionItems.isNotEmpty;

  CardDetail copyWith({
    int? quantity,
    bool? isWishlisted,
    Object? wishlistItemId = _cardCollectionItemUnset,
    List<CardMarketPrice>? marketPrices,
    List<CardPortfolioFolder>? portfolioFolders,
    List<CardCollectionItem>? collectionItems,
    Map<CardPriceRange, List<CardPricePoint>>? priceSeriesByRange,
    Map<CardPriceRange, List<CardPricePoint>>? gradedPriceSeriesByRange,
    List<CardSoldListing>? soldListings,
  }) {
    return CardDetail(
      id: id,
      imageUrl: imageUrl,
      type: type,
      name: name,
      game: game,
      setName: setName,
      identityLine: identityLine,
      finish: finish,
      language: language,
      quantity: quantity ?? this.quantity,
      isWishlisted: isWishlisted ?? this.isWishlisted,
      wishlistItemId: wishlistItemId == _cardCollectionItemUnset
          ? this.wishlistItemId
          : wishlistItemId as String?,
      marketPrices: marketPrices ?? this.marketPrices,
      portfolioFolders: portfolioFolders ?? this.portfolioFolders,
      collectionItems: collectionItems ?? this.collectionItems,
      priceSeriesByRange: priceSeriesByRange ?? this.priceSeriesByRange,
      gradedPriceSeriesByRange:
          gradedPriceSeriesByRange ?? this.gradedPriceSeriesByRange,
      soldListings: soldListings ?? this.soldListings,
    );
  }
}
