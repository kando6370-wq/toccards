import { Hono } from "hono";
import { afterEach, describe, expect, it, vi } from "vitest";
import app, { type Env } from "../index";
import type {
  CardSearchResult,
  DataSourceAdapter,
  MarketPrice,
  PricePoint,
  SetSearchResult,
  SoldListing,
} from "./adapter";
import { createDataSourceRoutes } from "./routes";
import { createMockDataSourceAdapter } from "./test-support/mock-data-source-adapter";

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

type SetCatalogRow = {
  game: string;
  name: string;
  set_code: string | null;
  set_image_id: string | null;
  total_cards: number | null;
};

type GameCatalogRow = {
  game_id: number;
  name: string;
  load: number;
  search_sort: number;
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
    private readonly sets: SetCatalogRow[] = [],
    private readonly games: GameCatalogRow[] = [],
  ) {}

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(
      sql,
      this.cardOverrides,
      this.cards,
      this.trendingPins,
      this.sets,
      this.games,
    );
  }
}

class FakeD1Statement {
  constructor(
    private readonly sql: string,
    private readonly cardOverrides: CardOverrideRow[],
    private readonly cards: CardCatalogRow[],
    private readonly trendingPins: TrendingPinRow[],
    private readonly sets: SetCatalogRow[],
    private readonly games: GameCatalogRow[],
  ) {}

  bind(...values: unknown[]): FakeD1BoundStatement {
    return new FakeD1BoundStatement(
      this.sql,
      this.cardOverrides,
      this.cards,
      this.trendingPins,
      this.sets,
      this.games,
      values,
    );
  }

  all<T>(): Promise<{ results: T[] }> {
    return new FakeD1BoundStatement(
      this.sql,
      this.cardOverrides,
      this.cards,
      this.trendingPins,
      this.sets,
      this.games,
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
    private readonly sets: SetCatalogRow[],
    private readonly games: GameCatalogRow[],
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

    if (this.sql.includes("FROM games")) {
      return {
        results: this.games
          .filter((game) => game.load === 1 && game.name.trim())
          .sort(
            (left, right) =>
              left.search_sort - right.search_sort ||
              left.game_id - right.game_id,
          )
          .map((game) => ({ id: String(game.game_id), name: game.name })) as T[],
      };
    }

    if (this.sql.includes("FROM sets s")) {
      const query = String(this.values[0]).replaceAll("%", "").toLowerCase();
      const hasGameFilter = this.sql.includes("lower(s.game) = lower(?)");
      const game = hasGameFilter ? String(this.values[1]).toLowerCase() : null;
      const limit = Number(this.values[hasGameFilter ? 2 : 1]);
      const offset = Number(this.values[hasGameFilter ? 3 : 2]);
      const results = this.sets
        .filter(
          (set) =>
            (game === null || set.game.toLowerCase() === game) &&
            `${set.name} ${set.set_code ?? ""}`
              .toLowerCase()
              .includes(query) &&
            Boolean(set.set_code?.trim()),
        )
        .sort((left, right) => left.name.localeCompare(right.name))
        .slice(offset, offset + limit)
        .map((set) => ({
          set_code: set.set_code,
          set_name: set.name,
          game: set.game,
          image_url: null,
          image_card_ref: set.set_image_id?.trim() || null,
          card_count: set.total_cards ?? 0,
        }));
      return { results: results as T[] };
    }

    if (!this.sql.includes("FROM cards_all")) {
      return { results: [] };
    }

    const query = String(this.values[0]).replaceAll("%", "").toLowerCase();
    const hasGameFilter = this.sql.includes("lower(game) = lower(?)");
    const hasSetFilter = this.sql.includes("lower(set_code) = lower(?)");
    const game = hasGameFilter ? String(this.values[1]).toLowerCase() : null;
    const setCode = hasSetFilter
      ? String(this.values[hasGameFilter ? 2 : 1]).toLowerCase()
      : null;
    const filterCount = Number(hasGameFilter) + Number(hasSetFilter);
    const limit = Number(this.values[1 + filterCount]);
    const offset = Number(this.values[2 + filterCount]);
    const catalogCards = this.sql.includes("product_type_name = 'Cards'")
      ? this.cards.filter((card) => card.product_type_name === "Cards")
      : this.cards;
    const gameCards = catalogCards.filter(
      (card) =>
        (game === null || card.game?.toLowerCase() === game) &&
        (setCode === null || card.set_code?.toLowerCase() === setCode),
    );

    if (this.sql.includes("GROUP BY game_id")) {
      const sets = new Map<string, Record<string, unknown>>();
      for (const card of gameCards) {
        if (
          !`${card.set_name ?? ""} ${card.set_code ?? ""}`
            .toLowerCase()
            .includes(query) ||
          !card.set_name?.trim() ||
          !card.set_code?.trim()
        ) {
          continue;
        }
        const key = `${card.game_id}\u0000${card.set_code}\u0000${card.set_name}`;
        const existing = sets.get(key);
        if (existing) {
          existing.card_count = Number(existing.card_count) + 1;
        } else {
          sets.set(key, {
            set_code: card.set_code,
            set_name: card.set_name,
            game: card.game,
            image_url: card.image_url,
            image_card_ref: card.image_url ? card.product_id : null,
            card_count: 1,
          });
        }
      }
      return { results: [...sets.values()].slice(offset, offset + limit) as T[] };
    }

    const results = this.cards
      .filter((card) => gameCards.includes(card))
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

  async searchSets(): Promise<SetSearchResult[]> {
    throw new Error("Injected set search failure.");
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

  async searchSets() {
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
  afterEach(() => {
    vi.unstubAllGlobals();
  });

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
        page_size: 40,
      },
    });
  });

  it("returns only Cards products because the app card grid must exclude sealed products", async () => {
    const response = await app.request(
      "/api/v1/cards/search?q=charizard",
      {},
      createTestEnv([], [
        {
          product_id: "card-1",
          game_id: 3,
          game: "Pokemon",
          set_name: "Base Set",
          set_code: "BS",
          name: "Charizard",
          rarity: "Rare",
          product_type_name: "Cards",
          image_url: null,
        },
        {
          product_id: "box-1",
          game_id: 3,
          game: "Pokemon",
          set_name: "Base Set",
          set_code: "BS",
          name: "Charizard Booster Box",
          rarity: null,
          product_type_name: "Booster Box",
          image_url: null,
        },
      ]),
    );

    const body = await response.json<{ data: { items: Array<{ card_ref: string }> } }>();
    expect(body.data.items.map((item) => item.card_ref)).toEqual(["card-1"]);
  });

  it("does not let admin pins override Trending Today because the feed order is defined by real price change", async () => {
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
    expect(await response.json()).toEqual({ success: true, data: { items: [] } });
  });

  it("returns transformed R2 detail images and redirects the legacy image route to the R2 master because card rendering must not depend on provider images", async () => {
    const imageUrl =
      "https://product-images.tcgplayer.com/filters:quality(100)/9359.jpg";
    const env = createTestEnv([], [
      {
        product_id: "9359",
        game_id: 1,
        game: "Magic",
        set_name: "Odyssey",
        set_code: "ODY",
        name: "Escape Artist",
        rarity: "Common",
        product_type_name: "Cards",
        image_url: imageUrl,
      },
    ]);
    const detail = await app.request(
      "https://api.tcgcard.fun/api/v1/cards/9359",
      { headers: { Origin: "http://localhost:3000" } },
      env,
    );
    const image = await app.request(
      "https://api.tcgcard.fun/api/v1/cards/9359/image",
      { headers: { Origin: "http://localhost:3000" } },
      env,
    );

    expect(await detail.json()).toEqual({
      success: true,
      data: expect.objectContaining({
        card_ref: "9359",
        image_url: "https://image.tcgcard.fun/cards/9359.jpg",
      }),
    });
    expect(image.status).toBe(302);
    expect(image.headers.get("location")).toBe(
      "https://image.tcgcard.fun/cards/9359.jpg",
    );
    expect(image.headers.get("access-control-allow-origin")).toBe(
      "http://localhost:3000",
    );
  });

  it("ignores provider image hosts because every catalog card must render from R2", async () => {
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

    expect(await response.json()).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({
            card_ref: "300",
            image_url: "https://image.tcgcard.fun/cards/300.jpg",
          }),
        ],
        total: 1,
        page: 1,
        page_size: 40,
      },
    });
  });

  it("keeps mock-backed M2 data proxy endpoints injectable because tests need a stable provider-independent contract", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json({
          amount: 1,
          base: "USD",
          date: "2026-07-14",
          rates: {
            AUD: 1.4404,
            CAD: 1.4112,
            EUR: 0.87681,
            GBP: 0.74717,
            JPY: 162.22,
            NZD: 1.724,
            SGD: 1.2927,
          },
        }),
      ),
    );
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
    const sets = await routeApp.request("/sets/search?q=t", {}, env);
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
            game: null,
            image_url: null,
            card_count: 1,
          },
          {
            set_code: "EVO",
            set_name: "Evolutions",
            game: null,
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
    expect(marketPrices.headers.get("Cache-Control")).toBe("no-store");
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
    expect(priceSeries.headers.get("Cache-Control")).toBe("no-store");
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
    expect(soldListings.headers.get("Cache-Control")).toBe("no-store");
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
        rates: { JPY: 162.22, EUR: 0.87681 },
        updated_at: "2026-07-14T00:00:00.000Z",
        stale: false,
      },
    });
  });

  it("keeps sets with the same code separate across games because Search filters sets by their real game", async () => {
    const env = createTestEnv(
      [],
      [
        {
          product_id: "pokemon-1",
          game_id: 3,
          game: "Pokemon",
          set_name: "Shared Pokemon Set",
          set_code: "SHARED",
          name: "Pokemon Card",
          rarity: "Common",
          product_type_name: "Cards",
          image_url: null,
        },
        {
          product_id: "pokemon-2",
          game_id: 3,
          game: "Pokemon",
          set_name: "Shared Pokemon Set",
          set_code: "SHARED",
          name: "Pokemon Card Two",
          rarity: "Uncommon",
          product_type_name: "Cards",
          image_url: null,
        },
        {
          product_id: "magic-1",
          game_id: 1,
          game: "Magic: The Gathering",
          set_name: "Shared Magic Set",
          set_code: "SHARED",
          name: "Magic Card",
          rarity: "Common",
          product_type_name: "Cards",
          image_url: null,
        },
      ],
      [],
      [
        {
          game: "Pokemon",
          name: "Shared Pokemon Set",
          set_code: "SHARED",
          set_image_id: "pokemon-1",
          total_cards: 2,
        },
        {
          game: "Magic: The Gathering",
          name: "Shared Magic Set",
          set_code: "SHARED",
          set_image_id: "magic-1",
          total_cards: 1,
        },
      ],
    );
    const response = await app.request(
      "/api/v1/sets/search?q=shared",
      {},
      env,
    );
    const filteredSets = await app.request(
      "/api/v1/sets/search?game=Pokemon",
      {},
      env,
    );
    const filteredCards = await app.request(
      "/api/v1/cards/search?game=Pokemon",
      {},
      env,
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({
            set_code: "SHARED",
            game: "Magic: The Gathering",
            card_count: 1,
          }),
          expect.objectContaining({
            set_code: "SHARED",
            game: "Pokemon",
            card_count: 2,
            image_url:
              "https://image.tcgcard.fun/cards/pokemon-1.jpg",
          }),
        ],
        total: 2,
        page: 1,
        page_size: 20,
      },
    });
    expect(await filteredSets.json()).toEqual({
      success: true,
      data: {
        items: [
          expect.objectContaining({
            set_code: "SHARED",
            game: "Pokemon",
            card_count: 2,
          }),
        ],
        total: 1,
        page: 1,
        page_size: 20,
      },
    });
    expect(await filteredCards.json()).toMatchObject({
      success: true,
      data: {
        items: [
          { card_ref: "pokemon-1", game: "Pokemon" },
          { card_ref: "pokemon-2", game: "Pokemon" },
        ],
      },
    });
  });

  it("returns enabled games by search_sort because the database owns the Search default", async () => {
    const env = createTestEnv(
      [],
      [],
      [],
      [],
      [
        { game_id: 3, name: "Pokemon", load: 1, search_sort: 0 },
        {
          game_id: 1,
          name: "Magic: The Gathering",
          load: 1,
          search_sort: 1000,
        },
        { game_id: 9, name: "Disabled", load: 0, search_sort: -1 },
      ],
    );

    const response = await app.request("/api/v1/games", {}, env);

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        items: [
          { id: "3", name: "Pokemon" },
          { id: "1", name: "Magic: The Gathering" },
        ],
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
        image_url: "https://image.tcgcard.fun/cards/mock%3Atcg%3Acharizard-base-4.jpg",
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
        image_url: "https://image.tcgcard.fun/cards/admin%3Atcg%3Amissing-promo.jpg",
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
            image_url: "https://image.tcgcard.fun/cards/mock%3Atcg%3Acharizard-base-4.jpg",
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

  it("keeps list fallbacks but fails Trending loudly because clients must not mistake an outage for an empty ranking", async () => {
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
      data: { items: [], total: 0, page: 1, page_size: 40 },
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
    expect(trending.status).toBe(500);
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

  it("batches price series in request order because Card Detail must avoid one HTTP round trip per chart dimension", async () => {
    const routeApp = new Hono<{ Bindings: Env }>();
    routeApp.route(
      "/",
      createDataSourceRoutes({
        createAdapter: () => createMockDataSourceAdapter(),
      }),
    );
    const path = `/cards/${encodeURIComponent(
      "mock:tcg:charizard-base-4",
    )}/price-series/batch`;
    const response = await routeApp.request(
      path,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          requests: [
            { grader: "Raw", grade: null, condition: "Near Mint", days: 30 },
            { grader: "PSA", grade: 10, condition: null, days: 90 },
          ],
        }),
      },
      createTestEnv(),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(await response.json()).toEqual({
      success: true,
      data: {
        card_ref: "mock:tcg:charizard-base-4",
        results: [
          expect.objectContaining({
            grader: "Raw",
            grade: null,
            condition: "Near Mint",
            days: 30,
            series: expect.any(Array),
          }),
          expect.objectContaining({
            grader: "PSA",
            grade: 10,
            condition: null,
            days: 90,
            series: expect.any(Array),
          }),
        ],
      },
    });

    const invalid = await routeApp.request(
      path,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ requests: [] }),
      },
      createTestEnv(),
    );
    expect(invalid.status).toBe(422);
  });
});

function createTestEnv(
  cardOverrides: CardOverrideRow[] = [],
  cards: CardCatalogRow[] = [],
  trendingPins: TrendingPinRow[] = [],
  sets: SetCatalogRow[] = [],
  games: GameCatalogRow[] = [],
): Env {
  return {
    DB: new FakeD1Database(
      cardOverrides,
      cards,
      trendingPins,
      sets,
      games,
    ) as unknown as D1Database,
    CACHE_KV: new FakeKvNamespace() as unknown as KVNamespace,
    JWT_SECRET: "test-secret",
  };
}
