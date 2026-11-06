import { signAccessToken } from "@kando/auth-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { createPortfolioRoutes } from "./routes";

const JWT_SECRET = "portfolio-pagination-test";
const NOW = "2026-08-01T00:00:00.000Z";

describe("Portfolio item PostgreSQL pagination", () => {
  let db: PGliteDatabase;
  let env: Env;
  let token: string;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(`
      CREATE TABLE "user" (id text PRIMARY KEY, status text NOT NULL);
      CREATE TABLE platform_account (id text PRIMARY KEY, user_id text NOT NULL, platform text NOT NULL, status text NOT NULL);
      CREATE TABLE anonymous_account (id text PRIMARY KEY, upgraded_user_id text, platform text NOT NULL, status text NOT NULL);
      CREATE TABLE session (
        id text PRIMARY KEY, owner_type text NOT NULL, owner_id text NOT NULL,
        platform text, user_id text, expires_at text NOT NULL, revoked_at text
      );
      CREATE TABLE collection_item (
        id text PRIMARY KEY, owner_type text NOT NULL, owner_id text NOT NULL,
        folder_id text NOT NULL, card_ref text NOT NULL, object_type text NOT NULL,
        grader text NOT NULL, condition text, grade numeric, language text,
        finish text, price_series_id bigint, quantity integer NOT NULL,
        purchase_price numeric, purchase_currency text, performance_start_at text,
        purchase_price_effective_at text, performance_history_available_from text,
        notes text, folder_joined_at text, created_at text NOT NULL,
        updated_at text NOT NULL
      );
      INSERT INTO "user" VALUES ('owner-1', 'active'), ('owner-2', 'active');
      INSERT INTO platform_account VALUES ('owner-1', 'owner-1', 'ios', 'active'), ('owner-2', 'owner-2', 'ios', 'active');
      INSERT INTO anonymous_account VALUES ('anon-1', NULL, 'ios', 'active'), ('owner-1', NULL, 'ios', 'active');
      INSERT INTO session VALUES
        ('session-1', 'user', 'owner-1', 'ios', 'owner-1', '2099-01-01T00:00:00.000Z', NULL),
        ('session-anon', 'anonymous', 'anon-1', 'ios', NULL, '2099-01-01T00:00:00.000Z', NULL),
        ('session-anon-same', 'anonymous', 'owner-1', 'ios', NULL, '2099-01-01T00:00:00.000Z', NULL);
    `);
    for (const [id, ownerId, folderId, cardRef, createdAt, updatedAt, joinedAt] of [
      ["item-b", "owner-1", "main", "card-2", "2026-01-02T00:00:00.000Z", "2026-02-01T00:00:00.000Z", NOW],
      ["item-a", "owner-1", "main", "card-1", "2026-01-02T00:00:00.000Z", "2026-02-02T00:00:00.000Z", NOW],
      ["item-c", "owner-1", "trade", "card-3", "2026-01-03T00:00:00.000Z", "2026-02-03T00:00:00.000Z", null],
      ["item-d", "owner-1", "main", "card-4", "2026-01-04T00:00:00.000Z", "2026-02-04T00:00:00.000Z", NOW],
      ["item-e", "owner-2", "main", "card-0", "2026-01-05T00:00:00.000Z", "2026-02-05T00:00:00.000Z", NOW],
    ]) {
      await db.prepare(`
        INSERT INTO collection_item (
          id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
          quantity, folder_joined_at, created_at, updated_at
        ) VALUES (?, 'user', ?, ?, ?, 'tcg', 'Raw', 1, ?, ?, ?)
      `).bind(id, ownerId, folderId, cardRef, joinedAt, createdAt, updatedAt).run();
    }
    await db.prepare(`
      INSERT INTO collection_item (
        id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
        quantity, created_at, updated_at
      ) VALUES
        ('item-anon', 'anonymous', 'anon-1', 'main', 'card-anon',
          'tcg', 'Raw', 1, '2026-03-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z'),
        ('item-anon-same', 'anonymous', 'owner-1', 'main', 'card-anon-same',
          'tcg', 'Raw', 1, '2026-03-01T00:00:00.000Z', '2026-03-01T00:00:00.000Z')
    `).run();
    token = await signAccessToken(
      { owner_type: "user", owner_id: "owner-1", session_id: "session-1" },
      JWT_SECRET,
    );
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
  });

  afterEach(async () => db.close());

  it("lists paged owner-isolated items and reads only the requested PostgreSQL page", async () => {
    const prepare = vi.spyOn(db, "prepare");
    const query = vi.spyOn(db, "query");
    const first = await request("?folder_id=main&page=1&page_size=1&sort_by=created_at&sort_order=desc");
    expect(first.data.items.map((item) => item.id)).toEqual(["item-d"]);
    expect(first.data.items[0]).toEqual({
      id: "item-d", folder_id: "main", card_ref: "card-4", object_type: "tcg",
      grader: "Raw", condition: null, grade: null, language: null, finish: null,
      quantity: 1, purchase_price: null, purchase_currency: null, notes: null,
      created_at: "2026-01-04T00:00:00.000Z",
      updated_at: "2026-02-04T00:00:00.000Z",
    });
    expect(first.data.total).toBe(3);
    expect(first.data.page_size).toBe(1);

    const itemQueries = prepare.mock.calls.filter(([sql]) => sql.includes("FROM collection_item"));
    expect(itemQueries, "total and items must share one PostgreSQL statement snapshot").toHaveLength(1);
    const pageQueryIndex = query.mock.calls.findIndex(([sql]) => sql.includes("FROM collection_item"));
    const pageResult = await query.mock.results[pageQueryIndex]!.value;
    expect(pageResult.rows).toHaveLength(1);

    const anonymousToken = await signAccessToken(
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-anon" },
      JWT_SECRET,
    );
    const anonymous = await request("?page_size=1", anonymousToken);
    expect(anonymous.data.items.map((item) => item.id)).toEqual(["item-anon"]);
    expect(anonymous.data.total).toBe(1);
    const sameIdToken = await signAccessToken(
      { owner_type: "anonymous", owner_id: "owner-1", session_id: "session-anon-same" },
      JWT_SECRET,
    );
    const sameIdAnonymous = await request("?page_size=1", sameIdToken);
    expect(sameIdAnonymous.data.items.map((item) => item.id)).toEqual(["item-anon-same"]);
    expect(sameIdAnonymous.data.total).toBe(1);
  });

  it.each([
    ["folder_joined_at", "asc", ["item-c", "item-a", "item-b", "item-d"]],
    ["created_at", "desc", ["item-d", "item-c", "item-a", "item-b"]],
    ["updated_at", "asc", ["item-b", "item-a", "item-c", "item-d"]],
    ["card_ref", "desc", ["item-d", "item-c", "item-b", "item-a"]],
  ])("keeps %s %s order and stable page boundaries", async (sortBy, sortOrder, ids) => {
    const pages = [];
    for (let page = 1; page <= 5; page++) {
      const result = await request(`?page=${page}&page_size=1&sort_by=${sortBy}&sort_order=${sortOrder}`);
      expect(result.data.total).toBe(4);
      pages.push(...result.data.items.map((item) => item.id));
    }
    expect(pages).toEqual(ids);
  });

  it("uses id as a stable tie-breaker because equal timestamps must not skip items across pages", async () => {
    const first = await request("?page=3&page_size=1&sort_by=created_at&sort_order=desc");
    const second = await request("?page=4&page_size=1&sort_by=created_at&sort_order=desc");
    expect(first.data.items.map((item) => item.id)).toEqual(["item-a"]);
    expect(second.data.items.map((item) => item.id)).toEqual(["item-b"]);
  });

  it("sorts by current-folder join time because moved assets precede older entries", async () => {
    await db.prepare(`
      INSERT INTO collection_item (
        id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
        quantity, folder_joined_at, created_at, updated_at
      ) VALUES
        ('created-later', 'user', 'owner-1', 'trade', 'card-6', 'tcg', 'Raw', 1,
          '2026-07-10T00:00:00.000Z', '2026-07-10T00:00:00.000Z', '2026-07-10T00:00:00.000Z'),
        ('moved-later', 'user', 'owner-1', 'trade', 'card-7', 'tcg', 'Raw', 1,
          '2026-07-15T00:00:00.000Z', '2026-07-01T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
    `).run();
    const result = await request("?folder_id=trade&page_size=10");
    expect(result.data.items.map((item) => item.id)).toEqual([
      "moved-later", "created-later", "item-c",
    ]);
  });

  it("preserves default order, capped page size, and empty-page total", async () => {
    const first = await request("?page_size=500");
    expect(first.data.page_size).toBe(100);
    expect(first.data.items.map((item) => item.id)).toEqual(["item-a", "item-b", "item-d", "item-c"]);
    const empty = await request("?folder_id=missing&page=2&page_size=1");
    expect(empty.data).toMatchObject({ items: [], total: 0, page: 2, page_size: 1 });
    const beyondLastPage = await request("?page=99&page_size=1");
    expect(beyondLastPage.data).toMatchObject({ items: [], total: 4, page: 99, page_size: 1 });
  });

  it("keeps C collation stable across pages for mixed-case and non-ASCII card refs and id ties", async () => {
    const rows = [
      ["dash", "-"], ["upper", "A"], ["underscore", "_"],
      ["lower", "a"], ["plain", "e"], ["case-B", "same"],
      ["case-a", "same"], ["accent", "\u00e9"], ["han", "\u4e2d"],
    ];
    for (const [id, cardRef] of rows) {
      await db.prepare(`
        INSERT INTO collection_item (
          id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
          quantity, created_at, updated_at
        ) VALUES (?, 'user', 'owner-1', 'collation', ?, 'tcg', 'Raw', 1, ?, ?)
      `).bind(id, cardRef, NOW, NOW).run();
    }

    const ascending = [];
    const descending = [];
    for (let page = 1; page <= rows.length; page++) {
      const asc = await request(`?folder_id=collation&page=${page}&page_size=1&sort_by=card_ref&sort_order=asc`);
      const desc = await request(`?folder_id=collation&page=${page}&page_size=1&sort_by=card_ref&sort_order=desc`);
      ascending.push(...asc.data.items.map((item) => item.id));
      descending.push(...desc.data.items.map((item) => item.id));
    }
    expect(ascending).toEqual([
      "dash", "upper", "underscore", "lower", "plain", "case-B", "case-a", "accent", "han",
    ]);
    expect(descending).toEqual([
      "han", "accent", "case-B", "case-a", "plain", "lower", "underscore", "upper", "dash",
    ]);
  });

  async function request(query = "", authToken = token) {
    const response = await createPortfolioRoutes().request(
      `/portfolio/items${query}`,
      { headers: { Authorization: `Bearer ${authToken}` } },
      env,
    );
    expect(response.status).toBe(200);
    const body = await response.json() as {
      success: boolean;
      data: {
        items: Array<{ id: string }>;
        total: number;
        page: number;
        page_size: number;
      };
    };
    expect(body.success).toBe(true);
    return body;
  }
});
