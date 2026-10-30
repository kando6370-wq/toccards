import { Hono } from "hono";
import { afterEach, describe, expect, it, vi } from "vitest";
import { PostgresDatabase } from "./db/postgres-database";
import { createLocalDbDataSourceAdapter } from "./data-source/local-db-adapter";
import { createKvCachedDataSourceAdapter } from "./data-source/kv-cache";
import { createCacheApiDataSourceAdapter } from "./data-source/cache-api";
import { apiRequestId } from "./request-id";
import { RequestPerformance, recordSqlQuery } from "./request-performance";

describe("request performance evidence", () => {
  afterEach(() => vi.restoreAllMocks());

  it("distinguishes a cached search from its catalog and price SQL without logging bindings or keywords", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});
    const db = database(async (sql) => sql.includes("FROM cards_all") ? [{
      product_id: "card-1", game_id: 1, game: "Pokemon", name: "Card",
      set_id: "set-1", set_name: "Set", set_code: "SET", number: "1",
      rarity: null, product_type_name: "Cards",
    }] : []);
    const values = new Map<string, string>();
    const source = createKvCachedDataSourceAdapter(createLocalDbDataSourceAdapter(db), {
      async get(key) { return values.get(key) ?? null; },
      async put(key, value) { values.set(key, value); },
    });
    const app = tracedApp();
    app.get("/api/v1/search", async (c) => c.json(await source.searchCards(
      c.req.query("q") ?? "", { has_image: 2, game: "Pokemon" },
    )));

    const cold = await app.request("/api/v1/search?q=private-keyword");
    const warm = await app.request("/api/v1/search?q=private-keyword");
    expect(await warm.json()).toEqual(await cold.json());
    const records = completions(logs);
    expect(records[0].performance).toMatchObject({
      sql: { count: 2, returned_rows: 1, errors: 0 }, cache: { kv: { miss: 1, hit: 0 } },
    });
    expect(records[1].performance).toMatchObject({
      sql: { count: 0 }, cache: { kv: { miss: 0, hit: 1 } },
    });
    expect(records[0].performance.sql.statements).toHaveLength(2);
    expect(records[0].performance.sql.statements[0].fingerprint).toMatch(/^[0-9a-f]{16}$/);
    expect(JSON.stringify(records)).not.toMatch(/private-keyword|card-1|Pokemon|SELECT|cards_all/);
  });

  it("separates concurrent requests sharing the Linux database client", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});
    const started = deferred();
    const release = deferred();
    const db = database(async (sql) => {
      if (sql.includes("slow_query")) { started.resolve(); await release.promise; }
      return [{ value: 1 }];
    });
    const app = tracedApp();
    app.get("/api/v1/one", async (c) => {
      await db.prepare("SELECT value FROM slow_query").first();
      return c.json({ ok: true });
    });
    app.get("/api/v1/two", async (c) => {
      await db.prepare("SELECT value FROM fast_query WHERE id = ?").bind("secret-a").first();
      await db.prepare("SELECT value FROM fast_query WHERE id = ?").bind("secret-b").first();
      return c.json({ ok: true });
    });
    const first = app.request("/api/v1/one");
    await started.promise;
    expect((await app.request("/api/v1/two")).status).toBe(200);
    release.resolve();
    expect((await first).status).toBe(200);
    const records = completions(logs);
    expect(records.find((row) => row.path.endsWith("/one"))?.performance.sql.count).toBe(1);
    const two = records.find((row) => row.path.endsWith("/two"));
    expect(two?.performance.sql).toMatchObject({ count: 2, returned_rows: 2 });
    expect(two?.performance.sql.statements).toHaveLength(1);
    expect(two?.performance.sql.statements[0].count).toBe(2);
    expect(JSON.stringify(records)).not.toContain("secret-");
  });

  it("counts failed SQL while preserving the error response", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});
    const db = database(async () => { throw new Error("private database failure"); });
    const app = tracedApp();
    app.get("/api/v1/failure", async () => {
      await db.prepare("SELECT value FROM example WHERE id = ?").bind("private-id").first();
      return new Response("unreachable");
    });
    expect((await app.request("/api/v1/failure")).status).toBe(500);
    const record = completions(logs)[0];
    expect(record.performance.sql).toMatchObject({ count: 1, returned_rows: 0, errors: 1 });
    expect(record.performance.sql.statements[0].errors).toBe(1);
    expect(JSON.stringify(record)).not.toContain("private");
  });

  it("records broken caches separately from misses without turning fallback success into an error", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});
    const source = createCacheApiDataSourceAdapter(createLocalDbDataSourceAdapter(database(async () => [])), {
      async match() { throw new Error("unavailable"); },
      async put() { throw new Error("unavailable"); },
    });
    const app = tracedApp();
    app.get("/api/v1/market", async (c) => c.json(await source.getMarketPrices("card-1")));
    expect((await app.request("/api/v1/market")).status).toBe(200);
    expect(completions(logs)[0].performance).toMatchObject({
      sql: { count: 1, errors: 0 }, cache: { cache_api: { error: 1, miss: 0, hit: 0 } },
    });
  });

  it("bounds fingerprint cardinality while keeping totals and excludes work finishing after the response", async () => {
    const metrics = new RequestPerformance();
    const release = deferred();
    let background!: Promise<void>;
    await metrics.run(async () => {
      for (let index = 0; index < 25; index += 1) {
        recordSqlQuery(`SELECT column_${index} FROM example`, 2, 1, false);
      }
      background = release.promise.then(() => recordSqlQuery("SELECT background", 1, 1, false));
    });
    const before = metrics.snapshot();
    expect(before?.sql).toMatchObject({ count: 25, duration_ms: 50, returned_rows: 25, overflow_count: 5 });
    expect(before?.sql.statements).toHaveLength(20);
    release.resolve();
    await background;
    expect(metrics.snapshot()).toEqual(before);
  });
});

function tracedApp() {
  const app = new Hono();
  app.use("/api/v1/*", apiRequestId());
  app.onError((_error, c) => c.json({ error: "INTERNAL_ERROR" }, 500));
  return app;
}

function database(load: (sql: string) => Promise<Record<string, unknown>[]>) {
  return new PostgresDatabase({
    async unsafe(sql: string) {
      const rows = await load(sql);
      return Object.assign(rows, {
        command: "SELECT", count: rows.length,
        columns: Object.keys(rows[0] ?? {}).map((name) => ({ name })),
      });
    },
  } as never);
}

function completions(logs: { mock: { calls: unknown[][] } }) {
  return logs.mock.calls.filter(([event]) => event === "api_request")
    .map(([, value]) => JSON.parse(String(value)));
}

function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => { resolve = done; });
  return { promise, resolve };
}
