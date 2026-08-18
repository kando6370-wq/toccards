import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

describe("D1 migration chain", () => {
  let mf: Miniflare;
  let db: D1Database;

  beforeEach(async () => {
    mf = new Miniflare({ modules: true, script: "export default { fetch() { return new Response('ok') } }", compatibilityDate: "2024-11-01", d1Databases: ["DB"] });
    db = await mf.getD1Database("DB");
  });

  afterEach(async () => { await mf.dispose(); });

  it("applies every numbered migration in order because a fresh environment must reach the v1.1 schema", async () => {
    const directory = dirname(fileURLToPath(import.meta.url));
    const migrations = (await readdir(directory))
      .filter((name) => /^\d{4}_.+\.sql$/.test(name))
      .sort();

    for (const migration of migrations) {
      const sql = await readFile(join(directory, migration), "utf8");
      for (const statement of statements(sql)) await db.prepare(statement).run();
    }

    expect(migrations).toHaveLength(36);
    expect(migrations.at(-1)).toBe("0035_drop_trending_pin.sql");
    const trendingPin = await db.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'trending_pin'",
    ).first();
    expect(trendingPin).toBeNull();
    const tables = await db.prepare(`SELECT name FROM sqlite_master
      WHERE type = 'table' AND name IN (
        'billing_session_entitlement_grant', 'billing_apple_verification_attempt',
        'billing_apple_app_attest_key', 'apple_notification_inbox', 'scan_quota_request'
      ) ORDER BY name`).all();
    expect(tables.results.map((row) => row.name)).toEqual([
      "apple_notification_inbox", "billing_apple_app_attest_key",
      "billing_apple_verification_attempt", "billing_session_entitlement_grant",
      "scan_quota_request",
    ]);

    const columns = await db.prepare(`SELECT name FROM pragma_table_info('billing_transaction')
      WHERE name IN ('business_status', 'charge_count', 'source_notification_uuid', 'auto_renew_snapshot',
        'usd_exchange_rate', 'usd_exchange_rate_source', 'usd_conversion_version', 'usd_rounding_mode')
      ORDER BY cid`).all();
    expect(columns.results.map((row) => row.name)).toEqual([
      "business_status", "charge_count", "source_notification_uuid", "usd_exchange_rate",
      "usd_exchange_rate_source", "usd_conversion_version", "usd_rounding_mode",
      "auto_renew_snapshot",
    ]);
  }, 30_000);

  it("uses existing item dates as logical starts without inventing reliable v1.0 history", async () => {
    const directory = dirname(fileURLToPath(import.meta.url));
    const migrations = (await readdir(directory))
      .filter((name) => /^\d{4}_.+\.sql$/.test(name))
      .sort();

    for (const migration of migrations.filter((name) => name < "0031_")) {
      await applyMigration(db, join(directory, migration));
    }
    await db.prepare(`INSERT INTO portfolio_folder
      (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('trade', 'user', 'user-1', 'Trade', 1, 0, ?, ?)`)
      .bind("2025-01-02T00:00:00.000Z", "2026-08-12T00:00:00.000Z").run();
    await db.prepare(`INSERT INTO collection_item
      (id, owner_type, owner_id, folder_id, card_ref, object_type, grader, condition,
       language, finish, quantity, purchase_price, purchase_currency, folder_joined_at,
       created_at, updated_at)
      VALUES ('item-1', 'user', 'user-1', 'trade', '100', 'tcg', 'Raw', 'Near Mint (NM)',
              'English', 'Normal', 2, 25, 'USD', ?, ?, ?)`)
      .bind("2026-08-01T00:00:00.000Z", "2025-01-02T00:00:00.000Z", "2026-08-12T00:00:00.000Z").run();
    await db.prepare(`INSERT INTO collection_item_event
      (id, item_id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
       condition, language, finish, quantity, event_type, effective_at)
      VALUES ('legacy-baseline', 'item-1', 'user', 'user-1', 'trade', '100', 'tcg',
              'Raw', 'Near Mint (NM)', 'English', 'Normal', 2, 'upsert', ?)`)
      .bind("2025-01-02T00:00:00.000Z").run();

    await applyMigration(db, join(directory, "0031_performance_history.sql"));

    const item = await db.prepare(`SELECT performance_start_at,
      purchase_price_effective_at, performance_history_available_from
      FROM collection_item WHERE id = 'item-1'`).first<Record<string, string>>();
    expect(item?.performance_start_at).toBe("2025-01-02T00:00:00.000Z");
    expect(item?.purchase_price_effective_at).toBe("2025-01-02T00:00:00.000Z");
    expect(item?.performance_history_available_from).toBeTruthy();
    expect(item!.performance_history_available_from > "2025-01-02T00:00:00.000Z").toBe(true);

    const event = await db.prepare(`SELECT folder_id, effective_at, purchase_price,
      purchase_currency, performance_history_available_from
      FROM collection_item_event WHERE id = 'legacy-baseline'`).first<Record<string, string | number>>();
    expect(event).toMatchObject({
      folder_id: "trade",
      effective_at: "2025-01-02T00:00:00.000Z",
      purchase_price: 25,
      purchase_currency: "USD",
      performance_history_available_from: item!.performance_history_available_from,
    });
  }, 30_000);
});

async function applyMigration(db: D1Database, path: string): Promise<void> {
  const sql = await readFile(path, "utf8");
  for (const statement of statements(sql)) await db.prepare(statement).run();
}

function statements(sql: string): string[] {
  return sql.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean);
}
