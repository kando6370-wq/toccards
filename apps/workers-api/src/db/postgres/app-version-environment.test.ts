import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { PGliteDatabase } from "../../test-support/pglite-database";

const migration = readFileSync(new URL("./migrations/0011_app_version_environment.sql", import.meta.url), "utf8");

describe("PostgreSQL version configuration migration", () => {
  let db: PGliteDatabase;
  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec("CREATE TABLE app_config (key text PRIMARY KEY, value text NOT NULL, updated_by text, updated_at text NOT NULL)");
  });
  beforeEach(async () => { await db.exec("DELETE FROM app_config"); });
  afterAll(async () => { await db?.close(); });

  async function insert(key: string, value: unknown) {
    await db.prepare("INSERT INTO app_config VALUES (?, ?, 'operator', '2026-09-08')")
      .bind(key, typeof value === "string" ? value : JSON.stringify(value)).run();
  }

  it("preserves the current forced rule for each environment without overwriting later independent edits", async () => {
    const ios = {
      platform: "iOS", min_supported_version: "1.0.1", recommended_version: "1.0.1",
      force_update: true, status: "enabled", store_url: "https://apps.apple.com/app/id6793017224",
      forced_update_message: "Please update to continue.",
    };
    await insert("admin.app_version.ios", ios);
    await db.exec(migration);
    const rows = (await db.query<{ key: string; value: string }>("SELECT key, value FROM app_config WHERE key LIKE 'admin.app_version.%.ios' ORDER BY key")).rows;
    expect(rows).toHaveLength(2);
    for (const row of rows) expect(JSON.parse(row.value)).toMatchObject(ios);

    await db.prepare("UPDATE app_config SET value = ? WHERE key = ?")
      .bind(JSON.stringify({ ...ios, recommended_version: "2.0.0" }), "admin.app_version.development.ios").run();
    await db.exec(migration);
    const dev = await db.prepare("SELECT value FROM app_config WHERE key = 'admin.app_version.development.ios'").first<{ value: string }>();
    expect(JSON.parse(dev!.value).recommended_version).toBe("2.0.0");
    const legacy = await db.prepare("SELECT value FROM app_config WHERE key = 'admin.app_version.ios'").first<{ value: string }>();
    expect(JSON.parse(legacy!.value)).toEqual(ios);
  });

  it("initializes all four disabled rules on an empty database so a fresh environment has an explicit decision", async () => {
    await db.exec(migration);
    const rows = (await db.query<{ value: string }>("SELECT value FROM app_config")).rows;
    expect(rows).toHaveLength(4);
    for (const row of rows) expect(JSON.parse(row.value)).toMatchObject({ status: "disabled", force_update: false, store_url: "" });
  });

  it("copies the legacy shared prompt only once and retains the effective shared store fallback", async () => {
    await insert("upgrade_prompt", { latest_version: "1.0.2", force_update: true, message: "Update required" });
    await insert("app_store_url", "https://apps.apple.com/app/id6793017224");
    await db.exec(migration);
    const rows = (await db.query<{ value: string }>("SELECT value FROM app_config WHERE key LIKE 'admin.app_version.%'")).rows;
    expect(rows).toHaveLength(4);
    for (const row of rows) expect(JSON.parse(row.value)).toMatchObject({ min_supported_version: "1.0.2", recommended_version: "1.0.2", force_update: true, status: "enabled", store_url: "https://apps.apple.com/app/id6793017224" });
  });
});
