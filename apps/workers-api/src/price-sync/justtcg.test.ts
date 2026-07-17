import { describe, expect, it, vi } from "vitest";
import {
  normalizeJustTcgResponse,
  runJustTcgPriceSync,
} from "./justtcg";

type StoredState = {
  source: string;
  status: string;
  cursor_product_id: number | null;
  cycle_started_at: string | null;
  last_attempt_at: string | null;
  last_success_at: string | null;
  last_completed_at: string | null;
  next_run_at: string | null;
  products_processed: number;
  variants_written: number;
  covered_products: number;
  total_products: number;
  last_error: string | null;
};

class FakePriceDatabase {
  constructor(readonly products: number[]) {}

  state: StoredState | null = null;
  variants: unknown[][] = [];

  prepare(sql: string): FakeStatement {
    return new FakeStatement(this, sql, []);
  }

  async batch(statements: D1PreparedStatement[]): Promise<D1Result[]> {
    return Promise.all(
      statements.map((statement) =>
        (statement as unknown as FakeStatement).run() as Promise<D1Result>,
      ),
    );
  }
}

class FakeStatement {
  constructor(
    private readonly db: FakePriceDatabase,
    private readonly sql: string,
    private readonly values: unknown[],
  ) {}

  bind(...values: unknown[]): FakeStatement {
    return new FakeStatement(this.db, this.sql, values);
  }

  async first<T>(): Promise<T | null> {
    if (this.sql.includes("FROM price_sync_state")) {
      return this.db.state as T | null;
    }
    if (this.sql.includes("AS covered_products")) {
      return {
        covered_products: new Set(
          this.db.variants.map((values) => Number(values[0])),
        ).size,
        total_products: this.db.products.length,
      } as T;
    }
    return null;
  }

  async all<T>(): Promise<{ results: T[] }> {
    if (this.sql.includes("FROM cards_all")) {
      const cursor = Number(this.values[0]);
      const limit = Number(this.values[1]);
      return {
        results: this.db.products
          .filter((productId) => productId > cursor)
          .slice(0, limit)
          .map((productId) => ({ product_id: String(productId) })) as T[],
      };
    }
    return { results: [] };
  }

  async run(): Promise<D1Result> {
    if (this.sql.includes("INSERT INTO price_sync_state")) {
      this.db.state = {
        source: String(this.values[0]),
        status: String(this.values[1]),
        cursor_product_id: this.values[2] as number | null,
        cycle_started_at: this.values[3] as string | null,
        last_attempt_at: this.values[4] as string | null,
        last_success_at: this.values[5] as string | null,
        last_completed_at: this.values[6] as string | null,
        next_run_at: this.values[7] as string | null,
        products_processed: Number(this.values[8]),
        variants_written: Number(this.values[9]),
        covered_products: Number(this.values[10]),
        total_products: Number(this.values[11]),
        last_error: this.values[12] as string | null,
      };
    } else if (this.sql.includes("INSERT INTO tcgplayer_skus")) {
      const sourceVariantId = String(this.values[12]);
      const existing = this.db.variants.findIndex(
        (values) => String(values[12]) === sourceVariantId,
      );
      if (existing === -1) this.db.variants.push(this.values);
      else this.db.variants[existing] = this.values;
    }
    return { success: true } as D1Result;
  }
}

describe("JustTCG price synchronization", () => {
  it("normalizes only requested Raw conditions because unknown provider states must never become portfolio prices", () => {
    const timestamp = Date.parse("2026-07-17T00:00:00.000Z") / 1000;

    expect(
      normalizeJustTcgResponse(
        {
          data: [
            {
              tcgplayerId: "100",
              variants: [
                {
                  uuid: "variant-nm",
                  condition: "Near Mint",
                  printing: "Normal",
                  price: 12.5,
                  lastUpdated: timestamp,
                  priceHistory: [
                    { p: 11, t: timestamp - 86400 },
                    { p: 12, t: timestamp },
                  ],
                },
                {
                  uuid: "variant-unknown",
                  condition: "Authentic",
                  printing: "Normal",
                  price: 99,
                  lastUpdated: timestamp,
                },
              ],
            },
            {
              tcgplayerId: "999",
              variants: [
                {
                  uuid: "foreign",
                  condition: "Near Mint",
                  printing: "Normal",
                  price: 20,
                  lastUpdated: timestamp,
                },
              ],
            },
          ],
        },
        new Set([100]),
      ),
    ).toEqual([
      {
        productId: 100,
        sourceVariantId: "variant-nm",
        conditionCode: "NM",
        conditionName: "Near Mint",
        languageCode: "EN",
        languageName: "English",
        variantCode: "N",
        variantName: "Normal",
        priceHistory: [
          { date: "2026-07-16", price: 11 },
          { date: "2026-07-17", price: 12.5 },
        ],
      },
    ]);
  });

  it("records a blocked state when the API key is absent because a cron must not look healthy without a real provider", async () => {
    const db = new FakePriceDatabase([100]);
    const fetcher = vi.fn();

    const status = await runJustTcgPriceSync(
      { DB: db as unknown as D1Database },
      {
        fetch: fetcher,
        now: new Date("2026-07-17T00:00:00.000Z"),
      },
    );

    expect(status.status).toBe("blocked");
    expect(status.last_error).toContain("JUSTTCG_API_KEY");
    expect(status.covered_products).toBe(0);
    expect(status.total_products).toBe(1);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("advances only after a validated provider batch because retries must not skip catalog products", async () => {
    const db = new FakePriceDatabase([100, 200]);
    const timestamp = Date.parse("2026-07-17T00:00:00.000Z") / 1000;
    const fetcher = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          data: [
            {
              tcgplayerId: "100",
              variants: [
                {
                  uuid: "variant-100-nm",
                  condition: "NM",
                  printing: "Normal",
                  price: 3.25,
                  lastUpdated: timestamp,
                },
              ],
            },
          ],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );

    const status = await runJustTcgPriceSync(
      {
        DB: db as unknown as D1Database,
        JUSTTCG_API_KEY: "real-provider-key",
        JUSTTCG_BATCH_SIZE: "100",
      },
      {
        fetch: fetcher,
        now: new Date("2026-07-17T00:00:00.000Z"),
      },
    );

    expect(status).toMatchObject({
      status: "running",
      cursor_product_id: 200,
      products_processed: 2,
      variants_written: 1,
      covered_products: 1,
      total_products: 2,
      last_error: null,
    });
    expect(db.variants[0]).toMatchObject({
      0: 100,
      10: JSON.stringify([{ date: "2026-07-17", price: 3.25 }]),
      11: "justtcg-v1",
      12: "variant-100-nm",
    });

    const completed = await runJustTcgPriceSync(
      {
        DB: db as unknown as D1Database,
        JUSTTCG_API_KEY: "real-provider-key",
      },
      {
        fetch: fetcher,
        now: new Date("2026-07-17T00:05:00.000Z"),
      },
    );

    expect(completed).toMatchObject({
      status: "completed",
      products_processed: 2,
      variants_written: 1,
      next_run_at: "2026-07-18T00:00:00.000Z",
    });
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("keeps the cursor on provider failure because the same products must be retried", async () => {
    const db = new FakePriceDatabase([100, 200]);
    const status = await runJustTcgPriceSync(
      {
        DB: db as unknown as D1Database,
        JUSTTCG_API_KEY: "real-provider-key",
      },
      {
        fetch: vi.fn().mockResolvedValue(new Response("quota exceeded", { status: 429 })),
        now: new Date("2026-07-17T00:00:00.000Z"),
      },
    );

    expect(status.status).toBe("failed");
    expect(status.cursor_product_id).toBeNull();
    expect(status.products_processed).toBe(0);
    expect(status.last_error).toContain("HTTP 429");
  });
});
