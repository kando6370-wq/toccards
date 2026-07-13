import { Hono } from "hono";
import { describe, expect, it } from "vitest";
import app, { type Env } from "../index";
import type {
  CardSearchResult,
  DataSourceAdapter,
  MarketPrice,
  PricePoint,
  SoldListing,
} from "./adapter";
import { createMockDataSourceAdapter } from "./adapter";
import { createDataSourceRoutes } from "./routes";

class FakeKvNamespace {
  values = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.values.get(key) ?? null;
  }

  async put(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }
}

type CardOverrideRow = {
  card_ref: string;
  override_fields: string | null;
  image_url: string | null;
  is_missing_card: number;
};

type CardCatalogRow = {
  product_id: string;
  game_id: number;
  game: string | null;
  set_name: string | null;
  set_code: string | null;
  name: string | null;
  rarity: string | null;
  product_type_name: string | null;
  image_url: string | null;
};

type TrendingPinRow = {
  card_ref: string;
  rank: number;
  active: number;
};

class FakeD1Database {
  constructor(
    private readonly cardOverrides: CardOverrideRow[] = [],
    private readonly cards: CardCatalogRow[] = [],
    private readonly trendingPins: TrendingPinRow[] = [],
  ) {}

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(sql, this.cardOverrides, this.cards, this.trendingPins);
  }
}

class FakeD1Statement {
  constructor(
    private readonly sql: string,
    private readonly cardOverrides: CardOverrideRow[],
    private readonly cards: CardCatalogRow[],
    private readonly trendingPins: TrendingPinRow[],
  ) {}

  bind(...values: unknown[]): FakeD1BoundStatement {
    return new FakeD1BoundStatement(
      this.sql,
      this.cardOverrides,
      this.cards,
      this.trendingPins,
      values,
    );
  }

  all<T>(): Promise<{ results: T[] }> {
    return new FakeD1BoundStatement(
      this.sql,
      this.cardOverrides,
      this.cards,
      this.trendingPins,
      [],
    ).all<T>();
  }
}

class FakeD1BoundStatement {
  constructor(
    private readonly sql: string,
    private readonly cardOverrides: CardOverrideRow[],
    private readonly cards: CardCatalogRow[],
    private readonly trendingPins: TrendingPinRow[],
    private readonly values: unknown[],
  ) {}

  async first<T>(): Promise<T | null> {
    const cardRef = String(this.values[0]);

    if (this.sql.includes("FROM cards_all")) {
      const card = this.cards.find((row) => row.product_id === cardRef);

      if (card) {
        return card as T;
      }

      return null;
    }

    if (this.sql.includes("FROM card_override")) {
      return (this.cardOverrides.find((row) => row.card_ref === cardRef) ??
        null) as T | null;
    }

    return null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    if (this.sql.includes("FROM trending_pin")) {
      return {
        results: this.trendingPins
          .filter((pin) => pin.active === 1)
          .sort((left, right) => left.rank - right.rank) as T[],
      };
    }

    if (!this.sql.includes("FROM cards_all")) {
      return { results: [] };
    }

    const query = String(this.values[0]).replaceAll("%", "").toLowerCase();
    const limit = Number(this.values[1]);
    const offset = Number(this.values[2]);
    const results = this.cards
      .filter((card) =>
        [card.name, card.set_name, card.set_code, card.rarity, card.game]
          .filter(Boolean)
          .some((value) => value!.toLowerCase().includes(query)),
      )
      .slice(offset, offset + limit);

    return { results: results as T[] };
  }
}

class FailingDataSourceAdapter implements DataSourceAdapter {
  async searchCards(): Promise<CardSearchResult[]> {
    throw new Error("Injected search failure.");
  }

  async getCard(): Promise<CardSearchResult | null> {
    throw new Error("Injected card failure.");
  }

  async getPriceSeries(): Promise<PricePoint[]> {
    throw new Error("Injected price series failure.");
  }

  async getMarketPrices(): Promise<MarketPrice[]> {
    throw new Error("Injected market prices failure.");
  }

  async getTrending(): Promise<CardSearchResult[]> {
    throw new Error("Injected trending failure.");
  }

  async getSoldListings(): Promise<SoldListing[]> {
    throw new Error("Injected sold listings failure.");
  }
}

class MissingCardDataSourceAdapter implements DataSourceAdapter {
  async searchCards(): Promise<CardSearchResult[]> {
    return [];
  }

  async getCard(): Promise<CardSearchResult | null> {
    return null;
  }

  async getPriceSeries(): Promise<PricePoint[]> {
    return [];
  }

  async getMarketPrices(): Promise<MarketPrice[]> {
    return [];
  }

  async getTrending(): Promise<CardSearchResult[]> {
    return [];
  }

  async getSoldListings(): Promise<SoldListing[]> {
    return [];
  }
}

describe("data source routes", () => {
  it("uses current D1 card catalog tables by default because M2 no longer depends on third-party mock data", async () => {
    const response = await app.request(
      "/api/v1/cards/search?q=pikachu",
      {},
      createTestEnv([], [
        {
          product_id: "300",
          game_id: 3,
          game: "Pokemon",
          set_name: "Base Set",
          set_code: "BS",
          name: "Pikachu",
          rarity: "Common",
          product_type_name: "Cards",
          image_url: "https://img.example/300.jpg",
        },
      ]),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({
            card_ref: "300",
            name: "Pikachu",
            set_name: "Base Set",
            object_type: "tcg",
          }),
        ],
        total: 1,
        page: 1,
        page_size: 20,
      },
    });
  });

  it("builds trending from active D1 pins and local card rows because the local catalog has no third-party trending feed", async () => {
    const response = await app.request(
      "/api/v1/cards/trending",
      {},
      createTestEnv(
        [],
        [
          {
            product_id: "300",
            game_id: 3,
            game: "Pokemon",
            set_name: "Base Set",
            set_code: "BS",
            name: "Pikachu",
            rarity: "Common",
            product_type_name: "Cards",
            image_url: "https://img.example/300.jpg",
          },
        ],
        [{ card_ref: "300", rank: 1, active: 1 }],
      ),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({
            card_ref: "300",
            name: "Pikachu",
            pinned: true,
            override_applied: false,
          }),
        ],
      },
    });
  });

  it("keeps mock-backed M2 data proxy endpoints injectable because tests need a stable provider-independent contract", async () => {
    const routeApp = new Hono<{ Bindings: Env }>();
    routeApp.route(
      "/",
      createDataSourceRoutes({
        createAdapter: () => createMockDataSourceAdapter(),
      }),
    );
    const env = createTestEnv();

    const search = await routeApp.request(
      "/cards/search?q=charizard&page=1&page_size=1",
      {},
      env,
    );
    const sets = await routeApp.request("/sets/search?q=charizard", {}, env);
    const detail = await routeApp.request(
      `/cards/${encodeURIComponent("mock:tcg:charizard-base-4")}`,
      {},
      env,
    );
    const marketPrices = await routeApp.request(
      `/cards/${encodeURIComponent(
        "mock:tcg:charizard-base-4",
      )}/market-prices`,
      {},
      env,
    );
    const priceSeries = await routeApp.request(
      `/cards/${encodeURIComponent(
        "mock:tcg:charizard-base-4",
      )}/price-series?grader=Raw&condition=Near%20Mint&days=30`,
      {},
      env,
    );
    const trending = await routeApp.request("/cards/trending", {}, env);
    const soldListings = await routeApp.request(
      `/cards/${encodeURIComponent(
        "mock:tcg:charizard-base-4",
      )}/sold-listings`,
      {},
      env,
    );
    const rates = await routeApp.request(
      "/rates?base=USD&targets=JPY,EUR",
      {},
      env,
    );

    expect(search.status).toBe(200);
    expect(await search.json()).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({
            card_ref: "mock:tcg:charizard-base-4",
            name: "Charizard",
          }),
        ],
        total: 1,
        page: 1,
        page_size: 1,
      },
    });
    expect(sets.status).toBe(200);
    expect(await sets.json()).toEqual({
      success: true,
      data: {
        items: [
          {
            set_code: "BS",
            set_name: "Base Set",
            image_url: null,
            card_count: 1,
          },
          {
            set_code: "EVO",
            set_name: "Evolutions",
            image_url: null,
            card_count: 1,
          },
        ],
        total: 2,
        page: 1,
        page_size: 20,
      },
    });
    expect(detail.status).toBe(200);
    expect(await detail.json()).toEqual({
      success: true,
      data: expect.objectContaining({
        card_ref: "mock:tcg:charizard-base-4",
        override_applied: false,
      }),
    });
    expect(marketPrices.status).toBe(200);
    expect(await marketPrices.json()).toEqual({
      success: true,
      data: {
        card_ref: "mock:tcg:charizard-base-4",
        prices: [
          { grader: "Raw", grade: null, condition: "Near Mint", price: 1200, currency: "USD" },
          { grader: "PSA", grade: 10, condition: null, price: 5000, currency: "USD" },
        ],
        updated_at: expect.any(String),
      },
    });
    expect(priceSeries.status).toBe(200);
    expect(await priceSeries.json()).toEqual({
      success: true,
      data: {
        card_ref: "mock:tcg:charizard-base-4",
        grader: "Raw",
        grade: null,
        condition: "Near Mint",
        days: 30,
        series: [
          { date: "2026-06-01", price: 4800 },
          { date: "2026-06-30", price: 5000 },
        ],
      },
    });
    expect(trending.status).toBe(200);
    expect(await trending.json()).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({
            card_ref: "mock:tcg:charizard-base-4",
            pinned: false,
          }),
          expect.objectContaining({
            card_ref: "mock:tcg:charizard-evolutions-11",
            pinned: false,
          }),
        ],
      },
    });
    expect(soldListings.status).toBe(200);
    expect(await soldListings.json()).toEqual({
      success: true,
      data: {
        items: [
          {
            date: "2026-06-29",
            title: "PSA 10 Charizard Base Set",
            price: 5000,
            currency: "USD",
            platform: "mock-market",
            url: null,
          },
        ],
      },
    });
    expect(rates.status).toBe(200);
    expect(await rates.json()).toEqual({
      success: true,
      data: {
        base: "USD",
        rates: { JPY: 155.32, EUR: 0.91 },
        updated_at: expect.any(String),
      },
    });
  });

  it("applies card_override to card detail because admin corrections must take precedence over provider data", async () => {
    const cardRef = "mock:tcg:charizard-base-4";
    const routeApp = new Hono<{ Bindings: Env }>();
    routeApp.route(
      "/",
      createDataSourceRoutes({
        createAdapter: () => createMockDataSourceAdapter(),
      }),
    );

    const detail = await routeApp.request(
      `/cards/${encodeURIComponent(cardRef)}`,
      {},
      createTestEnv([
        {
          card_ref: cardRef,
          override_fields: JSON.stringify({
            name: "Corrected Charizard",
            rarity: "Promo",
          }),
          image_url: "https://cdn.example.test/charizard.png",
          is_missing_card: 0,
        },
      ]),
    );

    expect(detail.status).toBe(200);
    expect(await detail.json()).toEqual({
      success: true,
      data: expect.objectContaining({
        card_ref: cardRef,
        name: "Corrected Charizard",
        set_code: "BS",
        rarity: "Promo",
        image_url: "https://cdn.example.test/charizard.png",
        override_applied: true,
      }),
    });
  });

  it("serves an is_missing_card override when the provider has no card because operations can manually backfill missing catalog data", async () => {
    const cardRef = "admin:tcg:missing-promo";
    const routeApp = new Hono<{ Bindings: Env }>();
    routeApp.route(
      "/",
      createDataSourceRoutes({
        createAdapter: () => new MissingCardDataSourceAdapter(),
      }),
    );

    const detail = await routeApp.request(
      `/cards/${encodeURIComponent(cardRef)}`,
      {},
      createTestEnv([
        {
          card_ref: cardRef,
          override_fields: JSON.stringify({
            name: "Missing Promo",
            set_name: "Admin Backfill",
            set_code: "ADM",
            card_number: "P-1",
            finish: null,
            language: "English",
            object_type: "tcg",
            rarity: "Promo",
          }),
          image_url: "https://cdn.example.test/missing-promo.png",
          is_missing_card: 1,
        },
      ]),
    );

    expect(detail.status).toBe(200);
    expect(await detail.json()).toEqual({
      success: true,
      data: {
        card_ref: cardRef,
        name: "Missing Promo",
        set_name: "Admin Backfill",
        set_code: "ADM",
        card_number: "P-1",
        finish: null,
        language: "English",
        object_type: "tcg",
        image_url: "https://cdn.example.test/missing-promo.png",
        rarity: "Promo",
        override_applied: true,
      },
    });
  });

  it("applies card_override to trending items because the home feed must show the same corrected card data as detail", async () => {
    const cardRef = "mock:tcg:charizard-base-4";
    const routeApp = new Hono<{ Bindings: Env }>();
    routeApp.route(
      "/",
      createDataSourceRoutes({
        createAdapter: () => createMockDataSourceAdapter(),
      }),
    );

    const trending = await routeApp.request(
      "/cards/trending",
      {},
      createTestEnv([
        {
          card_ref: cardRef,
          override_fields: JSON.stringify({ name: "Trending Charizard" }),
          image_url: "https://cdn.example.test/trending-charizard.png",
          is_missing_card: 0,
        },
      ]),
    );

    expect(trending.status).toBe(200);
    expect(await trending.json()).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({
            card_ref: cardRef,
            name: "Trending Charizard",
            image_url: "https://cdn.example.test/trending-charizard.png",
            pinned: false,
            override_applied: true,
          }),
          expect.objectContaining({
            card_ref: "mock:tcg:charizard-evolutions-11",
            pinned: false,
            override_applied: false,
          }),
        ],
      },
    });
  });

  it("returns documented fallback payloads when the adapter fails because proxy routes must degrade without 500s", async () => {
    const routeApp = new Hono<{ Bindings: Env }>();
    routeApp.route(
      "/",
      createDataSourceRoutes({
        createAdapter: () => new FailingDataSourceAdapter(),
      }),
    );

    const search = await routeApp.request(
      "/cards/search?q=charizard",
      {},
      createTestEnv(),
    );
    const sets = await routeApp.request(
      "/sets/search?q=charizard",
      {},
      createTestEnv(),
    );
    const marketPrices = await routeApp.request(
      `/cards/${encodeURIComponent("mock:tcg:charizard-base-4")}/market-prices`,
      {},
      createTestEnv(),
    );
    const priceSeries = await routeApp.request(
      `/cards/${encodeURIComponent(
        "mock:tcg:charizard-base-4",
      )}/price-series?grader=Raw&condition=Near%20Mint&days=30`,
      {},
      createTestEnv(),
    );
    const trending = await routeApp.request(
      "/cards/trending",
      {},
      createTestEnv(),
    );
    const soldListings = await routeApp.request(
      `/cards/${encodeURIComponent("mock:tcg:charizard-base-4")}/sold-listings`,
      {},
      createTestEnv(),
    );
    const detail = await routeApp.request(
      `/cards/${encodeURIComponent("mock:tcg:charizard-base-4")}`,
      {},
      createTestEnv(),
    );

    expect(search.status).toBe(200);
    expect(await search.json()).toEqual({
      success: true,
      data: { items: [], total: 0, page: 1, page_size: 20 },
    });
    expect(sets.status).toBe(200);
    expect(await sets.json()).toEqual({
      success: true,
      data: { items: [], total: 0, page: 1, page_size: 20 },
    });
    expect(marketPrices.status).toBe(200);
    expect(await marketPrices.json()).toEqual({
      success: true,
      data: {
        card_ref: "mock:tcg:charizard-base-4",
        prices: [],
        updated_at: expect.any(String),
      },
    });
    expect(priceSeries.status).toBe(200);
    expect(await priceSeries.json()).toEqual({
      success: true,
      data: {
        card_ref: "mock:tcg:charizard-base-4",
        grader: "Raw",
        grade: null,
        condition: "Near Mint",
        days: 30,
        series: [],
      },
    });
    expect(trending.status).toBe(200);
    expect(await trending.json()).toEqual({
      success: true,
      data: { items: [] },
    });
    expect(soldListings.status).toBe(200);
    expect(await soldListings.json()).toEqual({
      success: true,
      data: { items: [] },
    });
    expect(detail.status).toBe(404);
    expect(await detail.json()).toEqual({
      success: false,
      error: { code: "NOT_FOUND", message: "Not found." },
    });
  });
});

function createTestEnv(
  cardOverrides: CardOverrideRow[] = [],
  cards: CardCatalogRow[] = [],
  trendingPins: TrendingPinRow[] = [],
): Env {
  return {
    DB: new FakeD1Database(cardOverrides, cards, trendingPins) as unknown as D1Database,
    CACHE_KV: new FakeKvNamespace() as unknown as KVNamespace,
    JWT_SECRET: "test-secret",
  };
}
