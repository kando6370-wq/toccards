import { signAccessToken } from "@kando/auth-core";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Env } from "../env";
import {
  mutationLockKey,
  ownerCardMutationLockKey,
} from "../db/mutation-lock";
import { createScanRoutes } from "../scan/routes";
import { createPortfolioRoutes } from "./routes";

const JWT_SECRET = "owner-card-concurrency-test";
const CARD_REF = "card-race";

describe("Wishlist and Portfolio concurrency", () => {
  let mf: Miniflare;
  let db: D1Database;
  let env: Env;
  let token: string;

  beforeEach(async () => {
    mf = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    db = await mf.getD1Database("DB");
    for (const statement of SCHEMA) await db.prepare(statement).run();
    await db.batch([
      db.prepare("INSERT INTO user (id, status) VALUES ('user-1', 'active')"),
      db.prepare("INSERT INTO session (id, owner_type, owner_id, expires_at, revoked_at) VALUES ('session-1', 'user', 'user-1', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO portfolio_folder (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at) VALUES ('main', 'user', 'user-1', 'Main', 1, 0, '2026-08-18T00:00:00.000Z', '2026-08-18T00:00:00.000Z')"),
    ]);
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
    token = await signAccessToken(
      { owner_type: "user", owner_id: "user-1", session_id: "session-1" },
      JWT_SECRET,
    );
  });

  afterEach(async () => {
    await mf.dispose();
  });

  it("keeps Quick Collect mutually exclusive with Wishlist because ownership supersedes wanted intent", async () => {
    const portfolio = createPortfolioRoutes();
    const [wishlistResponse, collectResponse] = await Promise.all([
      addWishlist(portfolio),
      quickCollect(portfolio),
    ]);

    expect(collectResponse.status).toBe(201);
    expect([201, 409]).toContain(wishlistResponse.status);
    await expect(cardCounts()).resolves.toEqual({ collection: 1, wishlist: 0 });
    await expectLock(ownerCardMutationLockKey(owner(), CARD_REF));
  });

  it("keeps full Portfolio Create mutually exclusive with Wishlist because every write path shares the owner-card lock", async () => {
    const portfolio = createPortfolioRoutes();
    const [wishlistResponse, createResponse] = await Promise.all([
      addWishlist(portfolio),
      createPortfolioItem(portfolio),
    ]);

    expect(createResponse.status).toBe(201);
    expect([201, 409]).toContain(wishlistResponse.status);
    await expect(cardCounts()).resolves.toEqual({ collection: 1, wishlist: 0 });
    await expectLock(ownerCardMutationLockKey(owner(), CARD_REF));
  });

  it("keeps Scan Confirm mutually exclusive with Wishlist because scan additions obey the same ownership invariant", async () => {
    await db.prepare(`
      INSERT INTO scan_record
        (id, owner_type, owner_id, filename, platform, app_version,
         recognition_status, user_confirmation_status, system_result,
         user_result, candidates, raw_response, created_at)
      VALUES ('scan-1', 'user', 'user-1', 'scan.jpg', 'iOS', '1.0.0',
        'success', 'pending', '{}', '{}', ?, '{}', '2026-08-18T00:00:00.000Z')
    `).bind(JSON.stringify([{ card_ref: CARD_REF, name: "Concurrent Card" }])).run();
    const portfolio = createPortfolioRoutes();
    const scan = createScanRoutes();
    const [wishlistResponse, confirmResponse] = await Promise.all([
      addWishlist(portfolio),
      scan.request("/scan/scan-1/confirm", requestOptions(itemDraft()), env),
    ]);

    expect(confirmResponse.status).toBe(201);
    expect([201, 409]).toContain(wishlistResponse.status);
    await expect(cardCounts()).resolves.toEqual({ collection: 1, wishlist: 0 });
    await expectLock(ownerCardMutationLockKey(owner(), CARD_REF));
    await expectLock(mutationLockKey("scan-confirm", "user:user-1:scan-1"));
  });

  it("commits only one card when the same scan is concurrently confirmed with different candidates", async () => {
    const otherCardRef = "card-race-other";
    await db.batch([
      db.prepare(`
        INSERT INTO scan_record
          (id, owner_type, owner_id, filename, platform, app_version,
           recognition_status, user_confirmation_status, system_result,
           user_result, candidates, raw_response, created_at)
        VALUES ('scan-1', 'user', 'user-1', 'scan.jpg', 'iOS', '1.0.0',
          'success', 'pending', '{}', '{}', ?, '{}', '2026-08-18T00:00:00.000Z')
      `).bind(JSON.stringify([
        { card_ref: CARD_REF, name: "First Candidate" },
        { card_ref: otherCardRef, name: "Second Candidate" },
      ])),
      db.prepare(`
        INSERT INTO wishlist_item (id, owner_type, owner_id, card_ref, created_at)
        VALUES ('wish-a', 'user', 'user-1', ?, '2026-08-18T00:00:00.000Z')
      `).bind(CARD_REF),
      db.prepare(`
        INSERT INTO wishlist_item (id, owner_type, owner_id, card_ref, created_at)
        VALUES ('wish-b', 'user', 'user-1', ?, '2026-08-18T00:00:00.000Z')
      `).bind(otherCardRef),
    ]);
    const scan = createScanRoutes();

    const responses = await Promise.all([
      scan.request("/scan/scan-1/confirm", requestOptions(itemDraft(true, CARD_REF)), env),
      scan.request("/scan/scan-1/confirm", requestOptions(itemDraft(true, otherCardRef)), env),
    ]);

    expect(responses.map((response) => response.status).sort()).toEqual([201, 409]);
    await expect(count("collection_item")).resolves.toBe(1);
    await expect(count("collection_item_event")).resolves.toBe(1);
    await expect(count("wishlist_item")).resolves.toBe(1);
    await expect(db.prepare(
      "SELECT user_confirmation_status FROM scan_record WHERE id = 'scan-1'",
    ).first<string>("user_confirmation_status")).resolves.toBe("confirmed");
    await expectLock(mutationLockKey("scan-confirm", "user:user-1:scan-1"));
  });

  async function addWishlist(app: ReturnType<typeof createPortfolioRoutes>): Promise<Response> {
    return await app.request(
      "/wishlist",
      requestOptions({ card_ref: CARD_REF }),
      env,
    );
  }

  async function quickCollect(app: ReturnType<typeof createPortfolioRoutes>): Promise<Response> {
    return await app.request(
      `/cards/${CARD_REF}/collect`,
      requestOptions(itemDraft(false)),
      env,
    );
  }

  async function createPortfolioItem(app: ReturnType<typeof createPortfolioRoutes>): Promise<Response> {
    return await app.request(
      "/portfolio/items",
      requestOptions(itemDraft()),
      env,
    );
  }

  function requestOptions(body: Record<string, unknown>) {
    return {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    };
  }

  async function cardCounts(): Promise<{ collection: number; wishlist: number }> {
    const [collection, wishlist] = await Promise.all([
      db.prepare("SELECT COUNT(*) AS total FROM collection_item WHERE card_ref = ?")
        .bind(CARD_REF).first<number>("total"),
      db.prepare("SELECT COUNT(*) AS total FROM wishlist_item WHERE card_ref = ?")
        .bind(CARD_REF).first<number>("total"),
    ]);
    return { collection: collection ?? 0, wishlist: wishlist ?? 0 };
  }

  async function count(table: string): Promise<number> {
    return await db.prepare(`SELECT COUNT(*) AS total FROM ${table}`)
      .first<number>("total") ?? 0;
  }

  async function expectLock(expected: Promise<string>): Promise<void> {
    const lockKey = await expected;
    await expect(db.prepare(
      "SELECT COUNT(*) AS total FROM mutation_lock WHERE lock_key = ?",
    ).bind(lockKey).first<number>("total")).resolves.toBe(1);
  }
});

function owner() {
  return { owner_type: "user", owner_id: "user-1" };
}

function itemDraft(
  includeCardRef = true,
  cardRef = CARD_REF,
): Record<string, unknown> {
  return {
    folder_id: "main",
    ...(includeCardRef ? { card_ref: cardRef } : {}),
    object_type: "tcg",
    grader: "Raw",
    condition: "Near Mint (NM)",
    grade: null,
    language: "English",
    finish: "Normal",
    quantity: 1,
    purchase_price: null,
    purchase_currency: null,
    notes: null,
  };
}

const SCHEMA = [
  "CREATE TABLE mutation_lock (lock_key TEXT PRIMARY KEY)",
  "CREATE TABLE user (id TEXT PRIMARY KEY, status TEXT NOT NULL)",
  "CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, expires_at TEXT NOT NULL, revoked_at TEXT)",
  "CREATE TABLE portfolio_folder (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, name TEXT NOT NULL, is_default INTEGER NOT NULL, sort_order INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(owner_type, owner_id, name))",
  "CREATE TABLE collection_item (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, folder_id TEXT NOT NULL, card_ref TEXT NOT NULL, object_type TEXT NOT NULL, grader TEXT NOT NULL, condition TEXT, grade REAL, language TEXT, finish TEXT, price_series_id INTEGER, quantity INTEGER NOT NULL, purchase_price REAL, purchase_currency TEXT, performance_start_at TEXT, purchase_price_effective_at TEXT, performance_history_available_from TEXT, notes TEXT, folder_joined_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
  "CREATE UNIQUE INDEX uq_collection_item_sku ON collection_item (owner_type, owner_id, folder_id, card_ref, ifnull(finish, ''), ifnull(language, ''))",
  "CREATE TABLE collection_item_event (id TEXT PRIMARY KEY, item_id TEXT NOT NULL, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, folder_id TEXT NOT NULL, card_ref TEXT NOT NULL, object_type TEXT NOT NULL, grader TEXT NOT NULL, condition TEXT, grade REAL, language TEXT, finish TEXT, price_series_id INTEGER, quantity INTEGER NOT NULL, purchase_price REAL, purchase_currency TEXT, performance_history_available_from TEXT, event_type TEXT NOT NULL, effective_at TEXT NOT NULL)",
  "CREATE TABLE wishlist_item (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, card_ref TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(owner_type, owner_id, card_ref))",
  "CREATE TABLE scan_record (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, image_url TEXT, filename TEXT NOT NULL, platform TEXT NOT NULL, app_version TEXT NOT NULL, device_model TEXT, os_version TEXT, recognition_status TEXT NOT NULL, user_confirmation_status TEXT NOT NULL, modified_result INTEGER NOT NULL DEFAULT 0, system_result TEXT NOT NULL, user_result TEXT NOT NULL, candidates TEXT NOT NULL, raw_response TEXT NOT NULL, created_at TEXT NOT NULL)",
];
