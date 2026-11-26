import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import type { CardSearchResult, MarketPrice } from "./adapter";
import { createDataSourceRoutes } from "./routes";

describe("scan review prices on the public card detail route", () => {
  let db: PGliteDatabase;
  let env: Env;
  const app = createDataSourceRoutes();

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    for (const name of ["0000_business_schema.sql", "0001_price_domain.sql"]) {
      await db.exec(readFileSync(new URL(`../db/postgres/migrations/${name}`, import.meta.url), "utf8"));
    }
    await db.exec(`
      INSERT INTO cards_all (product_id, game_id, name) VALUES ('a', 1, 'Card A'), ('b', 1, 'No quotes'), ('many', 1, 'Many variants');
      CREATE TABLE review_current PARTITION OF price_current_snapshot DEFAULT;
      INSERT INTO price_source (source_code, display_name, source_kind) VALUES ('tcgplayer', 'Test', 'external');
      INSERT INTO price_series (source_id, source_record_id, metric_code, card_ref, currency_code, condition_code,
        condition_name, language_code, language_name, finish_code, finish_name, grader_code, grade_min_x10, grade_max_x10)
      VALUES (1, 'zero', 'market', 'a', 'USD', 'NM', 'Near Mint', 'EN', 'English', 'N', 'Normal', 'RAW', NULL, NULL),
        (1, 'fallback', 'market', 'a', 'USD', 'NM', 'Near Mint', NULL, NULL, 'N', 'Normal', 'RAW', NULL, NULL),
        (1, 'graded', 'market', 'a', 'USD', NULL, NULL, 'JA', 'Japanese', 'F', 'Foil', 'PSA', 95, 95);
      INSERT INTO price_series (source_id, source_record_id, metric_code, card_ref, currency_code, language_name, finish_name, grader_code)
      SELECT 1, 'many-' || i, 'market', 'many', 'USD', 'Language ' || i, 'Finish ' || i, 'RAW' FROM generate_series(1, 11) i;
      INSERT INTO price_ingest_batch (scope_code, source_id, business_date, idempotency_key, input_object_key, input_checksum_sha256,
        expected_series_count, loaded_series_count, distinct_series_count, status, validated_at, content_checksum_sha256)
      VALUES ('current:tcgplayer', 1, '2026-11-05', 'review', 'review', repeat('a',64), 14, 14, 14, 'validated', now(), repeat('b',64));
      INSERT INTO price_current_snapshot (batch_id, series_id, observed_on, amount_micros)
      SELECT 1, series_id, '2026-11-05', CASE source_record_id WHEN 'zero' THEN 0 WHEN 'fallback' THEN 5000000 ELSE 12500000 END FROM price_series;
      UPDATE price_ingest_batch SET status='published', published_at=now() WHERE batch_id=1;
      INSERT INTO current_price_pointer (scope_code, batch_id, updated_by) VALUES ('current:tcgplayer', 1, 'review');
    `);
    env = { DB: db, CACHE_KV: { get: async () => null, put: async () => {} } as unknown as KVNamespace, JWT_SECRET: "review" };
    vi.stubGlobal("caches", { default: { match: async () => undefined, put: async () => {} } });
  });

  afterAll(async () => { vi.unstubAllGlobals(); await db.close(); });

  async function data<T>(url: string): Promise<T> {
    const response = await app.request(url, {}, env);
    expect(response.status).toBe(200);
    return ((await response.json()) as { data: T }).data;
  }

  it("matches the old per-variant quotes including zero and language fallback, with one snapshot read and no history", async () => {
    const query = vi.spyOn(db, "query");
    const detail = await data<CardSearchResult>("/cards/a?include=review_prices");
    const sql = query.mock.calls.map(([statement]) => statement);
    expect(sql.filter((statement) => statement.includes("FROM price_series AS series"))).toHaveLength(1);
    expect(sql.filter((statement) => statement.includes("FROM cards_all"))).toHaveLength(1);
    expect(sql.some((statement) => statement.includes("price_history_month"))).toBe(false);
    expect(detail.review_prices).toEqual([
      { finish: "Foil", language: "Japanese", grader: "PSA", grade: 9.5, condition: null, price: 12.5 },
      { finish: "Normal", language: "English", grader: "Raw", grade: null, condition: "Near Mint", price: 0 },
      { finish: "Normal", language: "Japanese", grader: "Raw", grade: null, condition: "Near Mint", price: 5 },
    ]);
    for (const finish of detail.available_finishes!) {
      for (const language of detail.available_languages!) {
        const legacy = await data<{ prices: MarketPrice[] }>(`/cards/a/market-prices?finish=${finish}&language=${language}`);
        expect(detail.review_prices!.filter((row) => row.finish === finish && row.language === language))
          .toEqual(legacy.prices.map(({ grader, grade, condition, price }) => ({ finish, language, grader, grade, condition, price })));
      }
    }
    expect(await data("/cards/a")).not.toHaveProperty("review_prices");
  });

  it("distinguishes no quotes from a corrected fallback selection or an oversized variant matrix", async () => {
    expect(await data("/cards/b?include=review_prices")).toHaveProperty("review_prices", []);
    await db.exec(`INSERT INTO card_override (id,card_ref,override_fields,updated_at)
      VALUES ('corrected','b','{"finish":"Normal"}','2026-11-05')`);
    const corrected = await data("/cards/b?include=review_prices");
    expect(corrected).toMatchObject({ finish: "Normal", override_applied: true });
    expect(corrected).not.toHaveProperty("review_prices");
    const many = await data<CardSearchResult>("/cards/many?include=review_prices");
    expect(many.available_finishes).toHaveLength(11);
    expect(many).not.toHaveProperty("review_prices");
  });
});
