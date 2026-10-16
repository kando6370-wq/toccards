import { execFile } from "node:child_process";
import { mkdir, mkdtemp } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath, URL } from "node:url";
import { promisify } from "node:util";
import { build } from "esbuild";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { PGliteDatabase } from "./pglite-database";

describe("PGlite PostgreSQL test database", () => {
  let db: PGliteDatabase;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
  });

  afterEach(async () => db.close());

  it("executes PostgreSQL statements and normalizes production scalar types", async () => {
    const executed = await db.exec(`
      CREATE TABLE example (id text PRIMARY KEY, amount numeric, happened_on date);
      INSERT INTO example VALUES ('one', 12.5, '2026-08-26');
      INSERT INTO example VALUES ('two', 20, '2026-08-27');
    `);
    const row = await db.prepare(`
      SELECT count(*)::bigint AS count,
             sum(amount)::numeric AS total,
             min(happened_on) AS first_date
      FROM example
      WHERE amount >= ?
    `).bind(10).first<{
      count: number;
      total: number;
      first_date: string;
    }>();

    expect(executed.count).toBe(3);
    expect(row).toEqual({
      count: 2,
      total: 32.5,
      first_date: "2026-08-26",
    });
  });

  it("runs D1-style batches in one PostgreSQL transaction", async () => {
    await db.prepare("CREATE TABLE batched (id text PRIMARY KEY)").run();

    const results = await db.batch([
      db.prepare("INSERT INTO batched VALUES (?)").bind("a"),
      db.prepare("INSERT INTO batched VALUES (?)").bind("b"),
    ]);
    const rows = await db.prepare("SELECT id FROM batched ORDER BY id").all<{
      id: string;
    }>();

    expect(results.map((result) => result.meta.changes)).toEqual([1, 1]);
    expect(rows.results).toEqual([{ id: "a" }, { id: "b" }]);
  });
});


it("releases closed PostgreSQL engines even when test tooling retains their wrappers", async () => {
  const apiRoot = fileURLToPath(new URL("../../", import.meta.url));
  const artifacts = join(apiRoot, ".wrangler");
  await mkdir(artifacts, { recursive: true });
  const directory = await mkdtemp(join(artifacts, "pglite-lifetime-test-"));
  const output = join(directory, "retention.mjs");
  await build({
    stdin: { resolveDir: apiRoot, loader: "js", contents: `
      import assert from 'node:assert/strict';
      import { setImmediate as nextTurn } from 'node:timers/promises';
      import { PGlite } from '@electric-sql/pglite';
      import { PGliteDatabase } from './src/test-support/pglite-database.ts';
      const backends = [];
      const create = PGlite.create.bind(PGlite);
      let creationDepth = 0;
      PGlite.create = async (...args) => {
        const outermost = creationDepth++ === 0;
        try {
          const backend = await create(...args);
          if (outermost) backends.push(new WeakRef(backend));
          return backend;
        } finally { creationDepth--; }
      };
      // Spies and test reporters can retain wrappers after their databases close.
      globalThis.retainedDatabaseWrappers = [];
      for (let i = 0; i < 4; i++) {
        const db = await PGliteDatabase.create();
        globalThis.retainedDatabaseWrappers.push(db);
        await db.query('SELECT 1');
        await db.close();
      }
      await nextTurn(); global.gc(); await nextTurn(); global.gc();
      assert.equal(backends.length, 4, 'Observe each wrapper engine, not internal initialization helpers');
      // PGlite may keep its latest module; earlier closed engines must be collectible.
      const retainedEarlierEngines = backends.slice(0, -1).filter(ref => ref.deref() !== undefined).length;
      console.log(JSON.stringify({ retainedWrappers: globalThis.retainedDatabaseWrappers.length, retainedEarlierEngines }));
      assert.equal(retainedEarlierEngines, 0, 'Closed wrappers must not retain earlier PostgreSQL/WASM engines');
    ` },
    outfile: output, bundle: true, platform: "node", format: "esm", target: "node22", packages: "external", logLevel: "silent",
  });
  const { stdout } = await promisify(execFile)(process.execPath, ["--expose-gc", output], {
    windowsHide: true, timeout: 25_000, encoding: "utf8",
  });
  expect(JSON.parse(stdout.trim())).toEqual({ retainedWrappers: 4, retainedEarlierEngines: 0 });
}, 30_000);
