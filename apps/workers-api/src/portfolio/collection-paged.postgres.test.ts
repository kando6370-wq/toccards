import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { createPortfolioRoutes } from "./routes";

const JWT_SECRET = "collection-paged-test";
const NOW = "2026-08-01T00:00:00.000Z";

describe("collection paged read model", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    const migrations = new URL("../db/postgres/migrations/", import.meta.url);
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0001_price_domain.sql", migrations), "utf8"));
    await db.exec("CREATE TABLE price_current_snapshot_test PARTITION OF price_current_snapshot DEFAULT");
    await db.exec(`
      INSERT INTO "user" (id, email, created_at, updated_at)
      VALUES ('owner-1', 'owner@example.com', '${NOW}', '${NOW}');
      INSERT INTO session (id, owner_type, owner_id, refresh_token, expires_at, created_at)
      VALUES ('session-1', 'user', 'owner-1', 'refresh-1', '2099-01-01T00:00:00.000Z', '${NOW}');
      INSERT INTO portfolio_folder (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('main', 'user', 'owner-1', 'Main', 1, 0, '${NOW}', '${NOW}');
      INSERT INTO user_preference (id, owner_type, owner_id, currency, amount_hidden, created_at, updated_at)
      VALUES ('pref-1', 'user', 'owner-1', 'USD', 0, '${NOW}', '${NOW}');
      INSERT INTO collection_item (id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
        grade, quantity, language, created_at, updated_at)
      VALUES ('older', 'user', 'owner-1', 'main', 'card-a', 'tcg', 'Raw', NULL, 2, ' English ',
          '2026-07-01T00:00:00.000Z', '2026-07-01T00:00:00.000Z'),
        ('newer', 'user', 'owner-1', 'main', 'card-b', 'tcg', 'PSA', 10, 1, ' ',
          '2026-07-02T00:00:00.000Z', '2026-07-02T00:00:00.000Z');
      INSERT INTO wishlist_item (id, owner_type, owner_id, card_ref, created_at)
      VALUES ('wish-1', 'user', 'owner-1', 'card-c', '2026-07-03T00:00:00.000Z');
    `);
    token = await signAccessToken(
      { owner_type: "user", owner_id: "owner-1", session_id: "session-1" },
      JWT_SECRET,
    );
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
  });

  afterEach(async () => db.close());

  it("bounds the default page while summary retains all-folder totals", async () => {
    const query = vi.spyOn(db, "query");
    const first = await request("/collection/items?tab=portfolio&page_size=1");
    expect(first.status).toBe(200);
    const firstBody = await first.json() as { data: { items: Array<{ id: string }>; total: number; base_count: number } };
    expect(firstBody.data.items.map((item) => item.id)).toEqual(["newer"]);
    expect(firstBody.data.total).toBe(2);
    expect(firstBody.data.base_count).toBe(2);
    const itemQuery = query.mock.results.find((_, index) =>
      query.mock.calls[index]?.[0].includes("WITH total AS")
    );
    expect((await itemQuery?.value)?.rows).toHaveLength(1);

    const summary = await request("/collection/summary");
    expect(summary.status).toBe(200);
    const summaryBody = await summary.json() as { data: { folders: Array<Record<string, unknown>>; wishlist_count: number } };
    expect(summaryBody.data.folders[0]).toMatchObject({
      folder_id: "main", item_count: 2, card_count: 3, graded_count: 1,
      total_value_usd: null, languages: ["English", "Unknown"],
    });
    expect(summaryBody.data.wishlist_count).toBe(1);

    const second = await request("/collection/items?tab=portfolio&page_size=1&page=2");
    expect((await second.json() as { data: { items: Array<{ id: string }> } }).data.items.map((item) => item.id))
      .toEqual(["older"]);
  });

  it("keeps wishlist paging and rejects missing authentication", async () => {
    const wishlist = await request("/collection/items?tab=wishlist&page_size=1");
    expect(wishlist.status).toBe(200);
    expect((await wishlist.json() as { data: { items: Array<{ id: string }>; total: number } }).data)
      .toMatchObject({ items: [expect.objectContaining({ id: "wish-1" })], total: 1 });
    expect((await createPortfolioRoutes().request("/collection/items", {}, env)).status).toBe(401);
    expect((await createPortfolioRoutes().request("/collection/summary", {}, env)).status).toBe(401);
  });

  it("sorts and filters the full matching set before slicing, while keeping zero and missing prices distinct", async () => {
    await db.exec(`
      INSERT INTO cards_all (product_id, game_id, game, name, set_name, number)
      VALUES ('card-a', 1, ' Pokemon ', ' Alpha ', 'Base', '001'),
             ('card-b', 1, 'Pokemon', ' Beta ', 'Base', '002'),
             ('card-c', 2, 'Sports', 'Gamma', 'League', '003');
      INSERT INTO price_source (source_code, display_name, source_kind)
      VALUES ('pricecharting', 'Pricecharting', 'external');
      INSERT INTO price_series (source_id, source_record_id, metric_code, card_ref, currency_code,
        language_name, grader_code, grade_min_x10, grade_max_x10)
      VALUES (1, 'a', 'market', 'card-a', 'USD', 'English', 'RAW', NULL, NULL),
             (1, 'b', 'market', 'card-b', 'USD', 'Japanese', 'PSA', 100, 100);
      INSERT INTO price_ingest_batch (scope_code, source_id, business_date, idempotency_key,
        input_object_key, input_checksum_sha256, content_checksum_sha256,
        expected_series_count, loaded_series_count, distinct_series_count,
        status, validated_at, published_at)
      VALUES ('current:pricecharting', 1, '2026-11-02', 'batch-1', 'input', repeat('a', 64),
        repeat('b', 64), 2, 2, 2, 'published', now(), now());
      INSERT INTO price_current_snapshot (batch_id, series_id, observed_on, amount_micros,
        baseline_30d_on, baseline_30d_amount_micros)
      VALUES (1, 1, '2026-11-02', 10000000, '2026-10-03', 5000000),
             (1, 2, '2026-11-02', 0, '2026-10-03', 5000000);
      INSERT INTO current_price_pointer (scope_code, batch_id, updated_by)
      VALUES ('current:pricecharting', 1, 'test');
    `);
    await db.prepare(`
      INSERT INTO collection_item (id, owner_type, owner_id, folder_id, card_ref, object_type,
        grader, quantity, created_at, updated_at)
      VALUES ('missing', 'user', 'owner-1', 'main', 'card-c', 'tcg', 'Raw', 1,
        '2026-07-03T00:00:00.000Z', '2026-07-03T00:00:00.000Z')
    `).run();

    const byValue = await request("/collection/items?sort=value_desc&page_size=1");
    expect(byValue.status).toBe(200);
    const first = await byValue.json() as { data: { items: Array<{ id: string; market_price_usd: number | null }>; total: number } };
    expect(first.data.items).toMatchObject([{ id: "older", market_price_usd: 10 }]);
    expect(first.data.total).toBe(3);
    const secondValuePage = await request("/collection/items?sort=value_desc&page_size=1&page=2");
    expect((await secondValuePage.json() as { data: { items: Array<{ id: string; market_price_usd: number | null }>; total: number } }).data)
      .toMatchObject({ items: [expect.objectContaining({ id: "newer", market_price_usd: 0 })], total: 3 });
    const missingValuePage = await request("/collection/items?sort=value_desc&page_size=1&page=3");
    expect((await missingValuePage.json() as { data: { items: Array<{ id: string; market_price_usd: number | null }> } }).data.items)
      .toMatchObject([{ id: "missing", market_price_usd: null }]);
    const byLowValue = await request("/collection/items?sort=value_asc&page_size=1");
    expect((await byLowValue.json() as { data: { items: Array<{ id: string; market_price_usd: number | null }> } }).data.items)
      .toMatchObject([{ id: "newer", market_price_usd: 0 }]);
    const byChange = await request("/collection/items?sort=change_desc&page_size=1");
    expect((await byChange.json() as { data: { items: Array<{ id: string; increase_percent: number | null }> } }).data.items)
      .toMatchObject([{ id: "older", increase_percent: 100 }]);
    const secondChangePage = await request("/collection/items?sort=change_desc&page_size=1&page=2");
    expect((await secondChangePage.json() as { data: { items: Array<{ id: string; increase_percent: number | null }> } }).data.items)
      .toMatchObject([{ id: "newer", increase_percent: -100 }]);
    const byName = await request("/collection/items?sort=name_asc&page_size=1");
    expect((await byName.json() as { data: { items: Array<{ id: string }> } }).data.items)
      .toMatchObject([{ id: "older" }]);
    const byPerformance = await request("/collection/items?sort=performance_desc&performance_id=newer&performance_id=older&page_size=1");
    expect((await byPerformance.json() as { data: { items: Array<{ id: string }> } }).data.items)
      .toMatchObject([{ id: "newer" }]);
    const filtered = await request("/collection/items?q=Alpha&game=Pokemon&language=English&sort=value_desc&page_size=1");
    expect(filtered.status).toBe(200);
    expect((await filtered.json() as { data: { items: Array<{ id: string }>; total: number } }).data)
      .toMatchObject({ items: [expect.objectContaining({ id: "older" })], total: 1 });
    const marketLanguage = await request("/collection/items?language=Japanese&sort=value_asc&page_size=1");
    expect((await marketLanguage.json() as { data: { items: Array<{ id: string }>; total: number } }).data)
      .toMatchObject({ items: [expect.objectContaining({ id: "newer" })], total: 1 });
    const noMatch = await request("/collection/items?q=not-found&page_size=1");
    expect((await noMatch.json() as { data: { items: unknown[]; total: number; base_count: number } }).data)
      .toMatchObject({ items: [], total: 0, base_count: 3 });

    const summary = await request("/collection/summary");
    expect(summary.status).toBe(200);
    const summaryData = (await summary.json() as { data: { folders: Array<{ total_value_usd: number | null; card_count: number }>; games: string[] } }).data;
    const total = summaryData.folders[0];
    expect(total).toMatchObject({ total_value_usd: 20, card_count: 4, languages: ["English", "Japanese", "Unknown"] });
    expect(summaryData.games).toEqual(["Pokemon", "Sports"]);
  });

  it("rejects unknown sort and tab instead of silently changing the requested list", async () => {
    expect((await request("/collection/items?sort=unknown")).status).toBe(422);
    expect((await request("/collection/items?tab=unknown")).status).toBe(422);
  });

  function request(path: string) {
    return createPortfolioRoutes().request(path, {
      headers: { Authorization: `Bearer ${token}` },
    }, env);
  }
});
