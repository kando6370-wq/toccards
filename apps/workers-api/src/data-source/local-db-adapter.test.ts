import { describe, expect, it } from "vitest";
import { createLocalDbDataSourceAdapter } from "./local-db-adapter";

type CardRow = {
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

type SetRow = {
  game: string;
  name: string;
  set_code: string | null;
  product_id: string | null;
  total_cards: number | null;
  release_date: string | null;
};

type SkuRow = {
  sku_id: number;
  product_id: number;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  price_history: string;
};

class FakeCardDatabase {
  constructor(
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly sets: SetRow[] = [],
  ) {}

  prepare(sql: string): FakeStatement {
    return new FakeStatement(sql, this.cards, this.skus, this.sets);
  }
}

class FakeStatement {
  constructor(
    private readonly sql: string,
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly sets: SetRow[],
  ) {}

  bind(...values: unknown[]): FakeBoundStatement {
    return new FakeBoundStatement(this.sql, this.cards, this.skus, this.sets, values);
  }

  all<T>(): Promise<{ results: T[] }> {
    return new FakeBoundStatement(this.sql, this.cards, this.skus, this.sets, []).all<T>();
  }
}

class FakeBoundStatement {
  constructor(
    private readonly sql: string,
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly sets: SetRow[],
    private readonly values: unknown[],
  ) {}

  async all<T>(): Promise<{ results: T[] }> {
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
        .sort((left, right) =>
          (right.release_date ?? "").localeCompare(left.release_date ?? ""),
        )
        .slice(offset, offset + limit)
        .map((set) => ({
          set_code: set.set_code,
          set_name: set.name,
          game: set.game,
          image_url: null,
          image_card_ref: set.product_id?.trim() || null,
          card_count: set.total_cards ?? 0,
        }));
      return { results: results as T[] };
    }

    if (this.sql.includes("FROM cards_all") && this.sql.includes("LIKE")) {
      const query = String(this.values[0]).replaceAll("%", "").toLowerCase();
      const hasGameFilter = this.sql.includes("lower(game) = lower(?)");
      const hasSetFilter = this.sql.includes("lower(set_code) = lower(?)");
      const game = hasGameFilter ? String(this.values[1]).toLowerCase() : null;
      const setCode = hasSetFilter
        ? String(this.values[hasGameFilter ? 2 : 1]).toLowerCase()
        : null;
      const objectType = objectTypeFilterFromSql(this.sql);
      const filterCount = Number(hasGameFilter) + Number(hasSetFilter);
      const limit = Number(this.values[1 + filterCount]);
      const offset = Number(this.values[2 + filterCount]);
      const gameCards = this.cards.filter(
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
        return {
          results: [...sets.values()].slice(offset, offset + limit) as T[],
        };
      }

      const results = gameCards
        .filter((card) =>
          [card.name, card.set_name, card.set_code, card.rarity, card.game]
            .filter(Boolean)
            .some((value) => value!.toLowerCase().includes(query)),
        )
        .filter((card) => {
          return objectType === null || objectTypeFromProductType(card.product_type_name) === objectType;
        })
        .slice(offset, offset + limit);

      return { results: results as T[] };
    }

    if (this.sql.includes("FROM cards_all")) {
      return { results: this.cards as T[] };
    }

    if (this.sql.includes("FROM tcgplayer_skus")) {
      const productIds = new Set(this.values.map(Number));
      return {
        results: this.skus.filter((sku) =>
          productIds.has(sku.product_id),
        ) as T[],
      };
    }

    return { results: [] };
  }

  async first<T>(): Promise<T | null> {
    if (this.sql.includes("FROM cards_all")) {
      const cardRef = String(this.values[0]);
      return (this.cards.find((card) => card.product_id === cardRef) ?? null) as T | null;
    }

    return null;
  }
}

describe("local D1 card data source adapter", () => {
  it("maps cards_all rows into the provider-independent card contract because current D1 is the card catalog source", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [
          card({ product_id: "100", name: "Charizard", product_type_name: "Cards" }),
          card({ product_id: "200", name: "Charizard Booster Box", product_type_name: "Booster Box" }),
        ],
        [],
      ) as unknown as D1Database,
    );

    const cards = await adapter.searchCards("charizard", {
      object_type: "tcg",
      page: 1,
      page_size: 10,
    });

    expect(cards).toEqual([
      {
        card_ref: "100",
        name: "Charizard",
        game: "Pokemon",
        set_name: "Base Set",
        set_code: "BS",
        card_number: "",
        finish: null,
        language: null,
        object_type: "tcg",
        image_url: "https://img.example/100.jpg",
        rarity: "Rare Holo",
      },
    ]);
  });

  it("parses tcgplayer_skus price_history with JSON because price strings must become numeric market data", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            product_id: 100,
            condition_name: "Near Mint",
            price_history: JSON.stringify([
              { price: "12.50", date: "2026-07-01" },
              { price: "15.75", date: "2026-07-08" },
            ]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getMarketPrices("100")).resolves.toEqual([
      { grader: "Raw", grade: null, condition: "Near Mint", price: 15.75 },
    ]);
    await expect(
      adapter.getPriceSeries("100", "Raw", null, "Near Mint", 30),
    ).resolves.toEqual([
      { date: "2026-07-01", price: 12.5 },
      { date: "2026-07-08", price: 15.75 },
    ]);
    await expect(
      adapter.getPriceSeries("100", "Raw", null, "Near Mint", 1),
    ).resolves.toEqual([
      { date: "2026-07-01", price: 12.5 },
      { date: "2026-07-08", price: 15.75 },
    ]);
  });

  it("prefers the freshest same-specification row because a provider refresh must replace stale imported prices", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            sku_id: 1,
            product_id: 100,
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-08" },
            ]),
          }),
          sku({
            sku_id: 2,
            product_id: 100,
            price_history: JSON.stringify([
              { price: 12, date: "2026-07-16" },
              { price: 13, date: "2026-07-17" },
            ]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getMarketPrices("100")).resolves.toEqual([
      { grader: "Raw", grade: null, condition: "Near Mint", price: 13 },
    ]);
    await expect(
      adapter.getPriceSeries("100", "Raw", null, "Near Mint", 30),
    ).resolves.toEqual([
      { date: "2026-07-16", price: 12 },
      { date: "2026-07-17", price: 13 },
    ]);
  });

  it("filters by game before paging and counts the complete set because Search Game controls both tabs", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [
          card({ product_id: "100", name: "Pokemon One" }),
          card({ product_id: "101", name: "Pokemon Two" }),
          card({
            product_id: "200",
            game_id: 1,
            game: "Magic: The Gathering",
            name: "Magic One",
          }),
        ],
        [],
        [
          {
            game: "Pokemon",
            name: "Base Set",
            set_code: "BS",
            product_id: "100",
            total_cards: 2,
            release_date: "1999-01-09",
          },
        ],
      ) as unknown as D1Database,
    );

    await expect(
      adapter.searchCards("one", { game: "Pokemon", page_size: 1 }),
    ).resolves.toMatchObject([{ card_ref: "100", game: "Pokemon" }]);
    await expect(
      adapter.searchSets("base", { game: "Pokemon", page_size: 1 }),
    ).resolves.toEqual([
      {
        set_code: "BS",
        set_name: "Base Set",
        game: "Pokemon",
        image_url: null,
        image_card_ref: "100",
        card_count: 2,
      },
    ]);
    await expect(
      adapter.searchCards("", {
        game: "Pokemon",
        set_code: "BS",
        page_size: 10,
      }),
    ).resolves.toHaveLength(2);
  });

  it("adds the preferred SKU price to search results because Search must show real market reference data without per-card HTTP requests", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            sku_id: 1,
            variant_code: "F",
            variant_name: "Foil",
            price_history: JSON.stringify([
              { price: "12.50", date: "2026-06-01" },
              { price: "15.75", date: "2026-07-08" },
            ]),
          }),
          sku({
            sku_id: 2,
            variant_code: "N",
            variant_name: "Normal",
            price_history: JSON.stringify([
              { price: "9.25", date: "2026-06-01" },
              { price: "10.50", date: "2026-07-08" },
            ]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.searchCards("charizard")).resolves.toMatchObject([
      {
        card_ref: "100",
        finish: "Normal",
        language: "English",
        price_usd: 10.5,
        previous_30d_price_usd: 9.25,
      },
    ]);
  });

  it("uses one preferred SKU per condition because chart series must not interleave languages and finishes", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            sku_id: 1,
            variant_code: "F",
            variant_name: "Foil",
            price_history: JSON.stringify([
              { price: 20, date: "2026-07-01" },
              { price: 22, date: "2026-07-08" },
            ]),
          }),
          sku({
            sku_id: 2,
            variant_code: "N",
            variant_name: "Normal",
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-01" },
              { price: 12, date: "2026-07-08" },
            ]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getMarketPrices("100")).resolves.toEqual([
      { grader: "Raw", grade: null, condition: "Near Mint", price: 12 },
    ]);
    await expect(
      adapter.getPriceSeries("100", "Raw", null, "Near Mint", 30),
    ).resolves.toEqual([
      { date: "2026-07-01", price: 10 },
      { date: "2026-07-08", price: 12 },
    ]);
  });

  it("builds Shop rows from real SKU history because Card Detail must not rely on mock marketplace data", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            condition_name: "Near Mint",
            language_name: "English",
            variant_name: "Normal",
            price_history: JSON.stringify([
              { price: 12.5, date: "2026-07-01" },
              { price: 15.75, date: "2026-07-08" },
            ]),
          }),
          sku({
            sku_id: 2,
            variant_name: "Foil",
            price_history: "[]",
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getSoldListings("100")).resolves.toEqual([
      {
        date: "2026-07-08",
        title: "Charizard / Near Mint / English / Normal",
        price: 15.75,
        platform: "TCGplayer",
        url: "https://www.tcgplayer.com/product/100",
      },
    ]);
  });

  it("ranks Trending Today by the preferred SKU 1D change because Home must show the same price it ranked", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [
          card({ product_id: "100", name: "Small Mover" }),
          card({ product_id: "200", name: "Large Mover" }),
          card({ product_id: "300", name: "Falling Card" }),
          card({ product_id: "400", name: "Missing Baseline" }),
        ],
        [
          sku({
            product_id: 100,
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-14" },
              { price: 11, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 2,
            product_id: 200,
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-12" },
              { price: 15, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 3,
            product_id: 300,
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-14" },
              { price: 8, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 4,
            product_id: 400,
            price_history: JSON.stringify([
              { price: 7, date: "2026-07-15" },
            ]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getTrending()).resolves.toMatchObject([
      {
        card_ref: "200",
        name: "Large Mover",
        price_usd: 15,
        previous_30d_price_usd: 10,
        previous_1d_price_usd: 10,
        price_change_1d_percent: 50,
        price_as_of: "2026-07-15",
        previous_price_as_of: "2026-07-12",
      },
      {
        card_ref: "100",
        name: "Small Mover",
        price_usd: 11,
        previous_30d_price_usd: 10,
        previous_1d_price_usd: 10,
        price_change_1d_percent: 10,
      },
      {
        card_ref: "300",
        name: "Falling Card",
        price_change_1d_percent: -20,
      },
      {
        card_ref: "400",
        name: "Missing Baseline",
      },
    ]);
  });
});

function card(overrides: Partial<CardRow>): CardRow {
  return {
    product_id: "100",
    game_id: 3,
    game: "Pokemon",
    set_name: "Base Set",
    set_code: "BS",
    name: "Charizard",
    rarity: "Rare Holo",
    product_type_name: "Cards",
    image_url: "https://img.example/100.jpg",
    ...overrides,
  };
}

function sku(overrides: Partial<SkuRow>): SkuRow {
  return {
    sku_id: 1,
    product_id: 100,
    condition_code: "NM",
    condition_name: "Near Mint",
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    price_history: "[]",
    ...overrides,
  };
}

function objectTypeFromProductType(productType: string | null): string {
  return productType === "Cards" ? "tcg" : "sealed";
}

function objectTypeFilterFromSql(sql: string): string | null {
  if (sql.includes("product_type_name = 'Cards'")) {
    return "tcg";
  }

  if (sql.includes("product_type_name <> 'Cards'")) {
    return "sealed";
  }

  if (sql.includes("product_type_name IS NULL")) {
    return "other";
  }

  return null;
}
