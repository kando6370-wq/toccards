import type {
  CardSearchResult,
  DataSourceAdapter,
  MarketPrice,
  PricePoint,
  SetSearchResult,
  SoldListing,
} from "../adapter";

const MOCK_CARDS: CardSearchResult[] = [
  {
    card_ref: "mock:tcg:charizard-base-4",
    name: "Charizard",
    set_name: "Base Set",
    set_code: "BS",
    card_number: "4/102",
    finish: "Holofoil",
    language: "English",
    object_type: "tcg",
    image_url: null,
    rarity: "Rare Holo",
  },
  {
    card_ref: "mock:tcg:charizard-evolutions-11",
    name: "Charizard",
    set_name: "Evolutions",
    set_code: "EVO",
    card_number: "11/108",
    finish: "Holofoil",
    language: "English",
    object_type: "tcg",
    image_url: null,
    rarity: "Rare Holo",
  },
  {
    card_ref: "mock:sealed:booster-box",
    name: "Booster Box",
    set_name: "Mock Sealed",
    set_code: "MS",
    card_number: "BOX",
    finish: null,
    language: "English",
    object_type: "sealed",
    image_url: null,
    rarity: null,
  },
];

const MOCK_MARKET_PRICES: Record<string, MarketPrice[]> = {
  "mock:tcg:charizard-base-4": [
    { grader: "Raw", grade: null, condition: "Near Mint", price: 1200 },
    { grader: "PSA", grade: 10, condition: null, price: 5000 },
  ],
};

const MOCK_PRICE_SERIES: Record<string, PricePoint[]> = {
  "mock:tcg:charizard-base-4": [
    { date: "2026-06-01", price: 4800 },
    { date: "2026-06-30", price: 5000 },
  ],
};

const MOCK_SOLD_LISTINGS: Record<string, SoldListing[]> = {
  "mock:tcg:charizard-base-4": [
    {
      date: "2026-06-29",
      title: "PSA 10 Charizard Base Set",
      price: 5000,
      platform: "mock-market",
      url: null,
    },
  ],
};

export function createMockDataSourceAdapter(): DataSourceAdapter {
  return {
    async searchCards(query, options = {}) {
      const normalizedQuery = query.trim().toLowerCase();
      const searchTerms = normalizedQuery.split(/\s+/).filter(Boolean);
      const page = positiveIntegerOrDefault(options.page, 1);
      const pageSize = positiveIntegerOrDefault(options.page_size, 20);
      const filtered = MOCK_CARDS.filter((card) => {
        const matchesType =
          !options.object_type || card.object_type === options.object_type;
        const matchesGame =
          !options.game || card.game?.toLowerCase() === options.game.toLowerCase();
        const matchesQuery =
          searchTerms.length === 0 ||
          searchTerms.every((term) =>
            `${card.name} ${card.card_number} ${card.set_name} ${card.set_code}`
              .toLowerCase()
              .includes(term),
          );

        return matchesType && matchesGame && matchesQuery;
      });
      const startIndex = (page - 1) * pageSize;

      return filtered.slice(startIndex, startIndex + pageSize);
    },

    async searchSets(query, options = {}) {
      const normalizedQuery = query.trim().toLowerCase();
      const sets = new Map<string, SetSearchResult>();
      for (const card of MOCK_CARDS) {
        if (options.game && card.game?.toLowerCase() !== options.game.toLowerCase()) {
          continue;
        }
        if (!`${card.set_name} ${card.set_code}`.toLowerCase().includes(normalizedQuery)) {
          continue;
        }
        const key = `${card.game ?? ""}\u0000${card.set_code}`;
        const existing = sets.get(key);
        if (existing) {
          existing.card_count += 1;
        } else {
          sets.set(key, {
            set_code: card.set_code,
            set_name: card.set_name,
            game: card.game ?? null,
            image_url: card.image_url,
            image_card_ref: card.image_url ? card.card_ref : null,
            card_count: 1,
          });
        }
      }
      const page = positiveIntegerOrDefault(options.page, 1);
      const pageSize = positiveIntegerOrDefault(options.page_size, 20);
      const startIndex = (page - 1) * pageSize;
      return [...sets.values()].slice(startIndex, startIndex + pageSize);
    },

    async getCard(cardRef) {
      return MOCK_CARDS.find((card) => card.card_ref === cardRef) ?? null;
    },

    async getPriceSeries(cardRef) {
      return MOCK_PRICE_SERIES[cardRef] ?? [];
    },

    async getMarketPrices(cardRef) {
      return MOCK_MARKET_PRICES[cardRef] ?? [];
    },

    async getTrending() {
      return MOCK_CARDS.slice(0, 2);
    },

    async getSoldListings(cardRef) {
      return MOCK_SOLD_LISTINGS[cardRef] ?? [];
    },
  };
}

function positiveIntegerOrDefault(
  value: number | undefined,
  fallback: number,
): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : fallback;
}
