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
  set_id?: string;
  game: string;
  name: string;
  set_code: string | null;
  set_image_id: string | null;
  total_cards: number | null;
};

type SkuRow = {
  sku_id: number | null;
  series_id: number;
  source_code: string;
  source_record_id: string;
  metric_code: string;
  product_id: string;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  grader_code: string;
  grade_min_x10: number | null;
  grade_max_x10: number | null;
  observed_on: string;
  amount_micros: number;
  baseline_1d_on: string | null;
  baseline_1d_amount_micros: number | null;
  baseline_7d_on: string | null;
  baseline_7d_amount_micros: number | null;
  baseline_30d_on: string | null;
  baseline_30d_amount_micros: number | null;
  price_history: string;
  change_1d_percent: number | null;
  change_7d_percent: number | null;
  change_30d_percent: number | null;
};

class FakeCardDatabase {
  constructor(
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly sets: SetRow[] = [],
    private readonly hasNumberColumn = true,
  ) {}

  readonly preparedSql: string[] = [];
  readonly boundCalls: Array<{ sql: string; values: unknown[] }> = [];

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
      this.boundCalls,
    );
  }
}

class FakeStatement {
  constructor(
    private readonly sql: string,
    private readonly cards: CardRow[],
    private readonly skus: SkuRow[],
    private readonly sets: SetRow[],
    private readonly boundCalls: Array<{ sql: string; values: unknown[] }>,
  ) {}

  bind(...values: unknown[]): FakeBoundStatement {
    this.boundCalls.push({ sql: this.sql, values });
    return new FakeBoundStatement(
      this.sql,
      this.cards,
      this.skus,
      this.sets,
      values,
    );
  }

  all<T>(): Promise<{ results: T[] }> {
    return new FakeBoundStatement(
      this.sql,
      this.cards,
      this.skus,
      this.sets,
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
    private readonly values: unknown[],
  ) {}

  async all<T>(): Promise<{ results: T[] }> {
    if (this.sql.includes("FROM price_history_month AS history")) {
      const seriesIds = new Set(this.values.filter((value): value is number =>
        typeof value === "number"
      ));
      return {
        results: this.skus.filter((row) => seriesIds.has(row.series_id)).map((row) => ({
          series_id: row.series_id,
          points_json: row.price_history,
        })) as T[],
      };
    }
    if (
      this.sql.includes("FROM current_price_pointer AS pointer")
      && this.sql.includes("JOIN card_trending_snapshot AS trend")
    ) {
      const highestSkuByProduct = new Map<string, SkuRow>();
      for (const sku of this.skus.filter(
        (row) => row.change_1d_percent !== null && row.change_1d_percent > 0,
      )) {
        const productId = String(sku.product_id);
        const current = highestSkuByProduct.get(productId);
        if (
          !current ||
          sku.change_1d_percent! > current.change_1d_percent! ||
          (sku.change_1d_percent === current.change_1d_percent
            && naturalKey(sku) < naturalKey(current))
        ) {
          highestSkuByProduct.set(productId, sku);
        }
      }
      const limit = Number(this.values[0] ?? 10);
      const offset = Number(this.values[1] ?? 0);
      const results = [...highestSkuByProduct.values()]
        .sort(
          (left, right) =>
            right.change_1d_percent! - left.change_1d_percent!
            || naturalKey(left).localeCompare(naturalKey(right)),
        )
        .slice(offset, offset + limit)
        .flatMap((sku) => {
          const card = this.cards.find(
            (candidate) => candidate.product_id === String(sku.product_id),
          );
          return card ? [{ ...card, ...sku, rank: 1, product_id: card.product_id }] : [];
        });
      return { results: results as T[] };
    }

    if (this.sql.includes("FROM price_series AS series")) {
      const productIds = new Set(this.values.map(String));
      return {
        results: this.skus.filter((sku) => productIds.has(sku.product_id)) as T[],
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
          set_id: set.set_id ?? set.set_code ?? "",
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

describe("PostgreSQL card data source adapter", () => {
  it("maps cards_all rows into the provider-independent card contract because PostgreSQL is the catalog source", async () => {
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

  it("loads a card number by id because Card Detail and Review preserve exact printing identity", async () => {
    const db = new FakeCardDatabase(
      [card({ product_id: "100", name: "Leafeon ex", number: "200/187" })],
      [],
    );
    const adapter = createLocalDbDataSourceAdapter(db as unknown as D1Database);

    await expect(adapter.getCard("100")).resolves.toMatchObject({
      card_ref: "100",
      card_number: "200/187",
    });
    expect(db.preparedSql.filter((sql) => sql.includes("FROM cards_all"))).toHaveLength(1);
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

  it("keeps Search on the canonical Near Mint price because a larger gain from another condition must not relabel the visible market variant", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "664010", name: "Oricorio ex - 024" })],
        [
          sku({
            series_id: 1,
            product_id: "664010",
            condition_code: "NM",
            condition_name: "Near Mint",
            amount_micros: 11_350_000,
            baseline_30d_on: "2026-07-24",
            baseline_30d_amount_micros: 11_180_000,
            change_30d_percent: 1.520572,
          }),
          sku({
            series_id: 2,
            product_id: "664010",
            condition_code: "MP",
            condition_name: "Moderately Played",
            amount_micros: 11_580_000,
            baseline_30d_on: "2026-07-24",
            baseline_30d_amount_micros: 11_310_000,
            change_30d_percent: 2.387268,
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.searchCards("Oricorio ex")).resolves.toEqual([
      expect.objectContaining({
        card_ref: "664010",
        language: "English",
        finish: "Normal",
        price_usd: 11.35,
        previous_30d_price_usd: 11.18,
        price_change_30d_percent: 1.520572,
      }),
    ]);
  });

  it("uses each PostgreSQL change window because Search is 30D while Market Prices is 7D", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            product_id: "100",
            condition_name: "Near Mint",
            baseline_7d_on: "2026-07-01",
            baseline_7d_amount_micros: 12_500_000,
            change_1d_percent: 1.25,
            change_7d_percent: 7.5,
            change_30d_percent: 30.75,
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
        previous_7d_price_usd: 12.5,
        increase_percent: 7.5,
      },
    ]);
    await expect(adapter.searchCards("Charizard")).resolves.toEqual([
      expect.objectContaining({
        card_ref: "100",
        price_usd: 15.75,
        price_change_1d_percent: 1.25,
        price_change_30d_percent: 30.75,
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

  it("omits a missing graded 7D change because an unknown baseline must not look like 0%", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [gradedPrice({
          baseline_7d_on: null,
          baseline_7d_amount_micros: null,
          change_7d_percent: null,
        })],
      ) as unknown as D1Database,
    );

    const [price] = await adapter.getMarketPrices("100");

    expect(price).not.toHaveProperty("previous_7d_price_usd");
    expect(price).not.toHaveProperty("increase_percent");
  });

  it("returns normalized graded series without exposing unrelated raw series as a grade", async () => {
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
          gradedPrice({
            baseline_7d_on: "2026-07-23",
            baseline_7d_amount_micros: 300_000_000,
            change_7d_percent: 20,
          }),
        ],
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
        previous_7d_price_usd: 300,
        product_sub_type: "Foil",
        increase_percent: 20,
      }),
    );
    expect(prices.some((price) => price.grader === "ACE")).toBe(false);
    expect(prices.some((price) => price.price === 9999)).toBe(false);
  });

  it("normalizes PostgreSQL GENERIC grades because collection clients use the existing Grade API bucket", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [gradedPrice({
          product_id: "100",
          metric_code: "generic_90",
          variant_code: "N",
          variant_name: "Normal",
          grader_code: "GENERIC",
          grade_min_x10: 90,
          grade_max_x10: 90,
          price_history: JSON.stringify([
            { price: 40, date: "2026-07-29" },
            { price: 42, date: "2026-07-30" },
          ]),
        })],
      ) as unknown as D1Database,
    );

    await expect(adapter.getMarketPrices("100", "Normal", "English"))
      .resolves.toContainEqual(expect.objectContaining({
        grader: "Grade",
        grade: 9,
        grade_label: "9",
        price: 42,
      }));
    await expect(
      adapter.getPriceSeries("100", "Grade", 9, null, 30, "Normal"),
    ).resolves.toEqual([
      { date: "2026-07-29", price: 40 },
      { date: "2026-07-30", price: 42 },
    ]);
  });

  it("loads the requested graded series because Card Detail sends Raw and Graded ranges through one batch", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            product_id: "100",
            variant_name: "Foil",
            price_history: JSON.stringify([{ price: 15.75, date: "2026-07-30" }]),
          }),
          gradedPrice({
            product_id: "100",
            grade_min_x10: 95,
            grade_max_x10: 100,
            price_history: JSON.stringify([
              { price: 340, date: "2026-07-29" },
              { price: 360, date: "2026-07-30" },
            ]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getPriceSeriesBatch!("100", [
      { grader: "Raw", grade: null, condition: "Near Mint", days: 30, finish: "Foil" },
      { grader: "PSA", grade: 10, condition: null, days: 365, finish: "Foil" },
    ])).resolves.toEqual([
      [{ date: "2026-07-30", price: 15.75 }],
      [
        { date: "2026-07-29", price: 340 },
        { date: "2026-07-30", price: 360 },
      ],
    ]);
  });

  it("splits independently valid 365-day series windows because freshness gaps must not trip the 400-day query guard", async () => {
    const db = new FakeCardDatabase(
      [card({ product_id: "100", name: "Charizard" })],
      [
        sku({
          product_id: "100",
          observed_on: "2026-08-01",
          price_history: JSON.stringify([{ price: 15.75, date: "2026-08-01" }]),
        }),
        gradedPrice({
          product_id: "100",
          observed_on: "2026-06-01",
          price_history: JSON.stringify([{ price: 360, date: "2026-06-01" }]),
        }),
      ],
    );
    const adapter = createLocalDbDataSourceAdapter(db as unknown as D1Database);

    await expect(adapter.getPriceSeriesBatch!("100", [
      { grader: "Raw", grade: null, condition: "Near Mint", days: 365, finish: null },
      { grader: "PSA", grade: 10, condition: null, days: 365, finish: null },
    ])).resolves.toHaveLength(2);

    expect(db.preparedSql.filter((sql) =>
      sql.includes("FROM price_history_month AS history")
    )).toHaveLength(2);
  });

  it("starts market history from each series freshness because older graded series still need their own 90 days", async () => {
    const db = new FakeCardDatabase(
      [card({ product_id: "100", name: "Charizard" })],
      [
        sku({ product_id: "100", observed_on: "2026-07-30" }),
        gradedPrice({ product_id: "100", observed_on: "2026-01-15" }),
      ],
    );
    const adapter = createLocalDbDataSourceAdapter(db as unknown as D1Database);

    await adapter.getMarketPrices("100");

    const historyCall = db.boundCalls.find((call) =>
      call.sql.includes("FROM price_history_month AS history")
    );
    expect(historyCall?.values).toContain("2025-10-01");
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

  it("fails when the required number column is missing because PostgreSQL schema errors must not become partial search results", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Vaporeon" })],
        [],
        [],
        false,
      ) as unknown as D1Database,
    );

    await expect(adapter.searchCards("vaporeon")).rejects.toThrow("no such column: number");
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
        set_id: "BS",
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

  it("uses PostgreSQL-stable catalog ordering because equal sort keys must not move cards or sets between pages", async () => {
    const db = new FakeCardDatabase([], []);
    const adapter = createLocalDbDataSourceAdapter(db as unknown as D1Database);

    await adapter.searchCards("");
    await adapter.searchSets("");

    const cardSearchSql = db.preparedSql.find((sql) =>
      sql.includes("FROM cards_all") && sql.includes("LIMIT ? OFFSET ?")
    );
    const setSearchSql = db.preparedSql.find((sql) => sql.includes("FROM sets s"));
    expect(cardSearchSql).toContain(
      "ORDER BY updated_at DESC NULLS LAST, product_id ASC",
    );
    expect(setSearchSql).toContain("ORDER BY s.name ASC, s.set_id ASC");
  });

  it("adds the canonical Normal SKU price because Search must show one stable market reference without per-card HTTP requests", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "100", name: "Charizard" })],
        [
          sku({
            sku_id: null,
            variant_code: "F",
            variant_name: "Foil",
            change_30d_percent: 3186.713286713287,
            price_history: JSON.stringify([
              { price: "12.50", date: "2026-06-01" },
              { price: "15.75", date: "2026-07-08" },
            ]),
          }),
          sku({
            sku_id: 2,
            variant_code: "N",
            variant_name: "Normal",
            change_30d_percent: 13.513514,
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
        price_change_30d_percent: 13.513514,
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

  it("uses normalized PriceCharting ungraded series for the requested finish when no TCGplayer series exists", async () => {
    const adapter = createLocalDbDataSourceAdapter(
      new FakeCardDatabase(
        [card({ product_id: "180865" })],
        [
          sku({
            product_id: "180865",
            source_code: "pricecharting",
            source_record_id: "pc-normal",
            condition_code: null,
            condition_name: "Ungraded",
            variant_name: "Normal",
            price_history: JSON.stringify([{ price: 30, date: "2026-07-30" }]),
            change_7d_percent: 5,
          }),
          sku({
            sku_id: 2,
            series_id: 2,
            product_id: "180865",
            source_code: "pricecharting",
            source_record_id: "pc-foil",
            condition_code: null,
            condition_name: "Ungraded",
            variant_code: "F",
            variant_name: "Foil",
            price_history: JSON.stringify([{ price: 60, date: "2026-07-30" }]),
          }),
        ],
      ) as unknown as D1Database,
    );

    await expect(adapter.getMarketPrices("180865", "Normal")).resolves.toMatchObject([
      { grader: "Raw", condition: "Ungraded", price: 30, product_sub_type: "Normal", increase_percent: 5 },
    ]);
    await expect(
      adapter.getPriceSeries("180865", "Raw", null, "Ungraded", 30, "Normal"),
    ).resolves.toEqual([{ date: "2026-07-30", price: 30 }]);
  });

  it("builds Shop rows from published TCGplayer products because Card Detail must expose real marketplace links", async () => {
    const db = new FakeCardDatabase(
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
          sku_id: 4,
          source_code: "pricecharting",
          source_record_id: "pricecharting-ungraded",
          condition_code: null,
          condition_name: "Ungraded",
          price_history: JSON.stringify([
            { price: 20, date: "2026-07-11" },
          ]),
        }),
      ],
    );
    const adapter = createLocalDbDataSourceAdapter(db as unknown as D1Database);

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

  it("starts Shop card and price reads together because independent PostgreSQL waits must not serialize Card Detail", async () => {
    let releaseCard!: () => void;
    const cardBlocked = new Promise<void>((resolve) => {
      releaseCard = resolve;
    });
    const started: string[] = [];
    const db = {
      prepare(sql: string) {
        return {
          bind() {
            if (sql.includes("FROM cards_all")) {
              return {
                async first() {
                  started.push("card");
                  await cardBlocked;
                  return card({ product_id: "100", name: "Charizard" });
                },
              };
            }
            return {
              async all() {
                started.push("prices");
                return { results: [] };
              },
            };
          },
        };
      },
    };
    const pending = createLocalDbDataSourceAdapter(
      db as unknown as D1Database,
    ).getSoldListings("100");

    await Promise.resolve();
    await Promise.resolve();
    const startedBeforeCardCompleted = [...started];
    releaseCard();
    await pending;

    expect(startedBeforeCardCompleted).toEqual(["card", "prices"]);
  });

  it("reads the published Trending snapshot because Home must not scan all current prices", async () => {
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
            change_1d_percent: 5,
            price_history: JSON.stringify([
              { price: 10, date: "2026-07-14" },
              { price: 11, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 2,
            product_id: "200",
            change_1d_percent: 40,
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
            change_1d_percent: 60,
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
            change_1d_percent: 80,
            price_history: JSON.stringify([
              { price: 30, date: "2026-07-14" },
              { price: 54, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 4,
            product_id: "300",
            change_1d_percent: null,
            price_history: JSON.stringify([
              { price: 7, date: "2026-07-15" },
            ]),
          }),
          sku({
            sku_id: 5,
            product_id: "400",
            change_1d_percent: -20,
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
        previous_1d_price_usd: 30,
        price_change_1d_percent: 80,
      },
      {
        card_ref: "100",
        name: "Small Mover",
        price_usd: 11,
        previous_1d_price_usd: 10,
        price_change_1d_percent: 5,
      },
    ]);
    const trendingSql = db.preparedSql.find((sql) =>
      sql.includes("JOIN card_trending_snapshot AS trend"),
    );
    expect(trendingSql).toContain("pointer.scope_code = 'trending:global'");
    expect(trendingSql).toContain(
      "cards.product_id = trend.card_ref",
    );
    expect(trendingSql).not.toContain("NOT EXISTS");
    expect(trendingSql).not.toContain("tcg_price");
    expect(
      db.preparedSql.every((sql) => !/sku_id|pricecharting_id/i.test(sql)),
    ).toBe(true);
    expect(trendingSql).toContain("ORDER BY trend.rank");
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

let nextSeriesId = 1;

function sku(overrides: Partial<SkuRow>): SkuRow {
  const seriesId = overrides.series_id
    ?? (typeof overrides.sku_id === "number" ? overrides.sku_id : nextSeriesId++);
  const row: SkuRow = {
    sku_id: 1,
    series_id: seriesId,
    source_code: "tcgplayer",
    source_record_id: `sku-${seriesId}`,
    metric_code: "ungraded",
    product_id: "100",
    condition_code: "NM",
    condition_name: "Near Mint",
    language_code: "EN",
    language_name: "English",
    variant_code: "N",
    variant_name: "Normal",
    grader_code: "RAW",
    grade_min_x10: null,
    grade_max_x10: null,
    observed_on: "2026-07-30",
    amount_micros: 0,
    baseline_1d_on: null,
    baseline_1d_amount_micros: null,
    baseline_7d_on: null,
    baseline_7d_amount_micros: null,
    baseline_30d_on: null,
    baseline_30d_amount_micros: null,
    price_history: "[]",
    change_1d_percent: null,
    change_7d_percent: null,
    change_30d_percent: null,
    ...overrides,
  };
  const points = JSON.parse(row.price_history) as Array<{ date: string; price: number | string }>;
  const sorted = points.sort((left, right) => left.date.localeCompare(right.date));
  const latest = sorted.at(-1);
  const previous = sorted.at(-2);
  const first = sorted[0];
  return {
    ...row,
    observed_on: overrides.observed_on ?? latest?.date ?? row.observed_on,
    amount_micros: overrides.amount_micros
      ?? (latest ? Number(latest.price) * 1_000_000 : row.amount_micros),
    baseline_1d_on: overrides.baseline_1d_on ?? previous?.date ?? null,
    baseline_1d_amount_micros: overrides.baseline_1d_amount_micros
      ?? (previous ? Number(previous.price) * 1_000_000 : null),
    baseline_30d_on: overrides.baseline_30d_on ?? first?.date ?? null,
    baseline_30d_amount_micros: overrides.baseline_30d_amount_micros
      ?? (first ? Number(first.price) * 1_000_000 : null),
  };
}

function naturalKey(row: SkuRow): string {
  return [row.condition_name, row.language_name, row.variant_name]
    .map((value) => (value ?? "").trim().toLowerCase())
    .join("\u0000");
}

function gradedPrice(overrides: Partial<SkuRow> = {}): SkuRow {
  return sku({
    sku_id: 2,
    series_id: 2,
    source_code: "pricecharting",
    source_record_id: "pricecharting-2",
    metric_code: "psa_100",
    variant_code: "F",
    variant_name: "Foil",
    grader_code: "PSA",
    grade_min_x10: 100,
    grade_max_x10: 100,
    price_history: JSON.stringify([
      { price: "300", date: "2026-07-29" },
      { price: "360", date: "2026-07-30" },
    ]),
    ...overrides,
  });
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
