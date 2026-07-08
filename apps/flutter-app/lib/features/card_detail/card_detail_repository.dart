import 'card_detail_models.dart';

abstract interface class CardDetailRepository {
  CardDetail loadDetail(String cardId);
}

class MockCardDetailRepository implements CardDetailRepository {
  const MockCardDetailRepository();

  @override
  CardDetail loadDetail(String cardId) {
    return switch (cardId) {
      'squirtle' => const CardDetail(
        id: 'squirtle',
        type: CardDetailType.tcg,
        name: 'Squirtle',
        game: 'Pokemon',
        setName: 'Mega Evolution Promos',
        identityLine: 'Promo #039',
        finish: 'Holofoil',
        language: 'English',
        quantity: 0,
        isWishlisted: false,
        marketPrices: [
          CardMarketPrice(
            label: 'Raw Near Mint',
            priceUsd: 32.13,
            previous30dPriceUsd: 30.67,
          ),
          CardMarketPrice(
            label: 'PSA 10',
            priceUsd: 124.5,
            previous30dPriceUsd: 117.2,
          ),
        ],
      ),
      'charizard-ex' => const CardDetail(
        id: 'charizard-ex',
        type: CardDetailType.tcg,
        name: 'Charizard ex',
        game: 'Pokemon',
        setName: 'Obsidian Flames',
        identityLine: 'Special Illustration Rare #223/197',
        finish: 'Holofoil',
        language: 'English',
        quantity: 1,
        isWishlisted: false,
        marketPrices: [
          CardMarketPrice(
            label: 'PSA 10',
            priceUsd: 780,
            previous30dPriceUsd: 721.58,
          ),
          CardMarketPrice(
            label: 'Raw Near Mint',
            priceUsd: 215,
            previous30dPriceUsd: 204.5,
          ),
        ],
        collectionItems: [
          CardCollectionItem(
            id: 'item-charizard',
            portfolioName: 'Main',
            quantity: 1,
            grader: 'PSA',
            condition: null,
            grade: '10',
            purchasePriceUsd: 650,
            notes: 'Pulled from Obsidian Flames binder.',
          ),
        ],
      ),
      'mystery-promo' => const CardDetail(
        id: 'mystery-promo',
        type: CardDetailType.other,
        name: 'Mystery Promo',
        game: 'Pokemon',
        setName: 'Promo Vault',
        identityLine: 'Special Release',
        finish: 'Raw',
        language: 'English',
        quantity: 0,
        isWishlisted: false,
        marketPrices: [
          CardMarketPrice(
            label: 'Raw',
            priceUsd: null,
            previous30dPriceUsd: null,
          ),
        ],
      ),
      'one-piece-luffy' => const CardDetail(
        id: 'one-piece-luffy',
        type: CardDetailType.tcg,
        name: 'One Piece Manga Luffy',
        game: 'One Piece',
        setName: 'Romance Dawn',
        identityLine: 'Manga Rare #001',
        finish: 'Japanese',
        language: 'Japanese',
        quantity: 0,
        isWishlisted: true,
        marketPrices: [
          CardMarketPrice(
            label: 'Raw Near Mint',
            priceUsd: 330,
            previous30dPriceUsd: 306.69,
          ),
        ],
      ),
      _ => throw StateError('Unknown card detail id: $cardId'),
    };
  }
}
