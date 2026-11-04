import { signAccessToken } from "@kando/auth-core";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

import { app } from "../app";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";

const directory = path.dirname(fileURLToPath(import.meta.url));
const secret = "local-compatibility-fixture-only";
const folderId = "11111111-1111-4111-8111-111111111111";
const reservationId = "22222222-2222-4222-8222-222222222222";
const cases: Record<string, unknown> = {};
const cached = new Map<string, string>();
const cache = {
  async get(key: string) { return cached.get(key) ?? null; },
  async put(key: string, value: string) { cached.set(key, value); },
} as unknown as KVNamespace;
const externalFetch = vi.fn<typeof fetch>();
let db: PGliteDatabase;
let ownerToken: string;
let otherToken: string;

function env(environment: Env["APP_ENVIRONMENT"] = "production"): Env {
  return {
    DB: db, JWT_SECRET: secret, APP_ENVIRONMENT: environment,
    CACHE_KV: cache,
  };
}

async function call<T = Record<string, any>>(name: string, route: string, status: number, options: {
  method?: string; body?: unknown; token?: string; headers?: Record<string, string>;
  environment?: Env["APP_ENVIRONMENT"];
} = {}) {
  const method = options.method ?? "GET";
  const response = await app.request("/api/v1" + route, {
    method,
    headers: {
      ...(options.token ? { Authorization: "Bearer " + options.token } : {}),
      ...(options.body === undefined ? {} : { "Content-Type": "application/json" }),
      ...options.headers,
    },
    ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
  }, env(options.environment));
  const contentType = response.headers.get("Content-Type") ?? "";
  const body = (contentType.includes("application/json") ? await response.json() : await response.text()) as T;
  expect(response.status, name).toBe(status);
  expect(response.headers.get("X-Request-ID"), name).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
  cases[name] = { method, route, requestBody: options.body ?? null, status, body, contentType };
  return { response, body };
}

async function versionRule(environment: string, platform: string, latest: string, enabled = true) {
  await db.prepare("INSERT INTO app_config (key,value,updated_at) VALUES (?,?,?) ON CONFLICT (key) DO UPDATE SET value = excluded.value")
    .bind("admin.app_version." + environment + "." + platform, JSON.stringify({
      min_supported_version: "1.0.4", recommended_version: latest, force_update: true,
      status: enabled ? "enabled" : "disabled",
      store_url: platform === "ios" ? "https://apps.apple.com/app/id6793017224" : "https://play.google.com/store/apps/details?id=com.cardai.tcg",
    }), "2026-10-09").run();
}

describe("frozen App contracts against current PostgreSQL-backed API", () => {
  beforeAll(async () => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    cached.clear();
    externalFetch.mockRejectedValue(new Error("External HTTP is unavailable in the contract fixture"));
    vi.stubGlobal("fetch", externalFetch);
    db = await PGliteDatabase.create();
    for (const name of ["0000_business_schema.sql", "0001_price_domain.sql", "0003_price_history_visibility_guard.sql", "0004_price_history_month_payload_limit.sql", "0006_mutation_lock.sql"]) {
      await db.exec(readFileSync(path.join(directory, "../db/postgres/migrations", name), "utf8"));
    }
    for (const id of ["compat-owner", "compat-other"]) {
      await db.prepare("INSERT INTO anonymous_account (id,device_id,created_at) VALUES (?,?,?)").bind(id, id + "-device", "2026-10-09").run();
      await db.prepare("INSERT INTO session (id,owner_type,owner_id,refresh_token,expires_at,created_at) VALUES (?,'anonymous',?,?,?,?)")
        .bind(id + "-session", id, id + "-refresh", "2099-01-01T00:00:00.000Z", "2026-10-09").run();
    }
    await db.exec(`
      INSERT INTO games (game_id, name, load, search_sort) VALUES
        (25, 'Pokemon', 1, 1), (26, 'Hidden game', 0, 0), (27, ' ', 1, 0);
      INSERT INTO sets (set_id, game, name, set_code, total_cards, set_image_id)
        VALUES ('0010', 'Pokemon', 'Contract Set', 'C03', 41, '0001');
      -- Distinct creation times keep these page boundaries independent of ID tie-breakers.
      INSERT INTO cards_all (product_id, game_id, game, set_name, set_code, set_id, name, number, product_type_name, created_at, updated_at)
        SELECT lpad(value::text, 4, '0'), 25, 'Pokemon', 'Contract Set', 'C03', '0010',
          'Contract Card ' || lpad(value::text, 2, '0'), lpad(value::text, 2, '0'), 'Cards',
          to_char(timestamp '2026-10-12' + value * interval '1 second', 'YYYY-MM-DD HH24:MI:SS'), '2026-10-12'
        FROM generate_series(1, 41) AS card(value);
      CREATE TABLE price_current_snapshot_contract PARTITION OF price_current_snapshot FOR VALUES IN (1, 2);
      CREATE TABLE price_history_month_contract PARTITION OF price_history_month
        FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
      INSERT INTO price_source (source_id, source_code, display_name, source_kind)
        OVERRIDING SYSTEM VALUE VALUES (1, 'tcgplayer', 'Contract source', 'external');
      INSERT INTO price_series (series_id, source_id, source_record_id, metric_code, card_ref, currency_code,
        condition_code, condition_name, language_code, language_name, finish_code, finish_name, grader_code)
        OVERRIDING SYSTEM VALUE VALUES
        (1, 1, 'contract-zero', 'market', '0001', 'USD', 'NM', 'Near Mint', 'EN', 'English', 'N', 'Normal', 'RAW'),
        (2, 1, 'contract-unpublished', 'market', '0002', 'USD', 'NM', 'Near Mint', 'EN', 'English', 'N', 'Normal', 'RAW');
      INSERT INTO price_ingest_batch (batch_id, scope_code, source_id, business_date, idempotency_key, input_object_key,
        input_checksum_sha256, content_checksum_sha256, expected_series_count, loaded_series_count,
        distinct_series_count, status, validated_at)
        OVERRIDING SYSTEM VALUE VALUES
        (1, 'current:tcgplayer', 1, '2026-10-12', 'contract-published', 'contract/1', repeat('a',64), repeat('b',64), 1, 1, 1, 'validated', now()),
        (2, 'current:tcgplayer', 1, '2026-10-13', 'contract-loading', 'contract/2', repeat('a',64), NULL, 2, 2, 2, 'loading', NULL);
      INSERT INTO price_current_snapshot (batch_id, series_id, observed_on, amount_micros, baseline_7d_on, baseline_7d_amount_micros)
        VALUES (1, 1, '2026-10-12', 0, '2026-10-05', 1500000);
      INSERT INTO price_current_snapshot (batch_id, series_id, observed_on, amount_micros)
        VALUES (2, 1, '2026-10-13', 99000000), (2, 2, '2026-10-13', 88000000);
      BEGIN;
      INSERT INTO price_history_month (series_id, month_start, points, point_count, first_observed_on,
        last_observed_on, content_checksum_sha256, last_batch_id)
        VALUES (1, '2026-10-01', '[{"d":"2026-10-01","a":2000000},{"d":"2026-10-05","a":1500000}]',
          2, '2026-10-01', '2026-10-05', repeat('c',64), 1);
      UPDATE price_ingest_batch SET status = 'published', published_at = now() WHERE batch_id = 1;
      INSERT INTO current_price_pointer (scope_code, batch_id, updated_by) VALUES ('current:tcgplayer', 1, 'contract');
      COMMIT;
    `);
    ownerToken = await signAccessToken({ owner_type: "anonymous", owner_id: "compat-owner", session_id: "compat-owner-session" }, secret);
    otherToken = await signAccessToken({ owner_type: "anonymous", owner_id: "compat-other", session_id: "compat-other-session" }, secret);
  }, 30_000);
  afterAll(async () => {
    await db?.close();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    if (process.env.APP_COMPATIBILITY_OUTPUT) {
      writeFileSync(process.env.APP_COMPATIBILITY_OUTPUT, JSON.stringify({ schemaVersion: 1, producer: "current-hono-api", cases }, null, 2), { flag: "wx" });
    }
  });

  it("C01 preserves old upgrade fields and isolates platform/environment rather than forcing old builds out", async () => {
    await versionRule("production", "ios", "1.0.4");
    await versionRule("production", "google", "1.0.4", false);
    await versionRule("development", "ios", "2.0.0");
    const ios = await call("config-ios", "/app-config?platform=ios", 200);
    expect(ios.body.data.upgrade_prompt).toMatchObject({ latest_version: "1.0.4", min_version: "1.0.4", force_update: true, title: expect.any(String), message: expect.any(String), forced_message: expect.any(String) });
    expect(ios.body.data.upgrade_prompt.title.trim()).not.toBe("");
    expect(ios.response.headers.get("Cache-Control")).toBe("no-store");
    const google = await call("config-google", "/app-config?platform=google", 200);
    expect(google.body.data.upgrade_prompt).toBeNull();
    expect(google.body.data.app_store_url).toContain("play.google.com");
    const development = await call("config-development", "/app-config?platform=ios", 200, { environment: "development" });
    expect(development.body.data.upgrade_prompt.latest_version).toBe("2.0.0");
    await versionRule("production", "ios", "1.0.5");
    const newer = await call("config-recommended", "/app-config?platform=ios", 200);
    expect(newer.body.data.upgrade_prompt.min_version).toBe("1.0.4");
  });

  it("C02/C09 keeps unauthenticated errors independent of optional request IDs", async () => {
    const legacy = await call("folders-unauthorized", "/portfolio/folders", 401);
    const invalid = await call("folders-invalid-request-id", "/portfolio/folders", 401, { headers: { "X-Request-ID": "old-client-non-uuid" } });
    const valid = await call("folders-valid-request-id", "/portfolio/folders", 401, { headers: { "X-Request-ID": reservationId } });
    expect(invalid.body).toEqual(legacy.body);
    expect(valid.body).toEqual(legacy.body);
    expect(valid.response.headers.get("X-Request-ID")).toBe(reservationId);
    expect(legacy.body.error.code).toBe("UNAUTHORIZED");
  });

  it("C04/C13 preserves a new writer's folder for old list/rename/delete operations without crossing owners", async () => {
    const create = { method: "POST", token: ownerToken, body: { name: "Shared collection" }, headers: { "Idempotency-Key": folderId } };
    const created = await call("folder-created", "/portfolio/folders", 201, create);
    expect(created.body.data).toMatchObject({ id: folderId, name: "Shared collection", is_default: false });
    const replay = await call("folder-replay", "/portfolio/folders", 200, create);
    expect(replay.body).toEqual(created.body);
    await call("folder-conflict", "/portfolio/folders", 409, { ...create, body: { name: "Different operation" } });
    const oldRead = await call("folders-new-write", "/portfolio/folders", 200, { token: ownerToken });
    expect(oldRead.body.data.items).toHaveLength(1);
    await call("folder-foreign-rename", "/portfolio/folders/" + folderId, 404, { method: "PATCH", token: otherToken, body: { name: "Old client edit" } });
    const renamed = await call("folder-old-rename", "/portfolio/folders/" + folderId, 200, { method: "PATCH", token: ownerToken, body: { name: "Old client edit" } });
    expect(renamed.body.data.name).toBe("Old client edit");
    const newRead = await call("folders-after-old-edit", "/portfolio/folders", 200, { token: ownerToken });
    expect(newRead.body.data.items[0].name).toBe("Old client edit");
    await call("folder-old-delete", "/portfolio/folders/" + folderId, 200, { method: "DELETE", token: ownerToken });
    expect((await call("folders-after-old-delete", "/portfolio/folders", 200, { token: ownerToken })).body.data.items).toEqual([]);
    expect(await db.prepare("SELECT count(*) AS count FROM portfolio_folder").first<number>("count")).toBe(0);
  });

  it("C03 keeps public catalog IDs and page boundaries without hiding unavailable prices", async () => {
    const games = await call("catalog-games", "/games", 200);
    expect(games.body.data.items).toEqual([{ id: "25", name: "Pokemon" }]);
    const sets = await call("catalog-sets", "/sets/search?q=&game=Pokemon&page=1&page_size=40", 200);
    expect(sets.body.data.items).toMatchObject([{ set_id: "0010", set_code: "C03", card_count: 41 }]);
    const legacySets = await call("catalog-sets-legacy", "/sets/search?q=Contract&game=Pokemon&page_size=40", 200);
    expect(legacySets.body.data.items).toMatchObject([{ set_id: "0010", set_code: "C03", card_count: 41 }]);
    const first = await call("catalog-page-1", "/cards/search?q=Contract%20Card&game=Pokemon&page=1&page_size=40", 200);
    expect(first.body.data.items.map((item: { card_ref: string }) => item.card_ref))
      .toEqual(Array.from({ length: 40 }, (_, index) => String(41 - index).padStart(4, "0")));
    expect(first.body.data.items[39].price_usd).toBeUndefined();
    const second = await call("catalog-page-2", "/cards/search?q=Contract%20Card&game=Pokemon&page=2&page_size=40", 200);
    expect(second.body.data).toMatchObject({ page: 2, page_size: 40, items: [{ card_ref: "0001", price_usd: 0 }] });
    const end = await call("catalog-page-3", "/cards/search?q=Contract%20Card&game=Pokemon&page=3&page_size=40", 200);
    expect(end.body.data.items).toEqual([]);
    const setCards = await call("catalog-set-page-2", "/cards/search?game=Pokemon&set_id=0010&page=2&page_size=40", 200);
    expect(setCards.body.data.items.map((item: { card_ref: string }) => item.card_ref)).toEqual(["0001"]);
  });

  it("C03 exposes published zero prices and real history points without publishing pending imports", async () => {
    const zero = await call("card-zero", "/cards/0001", 200);
    expect(zero.body.data).toMatchObject({ card_ref: "0001", price_usd: 0, previous_7d_price_usd: 1.5, price_as_of: "2026-10-12" });
    const unknown = await call("card-unknown", "/cards/0002", 200);
    expect(unknown.body.data.price_usd).toBeUndefined();
    const prices = await call("prices-zero", "/cards/0001/market-prices?response_version=2&finish=Normal&language=English", 200);
    expect(prices.body.data.prices).toMatchObject([{ grader: "Raw", grade: null, condition: "Near Mint", price: 0, currency: "USD" }]);
    const absent = await call("prices-unknown", "/cards/0002/market-prices?response_version=2", 200);
    expect(absent.body.data.prices).toEqual([]);
    const history = await call("history-zero", "/cards/0001/price-series?response_version=2&days=30&grader=Raw&condition=Near%20Mint&finish=Normal", 200);
    expect(history.body.data.series).toEqual([
      { date: "2026-10-01", price: 2 }, { date: "2026-10-05", price: 1.5 }, { date: "2026-10-12", price: 0 },
    ]);
    const noHistory = await call("history-unknown", "/cards/0002/price-series?response_version=2&days=30&grader=Raw", 200);
    expect(noHistory.body.data.series).toEqual([]);
    expect(prices.response.headers.get("Cache-Control")).toBe("no-store");
    expect(history.response.headers.get("Cache-Control")).toBe("no-store");
  });

  it("C03 distinguishes an empty catalog from invalid input, missing cards and unavailable storage", async () => {
    const empty = await call("catalog-empty", "/cards/search?q=No%20matching%20contract&page=1&page_size=40", 200);
    expect(empty.body.data.items).toEqual([]);
    const invalid = await call("catalog-invalid", "/cards/search?q=&page=1&page_size=40", 422);
    expect(invalid.body.error.code).toBe("VALIDATION_ERROR");
    const missing = await call("card-not-found", "/cards/missing", 404);
    expect(missing.body.error.code).toBe("NOT_FOUND");
    const unavailable = vi.spyOn(db, "prepare").mockImplementationOnce(() => { throw new Error("Contract database unavailable"); });
    try {
      await call<string>("catalog-unavailable", "/cards/search?q=Unavailable%20contract&page=1&page_size=40", 500);
      expect(unavailable).toHaveBeenCalledOnce();
    } finally {
      unavailable.mockRestore();
    }
  });

  it("C03 keeps USD rates usable and reports upstream failure when no cached rates exist", async () => {
    externalFetch.mockResolvedValueOnce(new Response(JSON.stringify({
      base: "USD", date: "2026-10-12", rates: { EUR: 0.92, JPY: 150, GBP: 0.78, CAD: 1.37, AUD: 1.52, NZD: 1.66, SGD: 1.31 },
    }), { headers: { "Content-Type": "application/json" } }));
    const route = "/rates?base=USD&targets=EUR,JPY,GBP,CAD,AUD,NZD,SGD";
    const rates = await call("rates-available", route, 200);
    expect(rates.body.data).toMatchObject({ base: "USD", rates: { EUR: 0.92, JPY: 150 }, stale: false });
    cached.delete("exchange-rates:USD:v1");
    const unavailable = await call("rates-unavailable", route, 502);
    expect(unavailable.body.error.code).toBe("UPSTREAM_ERROR");
    expect(externalFetch).toHaveBeenCalledTimes(2);
  });

  it("C06 keeps lifetime Free quota and request replay semantics without trusting client Premium claims", async () => {
    const fresh = await call("quota-fresh", "/scan/quota", 200, { token: ownerToken });
    expect(fresh.body.data).toEqual({ access: "free", limit: 10, reserved: 0, consumed: 0, remaining: 10, unlimited: false });
    const options = { method: "POST", token: ownerToken, body: { request_id: reservationId }, headers: { "Idempotency-Key": reservationId } };
    const reserved = await call("quota-reserved", "/scan/quota/reserve", 200, options);
    expect(reserved.body.data.quota).toMatchObject({ reserved: 1, consumed: 0, remaining: 9 });
    expect((await call("quota-replayed", "/scan/quota/reserve", 200, options)).body).toEqual(reserved.body);
    const denied = await call("quota-premium-unverified", "/scan/quota", 409, { token: ownerToken, headers: { "X-Local-Premium-State": "verified" } });
    expect(denied.body.error.code).toBe("ENTITLEMENT_SYNC_REQUIRED");
    expect(await db.prepare("SELECT count(*) AS count FROM scan_quota_request").first<number>("count")).toBe(1);
  });
});
