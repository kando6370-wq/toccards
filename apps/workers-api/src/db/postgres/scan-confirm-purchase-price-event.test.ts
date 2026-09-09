import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { PGliteDatabase } from "../../test-support/pglite-database";

const migration = readFileSync(
  new URL("./migrations/0012_scan_confirm_purchase_price_event.sql", import.meta.url),
  "utf8",
);

describe("PostgreSQL Scan confirmation purchase price event migration", () => {
  let db: PGliteDatabase;

  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec(`
      CREATE TABLE scan_record (
        id text PRIMARY KEY,
        owner_type text NOT NULL,
        owner_id text NOT NULL,
        user_confirmation_status text NOT NULL,
        user_result text NOT NULL
      );
      CREATE TABLE collection_item (
        id text PRIMARY KEY,
        owner_type text NOT NULL,
        owner_id text NOT NULL,
        purchase_price double precision,
        purchase_currency text,
        performance_history_available_from text,
        created_at text NOT NULL
      );
      CREATE TABLE collection_item_event (
        id text PRIMARY KEY,
        item_id text NOT NULL,
        owner_type text NOT NULL,
        owner_id text NOT NULL,
        purchase_price double precision,
        purchase_currency text,
        performance_history_available_from text,
        event_type text NOT NULL,
        effective_at text NOT NULL
      );
    `);
  });

  beforeEach(async () => {
    await db.exec("DELETE FROM collection_item_event; DELETE FROM collection_item; DELETE FROM scan_record;");
  });

  afterAll(async () => {
    await db?.close();
  });

  it("repairs only the initial event created by Scan confirmation and remains idempotent", async () => {
    await db.exec(`
      INSERT INTO scan_record VALUES
        ('scan-1', 'user', 'user-1', 'confirmed',
         '{"added_to_inventory":true,"collection_item_id":"scan-item"}');

      INSERT INTO collection_item VALUES
        ('scan-item', 'user', 'user-1', 42.5, 'USD', NULL,
         '2026-09-01T00:00:00.000Z'),
        ('regular-item', 'user', 'user-1', 18, 'USD', NULL,
         '2026-09-01T00:00:00.000Z');

      INSERT INTO collection_item_event VALUES
        ('scan-initial', 'scan-item', 'user', 'user-1', NULL, NULL, NULL,
         'upsert', '2026-09-01T00:00:00.000Z'),
        ('scan-later', 'scan-item', 'user', 'user-1', NULL, NULL, NULL,
         'upsert', '2026-09-02T00:00:00.000Z'),
        ('regular-initial', 'regular-item', 'user', 'user-1', NULL, NULL, NULL,
         'upsert', '2026-09-01T00:00:00.000Z');
    `);

    await db.exec(migration);
    await db.exec(migration);

    const rows = (await db.query<{
      id: string;
      purchase_price: number | null;
      purchase_currency: string | null;
      performance_history_available_from: string | null;
    }>(`
      SELECT id, purchase_price, purchase_currency, performance_history_available_from
      FROM collection_item_event
      ORDER BY id
    `)).rows;

    expect(rows).toEqual([
      {
        id: "regular-initial",
        purchase_price: null,
        purchase_currency: null,
        performance_history_available_from: null,
      },
      {
        id: "scan-initial",
        purchase_price: 42.5,
        purchase_currency: "USD",
        performance_history_available_from: "2026-09-01T00:00:00.000Z",
      },
      {
        id: "scan-later",
        purchase_price: null,
        purchase_currency: null,
        performance_history_available_from: null,
      },
    ]);
  });
});
