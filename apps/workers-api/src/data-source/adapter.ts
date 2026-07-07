export type CardObjectType = "tcg" | "sports" | "sealed" | "other";

export type CardSearchOptions = {
  object_type?: CardObjectType;
  page?: number;
  page_size?: number;
};

export type CardSearchResult = {
  card_ref: string;
  name: string;
  set_name: string;
  set_code: string;
  card_number: string;
  finish: string | null;
  language: string | null;
  object_type: CardObjectType;
  image_url: string | null;
  rarity: string | null;
};

export type PricePoint = {
  date: string;
  price: number;
};

export type MarketPrice = {
  grader: string;
  grade: number | null;
  condition: string | null;
  price: number | null;
};

export type SoldListing = {
  date: string;
  title: string;
  price: number;
  platform: string;
  url: string | null;
};

export interface DataSourceAdapter {
  searchCards(
    query: string,
    options?: CardSearchOptions,
  ): Promise<CardSearchResult[]>;
  getCard(card_ref: string): Promise<CardSearchResult | null>;
  getPriceSeries(
    card_ref: string,
    grader: string,
    grade: number | null,
    condition: string | null,
    days: number,
  ): Promise<PricePoint[]>;
  getMarketPrices(card_ref: string): Promise<MarketPrice[]>;
  getTrending(): Promise<CardSearchResult[]>;
  getSoldListings(card_ref: string): Promise<SoldListing[]>;
}

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
      const page = positiveIntegerOrDefault(options.page, 1);
      const pageSize = positiveIntegerOrDefault(options.page_size, 20);
      const filtered = MOCK_CARDS.filter((card) => {
        const matchesType =
          !options.object_type || card.object_type === options.object_type;
        const matchesQuery =
          normalizedQuery.length === 0 ||
          [card.name, card.set_name, card.set_code, card.card_number].some(
            (value) => value.toLowerCase().includes(normalizedQuery),
          );

        return matchesType && matchesQuery;
      });
      const startIndex = (page - 1) * pageSize;

      return filtered.slice(startIndex, startIndex + pageSize);
    },

    async getCard(card_ref) {
      return MOCK_CARDS.find((card) => card.card_ref === card_ref) ?? null;
    },

    async getPriceSeries(card_ref) {
      return MOCK_PRICE_SERIES[card_ref] ?? [];
    },

    async getMarketPrices(card_ref) {
      return MOCK_MARKET_PRICES[card_ref] ?? [];
    },

    async getTrending() {
      return MOCK_CARDS.slice(0, 2);
    },

    async getSoldListings(card_ref) {
      return MOCK_SOLD_LISTINGS[card_ref] ?? [];
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
