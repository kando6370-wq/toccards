import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import { app } from "../app";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";

const endpoint = "/api/v1/extension/recognize";
let db: PGliteDatabase;

function setup(candidates: Array<{ product_id: string | number; confidence: number }>) {
  const forbidden = new Proxy({}, { get() { throw new Error("Plugin detail lookup must not access KV or image storage."); } });
  const env = {
    DB: db, CACHE_KV: forbidden, SCAN_IMAGES: forbidden,
    EXTENSION_RECOGNITION_KEY: "postgres-plugin-test-only",
    EXTENSION_RECOGNITION_RATE_LIMITER: { limit: async () => ({ success: true }) },
    EXTENSION_CLIENT_IP: "192.0.2.1",
    VECTOR_RECOGNITION: { fetch: async () => Response.json({ candidates }) },
  } as unknown as Env;
  const request = () => app.request(endpoint, {
    method: "POST",
    headers: { Authorization: "Bearer postgres-plugin-test-only", "Content-Type": "application/json" },
    body: JSON.stringify({ vector: [1, ...Array(511).fill(0)], card_type: 0 }),
  }, env);
  const detail = (cardRef: string) => app.request(`/api/v1/cards/${encodeURIComponent(cardRef)}`, undefined, env);
  return { request, detail };
}

describe("plugin card detail PostgreSQL business parity", () => {
  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec(`
      CREATE TABLE cards_all (
        product_id text PRIMARY KEY, game_id integer, game text, set_id text,
        set_name text, set_code text, number text, name text, rarity text, product_type_name text
      );
      CREATE TABLE card_override (card_ref text PRIMARY KEY, override_fields text, image_url text, is_missing_card integer);
      CREATE TABLE price_source (source_id bigint, source_code text, is_active boolean);
      CREATE TABLE current_price_pointer (scope_code text, batch_id bigint);
      CREATE TABLE price_ingest_batch (batch_id bigint, source_id bigint, scope_code text, business_date date, status text);
      CREATE TABLE price_series (
        series_id bigint, source_id bigint, source_record_id text, metric_code text,
        card_ref text, condition_code text, condition_name text, language_code text, language_name text,
        finish_code text, finish_name text, grader_code text, grade_min_x10 smallint, grade_max_x10 smallint,
        currency_code text, is_active boolean
      );
      CREATE TABLE price_current_snapshot (
        batch_id bigint, series_id bigint, observed_on date, amount_micros bigint,
        baseline_1d_on date, baseline_1d_amount_micros bigint,
        baseline_7d_on date, baseline_7d_amount_micros bigint,
        baseline_30d_on date, baseline_30d_amount_micros bigint,
        change_1d_percent numeric, change_7d_percent numeric, change_30d_percent numeric
      );
      INSERT INTO cards_all VALUES
        ('10738', 1, 'Pokemon', 'base', 'Base Set', 'BS', '4/102', 'Provider Charizard', 'Rare', 'Cards'),
        ('unpriced', 1, 'Pokemon', 'promo', 'Promos', 'PR', '001', 'Unpriced promo', 'Promo', 'Cards');
      INSERT INTO card_override VALUES
        ('10738', '{"name":"Corrected Charizard","rarity":"Promo"}', 'https://custom.invalid/card.jpg', 0),
        ('admin:tcg:missing-promo', '{"name":"Manual promo","set_name":"Promos","set_code":"PR","card_number":"001","object_type":"tcg"}', null, 1);
      INSERT INTO price_source VALUES (1, 'tcgplayer', true);
      INSERT INTO price_ingest_batch VALUES (10, 1, 'current:tcgplayer', '2026-10-09', 'published');
      INSERT INTO current_price_pointer VALUES ('current:tcgplayer', 10);
      INSERT INTO price_series VALUES
        (1, 1, 'raw-en', 'ungraded', '10738', 'NM', 'Near Mint', 'EN', 'English', 'N', 'Normal', 'Raw', null, null, 'USD', true),
        (2, 1, 'raw-ja', 'ungraded', '10738', 'NM', 'Near Mint', 'JA', 'Japanese', 'H', 'Holo', 'Raw', null, null, 'USD', true),
        (3, 1, 'psa', 'psa', '10738', null, null, 'EN', 'English', 'N', 'Normal', 'PSA', 100, 100, 'USD', true);
      INSERT INTO price_current_snapshot VALUES
        (10, 1, '2026-10-09', 12500000, '2026-10-08', 10000000, '2026-10-02', 8000000, '2026-09-09', 5000000, 25, 56.25, 150),
        (10, 2, '2026-10-09', 100000000, null, null, null, null, null, null, null, null, 200),
        (10, 3, '2026-10-09', 500000000, null, null, null, null, null, null, null, null, null);
    `);
  });
  afterAll(async () => { await db?.close(); });
  beforeEach(() => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    const prepare = db.prepare.bind(db);
    vi.spyOn(db, "prepare").mockImplementation((query) => {
      expect(query.trim()).toMatch(/^(SELECT|WITH)\b/);
      return prepare(query);
    });
  });
  afterEach(() => { vi.restoreAllMocks(); });

  it("returns the same complete published-price, image, and operations-corrected data as the existing public card detail API", async () => {
    const { request, detail } = setup([{ product_id: 10738, confidence: 92.125 }]);
    const existing = await detail("10738");
    const expected = await existing.json() as { data: Record<string, unknown> };
    expect(existing.status).toBe(200);
    expect(expected.data).toMatchObject({
      name: "Corrected Charizard", rarity: "Promo", override_applied: true,
      image_url: "https://image.tcgcard.fun/cards/10738.jpg",
      price_usd: 12.5, previous_1d_price_usd: 10, previous_7d_price_usd: 8, previous_30d_price_usd: 5,
      price_change_1d_percent: 25, price_change_7d_percent: 56.25, price_change_30d_percent: 150,
      price_as_of: "2026-10-09", available_languages: ["English", "Japanese"], available_finishes: ["Holo", "Normal"],
    });
    const response = await request();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ candidates: [{ ...expected.data, product_id: "10738", confidence: 92.125 }] });
  });

  it("preserves existing detail semantics for manual backfill and missing prices instead of applying scan-only catalog filtering", async () => {
    const { request, detail } = setup([
      { product_id: "unpriced", confidence: 90 },
      { product_id: "admin:tcg:missing-promo", confidence: 85 },
      { product_id: "missing", confidence: 99 },
    ]);
    const unpriced = await (await detail("unpriced")).json() as { data: Record<string, unknown> };
    const manual = await (await detail("admin:tcg:missing-promo")).json() as { data: Record<string, unknown> };
    expect(unpriced.data).not.toHaveProperty("price_usd");
    expect(manual.data).toMatchObject({ name: "Manual promo", override_applied: true });
    expect((await detail("missing")).status).toBe(404);
    const response = await request();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ candidates: [
      { ...unpriced.data, product_id: "unpriced", confidence: 90 },
      { ...manual.data, product_id: "admin:tcg:missing-promo", confidence: 85 },
    ] });
  });
  it("binds product IDs as values so retrieval text cannot widen the catalog or published-price query", async () => {
    const { request } = setup([
      { product_id: "10738' OR '1'='1", confidence: 99 },
      { product_id: "10738", confidence: 92.125 },
    ]);
    const response = await request();
    expect(response.status).toBe(200);
    const body = await response.json() as { candidates: Array<{ product_id: string; price_usd: number }> };
    expect(body.candidates).toHaveLength(1);
    expect(body.candidates[0]).toMatchObject({ product_id: "10738", price_usd: 12.5 });
  });

});
