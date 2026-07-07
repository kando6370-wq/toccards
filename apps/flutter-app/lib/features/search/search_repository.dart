import 'search_models.dart';

abstract interface class SearchRepository {
  SearchCatalog loadCatalog();
}

class MockSearchRepository implements SearchRepository {
  const MockSearchRepository();

  @override
  SearchCatalog loadCatalog() {
    return const SearchCatalog(
      games: [
        SearchGame(id: 'pokemon', label: 'Pokemon'),
        SearchGame(id: 'lorcana', label: 'Lorcana'),
        SearchGame(id: 'one-piece', label: 'One Piece'),
      ],
      cards: [
        SearchCard(
          id: 'squirtle',
          gameId: 'pokemon',
          type: SearchCardType.tcg,
          name: 'Squirtle',
          priceUsd: 32.13,
          previous30dPriceUsd: 30.67,
          setName: 'Mega Evolution Promos',
          metadataLine: 'Promo · 039',
          variantLine: 'Holofoil',
          quantity: 0,
          isWishlisted: false,
        ),
        SearchCard(
          id: 'charizard-ex',
          gameId: 'pokemon',
          type: SearchCardType.tcg,
          name: 'Charizard ex',
          priceUsd: 780,
          previous30dPriceUsd: 721.58,
          setName: 'Obsidian Flames',
          metadataLine: 'Special Illustration Rare · 223',
          variantLine: 'PSA 10',
          quantity: 1,
          isWishlisted: false,
        ),
        SearchCard(
          id: 'mystery-promo',
          gameId: 'pokemon',
          type: SearchCardType.other,
          name: 'Mystery Promo',
          priceUsd: null,
          previous30dPriceUsd: null,
          setName: 'Promo Vault',
          metadataLine: 'Special Release',
          variantLine: 'Raw',
          quantity: 0,
          isWishlisted: false,
        ),
        SearchCard(
          id: 'lorcana-elsa',
          gameId: 'lorcana',
          type: SearchCardType.tcg,
          name: 'Lorcana Elsa',
          priceUsd: 480,
          previous30dPriceUsd: 449.86,
          setName: 'The First Chapter',
          metadataLine: 'Enchanted · 212',
          variantLine: 'Cold Foil',
          quantity: 0,
          isWishlisted: false,
        ),
        SearchCard(
          id: 'one-piece-luffy',
          gameId: 'one-piece',
          type: SearchCardType.tcg,
          name: 'One Piece Manga Luffy',
          priceUsd: 330,
          previous30dPriceUsd: 306.69,
          setName: 'Romance Dawn',
          metadataLine: 'Manga Rare · 001',
          variantLine: 'Japanese',
          quantity: 0,
          isWishlisted: true,
        ),
      ],
      sets: [
        SearchSet(
          id: 'mega-evolution-promos',
          gameId: 'pokemon',
          name: 'Mega Evolution Promos',
          subtitle: 'Pokemon promotional cards',
          releaseText: '2025',
          cardCountText: '124 cards',
        ),
        SearchSet(
          id: 'obsidian-flames',
          gameId: 'pokemon',
          name: 'Obsidian Flames',
          subtitle: 'Scarlet & Violet',
          releaseText: '2023',
          cardCountText: '230 cards',
        ),
        SearchSet(
          id: 'the-first-chapter',
          gameId: 'lorcana',
          name: 'The First Chapter',
          subtitle: 'Disney Lorcana',
          releaseText: '2023',
          cardCountText: '216 cards',
        ),
        SearchSet(
          id: 'romance-dawn',
          gameId: 'one-piece',
          name: 'Romance Dawn',
          subtitle: 'One Piece Card Game',
          releaseText: '2022',
          cardCountText: '121 cards',
        ),
      ],
    );
  }
}
