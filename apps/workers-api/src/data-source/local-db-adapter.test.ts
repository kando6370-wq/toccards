import { describe, expect, it } from "vitest";
import { createLocalDbDataSourceAdapter } from "./local-db-adapter";

type CardRow = {
  product_id: string;
  game_id: number;
  game: string | null;
  set_name: string | null;
  set_code: string | null;
  number: string | null;
  name: string | null;
  rarity: string | null;
  product_type_name: string | null;
  image_url: string | null;
};

type SetRow = {
  game: string;
  name: string;
  set_code: string | null;
  set_image_id: string | null;
  total_cards: number | null;
};

type SkuRow = {
  sku_id: number | null;
  product_id: string;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  price_history: string;
  increase_rate: number | null;
};

type PriceHistoryRow = Record<string, string | number | null> & {
  product_id: string;
  product_sub_type: string | null;
};

class FakeCardDatabase {
  constructor(
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly sets: SetRow[] = [],
    private readonly hasNumberColumn = true,
    private readonly priceHistories: PriceHistoryRow[] = [],
  ) {}

  readonly preparedSql: string[] = [];

  prepare(sql: string): FakeStatement {
    this.preparedSql.push(sql);
    if (!this.hasNumberColumn && sql.includes("coalesce(number")) {
      throw new Error("no such column: number");
    }
    return new FakeStatement(
      sql,
      this.cards,
      this.skus,
      this.sets,
      this.priceHistories,
    );
  }
}

class FakeStatement {
  constructor(
    private readonly sql: string,
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly sets: SetRow[],
    private readonly priceHistories: PriceHistoryRow[],
  ) {}

  bind(...values: unknown[]): FakeBoundStatement {
    return new FakeBoundStatement(
      this.sql,
      this.cards,
      this.skus,
      this.sets,
      this.priceHistories,
      values,
    );
  }

  all<T>(): Promise<{ results: T[] }> {
    return new FakeBoundStatement(
      this.sql,
      this.cards,
      this.skus,
      this.sets,
      this.priceHistories,
      [],
    ).all<T>();
  }
}

class FakeBoundStatement {
  constructor(
    private readonly sql: string,
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly sets: SetRow[],
    private readonly priceHistories: PriceHistoryRow[],
    private readonly values: unknown[],
  ) {}

  async all<T>(): Promise<{ results: T[] }> {
    if (
      this.sql.includes("price_Grade_7") ||
      this.sql.includes("variant_name AS product_sub_type")
    ) {
      const productId = String(this.values[0]);
      return {
        results: this.priceHistories.filter(
          (row) => row.product_id === productId,
        ) as T[],
      };
    }
    if (this.sql.includes("FROM tcg_price AS sku")) {
      const highestSkuByProduct = new Map<string, SkuRow>();
      for (const sku of this.skus.filter(
        (row) => row.increase_rate !== null && row.increase_rate > 0,
      )) {
        const productId = String(sku.product_id);
        const current = highestSkuByProduct.get(productId);
        if (
          !current ||
          sku.increase_rate! > current.increase_rate! ||
          (sku.increase_rate === current.increase_rate && naturalKey(sku) < naturalKey(current))
        ) {
          highestSkuByProduct.set(productId, sku);
        }
      }
      const results = [...highestSkuByProduct.values()]
        .sort(
          (left, right) =>
            right.increase_rate! - left.increase_rate! || naturalKey(left).localeCompare(naturalKey(right)),
        )
        .slice(0, 10)
        .flatMap((sku) => {
          const card = this.cards.find(
            (candidate) => candidate.product_id === String(sku.product_id),
          );
          return card ? [{ ...card, ...sku, product_id: card.product_id }] : [];
        });
      return { results: results as T[] };
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

    if (this.sql.includes("FROM cards_all") && this.sql.includes("LIKE")) {
      const queryCount = this.sql.split(") LIKE ?").length - 1;
      const queries = this.values
        .slice(0, queryCount)
        .map((value) => String(value).replaceAll("%", "").toLowerCase());
      const hasGameFilter = this.sql.includes("lower(game) = lower(?)");
      const hasSetFilter = this.sql.includes("lower(set_code) = lower(?)");
      const game = hasGameFilter
        ? String(this.values[queryCount]).toLowerCase()
        : null;
      const setCode = hasSetFilter
        ? String(this.values[queryCount + Number(hasGameFilter)]).toLowerCase()
        : null;
      const objectType = objectTypeFilterFromSql(this.sql);
      const filterCount = Number(hasGameFilter) + Number(hasSetFilter);
      const limit = Number(this.values[queryCount + filterCount]);
      const offset = Number(this.values[queryCount + filterCount + 1]);
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
              .includes(queries[0] ?? "") ||
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
          queries.every((query) =>
            `${card.name ?? ""} ${card.number ?? ""} ${card.set_name ?? ""} ${card.set_code ?? ""} ${card.rarity ?? ""} ${card.game ?? ""}`
              .toLowerCase()
              .includes(query),
          ),
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

    if (this.sql.includes("FROM tcg_price")) {
      const productIds = new Set(this.values.map(String));
      return {
        results: this.skus.filter((sku) =>
          productIds.has(String(sku.product_id)),
        ).map((sku) => ({ ...sku, product_id: String(sku.product_id) })) as T[],
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
          card({ product_id: "100", name: "Charizard", number: "4/102", product_type_name: "Cards" }),
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
        card_number: "4/102",
        finish: null,
        language: null,
        object_type: "tcg",
        image_url: null,
        rarity: "Rare Holo",
      },
    ]);
  });

  it("loads a card number by id because scan disambiguation compares exact printings", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Leafeon ex", number: "200/187" })],
        [],
      ) as unknown as D1Database,
    );

    await expect(adapter.getCard("100")).resolves.toMatchObject({
      card_ref: "100",
      card_number: "200/187",
    });
  });

  it("returns only the card's distinct SKU qualifiers because collection editing must not offer nonexistent variants", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Leafeon ex" })],
        [
          sku({ sku_id: 1, language_name: "Japanese", variant_name: "Normal" }),
          sku({ sku_id: 2, language_name: "English", variant_name: "Holofoil" }),
          sku({ sku_id: 3, language_name: "English", variant_name: "Holofoil" }),
          sku({
            sku_id: 4,
            language_name: null,
            language_code: "FR",
            variant_name: null,
            variant_code: "Foil",
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getCard("100")).resolves.toMatchObject({
      available_languages: ["English", "FR", "Japanese"],
      available_finishes: ["Holofoil", "Normal"],
    });
  });

  it("parses tcg_price price_Ungraded with JSON because price strings must become numeric market data", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            product_id: "100",
            condition_name: "Near Mint",
            increase_rate: 8.97,
            price_history: JSON.stringify([
              { price: "12.50", date: "2026-07-01" },
              { price: "15.75", date: "2026-07-08" },
            ]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getMarketPrices("100")).resolves.toEqual([
      {
        grader: "Raw",
        grade: null,
        condition: "Near Mint",
        price: 15.75,
        increase_percent: 8.97,
      },
    ]);
    await expect(adapter.searchCards("Charizard")).resolves.toEqual([
      expect.objectContaining({
        card_ref: "100",
        price_usd: 15.75,
        price_change_1d_percent: 8.97,
      }),
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

  it("adds only real graded history while raw pricing stays on tcg_price.price_Ungraded", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            product_id: "100",
            price_history: JSON.stringify([
              { price: "12.50", date: "2026-07-29" },
              { price: "15.75", date: "2026-07-30" },
            ]),
          }),
        ],
        [],
        true,
        [gradedPriceHistory()],
      ) as unknown as D1Database,
    );

    const prices = await adapter.getMarketPrices("100");

    expect(prices[0]).toMatchObject({ grader: "Raw", price: 15.75 });
    expect(prices).toContainEqual(
      expect.objectContaining({
        grader: "PSA",
        grade: 10,
        grade_label: "10",
        price: 360,
        product_sub_type: "Foil",
        increase_percent: 20,
      }),
    );
    expect(prices.some((price) => price.grader === "ACE")).toBe(false);
    expect(prices.some((price) => price.price === 9999)).toBe(false);
  });

  it("searches by card name and number together because collectors use the number to identify an exact printing", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [
          card({ product_id: "100", name: "Vaporeon", number: "022/131" }),
          card({ product_id: "200", name: "Vaporeon", number: "030/131" }),
        ],
        [],
      ) as unknown as D1Database,
    );

    const cards = await adapter.searchCards("VAPOREON 022/131");

    expect(cards.map((card) => card.card_ref)).toEqual(["100"]);
  });

  it("matches every search term across card fields because abbreviated queries need not be one literal phrase", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [
          card({
            product_id: "100",
            name: "Charizard ex",
            set_name: "Mega Evolution",
          }),
          card({ product_id: "200", name: "Charizard ex", set_name: "Base Set" }),
        ],
        [],
      ) as unknown as D1Database,
    );

    const cards = await adapter.searchCards("  MEGA   ch  ");

    expect(cards.map((card) => card.card_ref)).toEqual(["100"]);
  });

  it("keeps name search working without the optional number column because older local catalogs must remain usable", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Vaporeon" })],
        [],
        [],
        false,
      ) as unknown as D1Database,
    );

    await expect(adapter.searchCards("vaporeon")).resolves.toMatchObject([
      { card_ref: "100", name: "Vaporeon" },
    ]);
  });

  it("prefers the freshest same-specification row because a provider refresh must replace stale imported prices", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            sku_id: 1,
            product_id: "100",
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-08" },
            ]),
          }),
          sku({
            sku_id: 2,
            product_id: "100",
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
            set_image_id: "100",
            total_cards: 2,
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
            sku_id: null,
            variant_code: "F",
            variant_name: "Foil",
            increase_rate: 3186.713286713287,
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
        finish: "Foil",
        language: "English",
        price_usd: 15.75,
        previous_30d_price_usd: 12.5,
        price_change_1d_percent: 3186.713286713287,
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

  it("filters raw prices by finish because switching material must not mix Normal and Foil histories", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "180865" })],
        [
          sku({ product_id: "180865", variant_name: "Normal", price_history: JSON.stringify([{ price: 12, date: "2026-07-30" }]) }),
          sku({ product_id: "180865", sku_id: 2, variant_code: "F", variant_name: "Foil", price_history: JSON.stringify([{ price: 24, date: "2026-07-30" }]) }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getMarketPrices("180865", "Foil")).resolves.toEqual([
      { grader: "Raw", grade: null, condition: "Near Mint", price: 24 },
    ]);
    await expect(
      adapter.getPriceSeries("180865", "Raw", null, "Near Mint", 30, "Normal"),
    ).resolves.toEqual([{ date: "2026-07-30", price: 12 }]);
  });

  it("filters current prices by language because the collection editor must not display another language variant", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "180865" })],
        [
          sku({
            product_id: "180865",
            language_code: "EN",
            language_name: "English",
            price_history: JSON.stringify([{ price: 12, date: "2026-07-30" }]),
          }),
          sku({
            product_id: "180865",
            sku_id: 2,
            language_code: "JP",
            language_name: "Japanese",
            price_history: JSON.stringify([{ price: 22, date: "2026-07-30" }]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(
      adapter.getMarketPrices("180865", "Normal", "Japanese"),
    ).resolves.toEqual([
      { grader: "Raw", grade: null, condition: "Near Mint", price: 22 },
    ]);
  });

  it("falls back to Ungraded for the same product subtype only when that finish has no SKU history", async () => {
    const normalHistory = {
      ...gradedPriceHistory(),
      product_id: "180865",
      product_sub_type: "Normal",
      price_Ungraded: JSON.stringify([{ price: 30, date: "2026-07-30" }]),
      increase_Ungraded: 5,
      price_PSA_10: "[]",
    };
    const foilHistory = {
      ...gradedPriceHistory(),
      product_id: "180865",
      price_Ungraded: JSON.stringify([{ price: 60, date: "2026-07-30" }]),
    };
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "180865" })],
        [sku({ product_id: "180865", price_history: "[]" })],
        [],
        true,
        [normalHistory, foilHistory],
      ) as unknown as D1Database,
    );

    await expect(adapter.getMarketPrices("180865", "Normal")).resolves.toMatchObject([
      { grader: "Raw", condition: "Ungraded", price: 30, product_sub_type: "Normal", increase_percent: 5 },
    ]);
    await expect(
      adapter.getPriceSeries("180865", "Raw", null, "Ungraded", 30, "Normal"),
    ).resolves.toEqual([{ date: "2026-07-30", price: 30 }]);
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
            sku_id: 3,
            condition_code: "LP",
            condition_name: "Lightly Played",
            language_name: "English",
            variant_name: "Normal",
            price_history: JSON.stringify([
              { price: 11, date: "2026-07-01" },
              { price: 12, date: "2026-07-10" },
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
        date: "2026-07-10",
        title: "Charizard / Lightly Played / English / Normal",
        price: 12,
        platform: "TCGplayer",
        url: "https://www.tcgplayer.com/product/100",
      },
      {
        date: "2026-07-08",
        title: "Charizard / Near Mint / English / Normal",
        price: 15.75,
        platform: "TCGplayer",
        url: "https://www.tcgplayer.com/product/100",
      },
    ]);
  });

  it("ranks only positive Trending Today cards by stored increase_Ungraded because Home and View all share that daily metric", async () => {
    const db = new FakeCardDatabase(
        [
          card({ product_id: "100", name: "Small Mover" }),
          card({ product_id: "200", name: "Largest Mover" }),
          card({ product_id: "300", name: "Missing Increase" }),
          card({ product_id: "400", name: "Falling Card" }),
        ],
        [
          sku({
            product_id: "100",
            increase_rate: 5,
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-14" },
              { price: 11, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 2,
            product_id: "200",
            increase_rate: 40,
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-12" },
              { price: 15, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 3,
            product_id: "200",
            variant_code: "F",
            variant_name: "Foil",
            increase_rate: 60,
            price_history: JSON.stringify([
              { price: 20, date: "2026-07-14" },
              { price: 25, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: null,
            product_id: "200",
            variant_code: "CF",
            variant_name: "Cold Foil",
            increase_rate: 80,
            price_history: JSON.stringify([
              { price: 30, date: "2026-07-14" },
              { price: 54, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 4,
            product_id: "300",
            increase_rate: null,
            price_history: JSON.stringify([
              { price: 7, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 5,
            product_id: "400",
            increase_rate: -20,
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-14" },
              { price: 8, date: "2026-07-15" },
            ]),
          }),
        ],
    );
    const adapter = createLocalDbDataSourceAdapter(
      db as unknown as D1Database,
    );

    await expect(adapter.getTrending()).resolves.toMatchObject([
      {
        card_ref: "200",
        name: "Largest Mover",
        finish: "Cold Foil",
        price_usd: 54,
        previous_30d_price_usd: 30,
        price_change_1d_percent: 80,
      },
      {
        card_ref: "100",
        name: "Small Mover",
        price_usd: 11,
        previous_30d_price_usd: 10,
        price_change_1d_percent: 5,
      },
    ]);
    const trendingSql = db.preparedSql.find((sql) =>
      sql.includes("FROM tcg_price AS sku"),
    );
    expect(trendingSql).toContain("NOT EXISTS");
    expect(trendingSql).toContain(
      "cards_all.product_id = sku.product_id",
    );
    expect(trendingSql).not.toContain("sku_id IS NOT NULL");
    expect(trendingSql).not.toContain("pricecharting_id");
    expect(
      db.preparedSql.every((sql) => !/sku_id|pricecharting_id/i.test(sql)),
    ).toBe(true);
    expect(trendingSql).toContain("idx_tcg_price_increase_ungraded");
    expect(trendingSql).toContain("sku.increase_Ungraded > 0");
    expect(trendingSql).not.toContain("CAST(");
  });
});

function card(overrides: Partial<CardRow>): CardRow {
  return {
    product_id: "100",
    game_id: 3,
    game: "Pokemon",
    set_name: "Base Set",
    set_code: "BS",
    number: null,
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
    product_id: "100",
    condition_code: "NM",
    condition_name: "Near Mint",
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    price_history: "[]",
    increase_rate: null,
    ...overrides,
  };
}

function naturalKey(row: SkuRow): string {
  return [row.condition_name, row.language_name, row.variant_name]
    .map((value) => (value ?? "").trim().toLowerCase())
    .join("\u0000");
}

function gradedPriceHistory(): PriceHistoryRow {
  return {
    product_id: "100",
    product_sub_type: "Foil",
    price_Ungraded: JSON.stringify([
      { price: "9999", date: "2026-07-30" },
    ]),
    increase_Ungraded: 999,
    price_Grade_7: "[]",
    price_Grade_8: "[]",
    price_Grade_9: "[]",
    price_Grade_9_5: "[]",
    price_PSA_10: JSON.stringify([
      { price: "360", date: "2026-07-30" },
      { price: "300", date: "2026-07-29" },
    ]),
    price_BGS_10: "[]",
    price_CGC_10: "[]",
    price_SGC_10: "[]",
    increase_Grade_7: 0,
    increase_Grade_8: 0,
    increase_Grade_9: 0,
    increase_Grade_9_5: 0,
    increase_PSA_10: 20,
    increase_BGS_10: 0,
    increase_CGC_10: 0,
    increase_SGC_10: 0,
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
