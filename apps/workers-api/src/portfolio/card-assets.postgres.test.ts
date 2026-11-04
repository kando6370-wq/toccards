import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { createPortfolioRoutes } from "./routes";

const JWT_SECRET = "card-assets-test";
const NOW = "2026-08-01T00:00:00.000Z";

describe("card-scoped owner assets on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("../db/postgres/migrations/0000_business_schema.sql", import.meta.url), "utf8"));
    await db.exec("ALTER TABLE collection_item ADD COLUMN price_series_id bigint");
    await db.exec(`
      INSERT INTO "user" (id, email, created_at, updated_at)
      VALUES ('owner-1', 'owner-1@example.com', '${NOW}', '${NOW}'),
             ('owner-2', 'owner-2@example.com', '${NOW}', '${NOW}');
      INSERT INTO anonymous_account (id, device_id, created_at)
      VALUES ('owner-1', 'device-1', '${NOW}');
      INSERT INTO session (id, owner_type, owner_id, refresh_token, expires_at, created_at)
      VALUES ('session-1', 'user', 'owner-1', 'refresh-1', '2099-01-01T00:00:00.000Z', '${NOW}');
      INSERT INTO portfolio_folder (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
      VALUES ('main', 'user', 'owner-1', 'Main', 1, 0, '${NOW}', '${NOW}'),
             ('other', 'user', 'owner-2', 'Other', 1, 0, '${NOW}', '${NOW}');
      INSERT INTO collection_item (id, owner_type, owner_id, folder_id, card_ref,
        object_type, grader, quantity, created_at, updated_at)
      VALUES ('owned-a', 'user', 'owner-1', 'main', 'card-a', 'tcg', 'Raw', 1, '${NOW}', '${NOW}'),
             ('owned-b', 'user', 'owner-1', 'main', 'card-b', 'tcg', 'Raw', 1, '${NOW}', '${NOW}'),
             ('other-owner', 'user', 'owner-2', 'other', 'card-a', 'tcg', 'Raw', 1, '${NOW}', '${NOW}'),
             ('same-id-anonymous', 'anonymous', 'owner-1', 'main', 'card-a', 'tcg', 'Raw', 1, '${NOW}', '${NOW}');
      INSERT INTO wishlist_item (id, owner_type, owner_id, card_ref, created_at)
      VALUES ('wish-a', 'user', 'owner-1', 'card-a', '${NOW}'),
             ('wish-b', 'user', 'owner-1', 'card-b', '${NOW}'),
             ('other-wish', 'user', 'owner-2', 'card-a', '${NOW}');
    `);
    token = await signAccessToken(
      { owner_type: "user", owner_id: "owner-1", session_id: "session-1" },
      JWT_SECRET,
    );
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
  });

  afterEach(async () => db.close());

  it("returns only the selected card while retaining all owner folders needed for Collect", async () => {
    const query = vi.spyOn(db, "query");
    const response = await createPortfolioRoutes().request(
      "/portfolio/cards/card-a/assets",
      { headers: { Authorization: `Bearer ${token}` } },
      env,
    );
    expect(response.status).toBe(200);
    const body = await response.json() as {
      data: { folders: Array<{ id: string }>; items: Array<{ id: string }>; wishlist_items: Array<{ id: string }> };
    };
    expect(body.data.folders.map((row) => row.id)).toEqual(["main"]);
    expect(body.data.items.map((row) => row.id)).toEqual(["owned-a"]);
    expect(body.data.wishlist_items.map((row) => row.id)).toEqual(["wish-a"]);
    const collectionQuery = query.mock.calls.find(([sql]) => sql.includes("FROM collection_item"));
    expect(collectionQuery?.[1]).toEqual(["user", "owner-1", "card-a"]);
  });

  it("returns an empty asset state for an unowned card and rejects missing auth", async () => {
    const route = createPortfolioRoutes();
    const missing = await route.request("/portfolio/cards/card-missing/assets", {
      headers: { Authorization: `Bearer ${token}` },
    }, env);
    expect(missing.status).toBe(200);
    expect((await missing.json() as { data: { items: unknown[]; wishlist_items: unknown[] } }).data)
      .toMatchObject({ items: [], wishlist_items: [] });
    expect((await route.request("/portfolio/cards/card-a/assets", {}, env)).status).toBe(401);
  });

  it("reads only requested cards for the authenticated owner in one batch", async () => {
    const query = vi.spyOn(db, "query");
    const route = createPortfolioRoutes();
    const response = await route.request(
      "/portfolio/cards/assets?card_ref=card-a&card_ref=card-b&card_ref=card-a&card_ref=card-missing",
      { headers: { Authorization: `Bearer ${token}` } },
      env,
    );
    expect(response.status).toBe(200);
    const body = await response.json() as {
      data: {
        folders: Array<{ id: string }>;
        items: Array<{ id: string; card_ref: string; quantity: number }>;
        wishlist_items: Array<{ id: string; card_ref: string }>;
      };
    };
    expect(body.data.folders.map((row) => row.id)).toEqual(["main"]);
    expect(body.data.items.map((row) => [row.id, row.card_ref, row.quantity]).sort())
      .toEqual([["owned-a", "card-a", 1], ["owned-b", "card-b", 1]]);
    expect(body.data.wishlist_items.map((row) => [row.id, row.card_ref]).sort())
      .toEqual([["wish-a", "card-a"], ["wish-b", "card-b"]]);
    const collectionQueries = query.mock.calls.filter(([sql]) => sql.includes("FROM collection_item"));
    const wishlistQueries = query.mock.calls.filter(([sql]) => sql.includes("FROM wishlist_item"));
    expect(collectionQueries).toHaveLength(1);
    expect(wishlistQueries).toHaveLength(1);
    expect(collectionQueries[0]?.[1]).toEqual(["user", "owner-1", "card-a", "card-b", "card-missing"]);
    expect(wishlistQueries[0]?.[1]).toEqual(["user", "owner-1", "card-a", "card-b", "card-missing"]);
  });

  it("rejects missing, blank and oversized batches without reading assets", async () => {
    const route = createPortfolioRoutes();
    const headers = { Authorization: `Bearer ${token}` };
    const overLimit = Array.from({ length: 101 }, (_, index) => `card_ref=card-${index}`).join("&");
    for (const path of [
      "/portfolio/cards/assets",
      "/portfolio/cards/assets?card_ref=%20",
      `/portfolio/cards/assets?${overLimit}`,
    ]) {
      expect((await route.request(path, { headers }, env)).status).toBe(422);
    }
    expect((await route.request("/portfolio/cards/assets?card_ref=card-a", {}, env)).status).toBe(401);
  });
});
