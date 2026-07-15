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
  ) {}

  prepare(sql: string): FakeStatement {
    return new FakeStatement(sql, this.cards, this.skus);
  }
}

class FakeStatement {
  constructor(
    private readonly sql: string,
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
  ) {}

  bind(...values: unknown[]): FakeBoundStatement {
    return new FakeBoundStatement(this.sql, this.cards, this.skus, values);
  }

  all<T>(): Promise<{ results: T[] }> {
    return new FakeBoundStatement(this.sql, this.cards, this.skus, []).all<T>();
  }
}

class FakeBoundStatement {
  constructor(
    private readonly sql: string,
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly values: unknown[],
  ) {}

  async all<T>(): Promise<{ results: T[] }> {
    if (this.sql.includes("FROM cards_all") && this.sql.includes("LIKE")) {
      const query = String(this.values[0]).replaceAll("%", "").toLowerCase();
      const objectType = objectTypeFilterFromSql(this.sql);
      const limit = Number(this.values[1]);
      const offset = Number(this.values[2]);
      const results = this.cards
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

  it("ranks trending cards from recent price history because Home must not depend on mock or manually pinned data", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [
          card({ product_id: "100", name: "Small Mover" }),
          card({ product_id: "200", name: "Large Mover" }),
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
              { price: 10, date: "2026-07-14" },
              { price: 15, date: "2026-07-15" },
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
      },
      {
        card_ref: "100",
        name: "Small Mover",
        price_usd: 11,
        previous_30d_price_usd: 10,
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
