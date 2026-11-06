import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { PGliteDatabase } from "./pglite-database";

const databases = new Set<PGliteDatabase>();
const createdAt = "2026-07-07T00:00:00.000Z";
const tables = new Set([
  "portfolio_folder", "collection_item", "collection_item_event", "wishlist_item", "user_preference",
]);

export async function createPortfolioPostgresFixture(
  ownerType: "anonymous" | "user", ownerId: string,
): Promise<PGliteDatabase> {
  const db = await PGliteDatabase.create();
  databases.add(db);
  for (const file of [
    "0000_business_schema.sql", "0001_price_domain.sql", "0006_mutation_lock.sql",
    "0008_collection_item_grading_identity.sql", "0018_platform_account_isolation.sql",
  ]) {
    await db.exec(readFileSync(new URL(`../db/postgres/migrations/${file}`, import.meta.url), "utf8"));
  }
  await seedOwner(db, ownerType, ownerId);
  await db.prepare(`INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
    VALUES (?, ?, ?, ?, '2099-01-01T00:00:00.000Z', ?, 'ios', ?)`)
    .bind(`${ownerType}-${ownerId}-session`, ownerType, ownerId,
      `${ownerType}-${ownerId}-refresh`, createdAt, ownerType === "user" ? ownerId : null).run();
  return db;
}

export async function closePortfolioPostgresFixtures(): Promise<void> {
  for (const db of databases) await db.close();
  databases.clear();
}

export async function seedPortfolioRows(
  db: PGliteDatabase, table: string, ...rows: Record<string, unknown>[]
): Promise<void> {
  if (!tables.has(table)) throw new Error("Unknown Portfolio fixture table");
  for (const input of rows) {
    const ownerType = input.owner_type === "user" ? "user" : "anonymous";
    const ownerId = String(input.owner_id);
    await seedOwner(db, ownerType, ownerId);
    const row: Record<string, unknown> = {
      id: crypto.randomUUID(), created_at: createdAt, updated_at: createdAt,
      ...input,
    };
    if (table === "portfolio_folder") {
      Object.assign(row, { name: `Fixture ${row.id}`, is_default: 0, sort_order: 0 }, input);
    }
    if (table === "user_preference") {
      Object.assign(row, { currency: "USD", amount_hidden: 0, last_selected_folder_id: null }, input);
    }
    if (table === "collection_item" || table === "collection_item_event") {
      Object.assign(row, {
        object_type: "tcg", grader: "RAW", condition: null, grade: null,
        language: null, finish: null, quantity: 1,
        purchase_price: null, purchase_currency: null,
      }, input);
      if (table === "collection_item") {
        row.folder_id ??= `fixture-folder-${ownerId}`;
        const folderExists = await db.prepare("SELECT id FROM portfolio_folder WHERE id = ?")
          .bind(row.folder_id).first();
        if (!folderExists) await seedPortfolioRows(db, "portfolio_folder", {
          id: row.folder_id, owner_type: ownerType, owner_id: ownerId,
        });
      }
      if (row.price_series_id != null) await seedPriceSeries(db, row);
    }
    const columns = (await db.query<{ column_name: string }>(
      "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1",
      [table],
    )).rows.map((value) => value.column_name);
    const entries = Object.entries(row).filter(([key, value]) => columns.includes(key) && value !== undefined);
    await db.prepare(`INSERT INTO ${table} (${entries.map(([key]) => key).join(", ")})
      VALUES (${entries.map(() => "?").join(", ")})`)
      .bind(...entries.map(([, value]) => value)).run();
  }
}

export async function readPortfolioRows<T>(
  db: PGliteDatabase, table: string, columns: string[],
): Promise<T[]> {
  if (!tables.has(table) || columns.some((value) => !/^[a-z_]+$/.test(value))) {
    throw new Error("Invalid Portfolio fixture projection");
  }
  return (await db.prepare(`SELECT ${columns.join(", ")} FROM ${table}`).all<T>()).results;
}

async function seedOwner(db: PGliteDatabase, type: "anonymous" | "user", id: string) {
  if (type === "anonymous") {
    await db.prepare(`INSERT INTO anonymous_account (id, device_id, created_at, platform, status)
      VALUES (?, ?, ?, 'ios', 'active') ON CONFLICT (id) DO NOTHING`)
      .bind(id, `fixture-device-${id}`, createdAt).run();
  } else {
    await db.prepare(`INSERT INTO "user" (id, email, created_at, updated_at)
      VALUES (?, ?, ?, ?) ON CONFLICT (id) DO NOTHING`)
      .bind(id, `${id}@fixture.invalid`, createdAt, createdAt).run();
    await db.prepare(`INSERT INTO platform_account
      (id, user_id, platform, status, created_at, updated_at)
      VALUES (?, ?, 'ios', 'active', ?, ?) ON CONFLICT (id) DO NOTHING`)
      .bind(id, id, createdAt, createdAt).run();
  }
}

async function seedPriceSeries(db: PGliteDatabase, row: Record<string, unknown>) {
  await db.prepare(`INSERT INTO cards_all (product_id, game_id)
    VALUES (?, 1) ON CONFLICT (product_id) DO NOTHING`).bind(row.card_ref).run();
  await db.exec(`INSERT INTO price_source
    (source_id, source_code, display_name, source_kind) OVERRIDING SYSTEM VALUE
    VALUES (1, 'fixture', 'Fixture', 'external') ON CONFLICT (source_id) DO NOTHING`);
  await db.prepare(`INSERT INTO price_series
    (series_id, source_id, source_record_id, metric_code, card_ref, currency_code, grader_code)
    OVERRIDING SYSTEM VALUE VALUES (?, 1, ?, 'market', ?, 'USD', ?)
    ON CONFLICT (series_id) DO NOTHING`)
    .bind(row.price_series_id, `fixture-${row.price_series_id}`, row.card_ref, row.grader).run();
}
