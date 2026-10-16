import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
import { test } from "node:test";
import { build } from "esbuild";
import postgres from "postgres";

// Explicit command only: never makes Docker or a live database a dependency of
// the default Workers tests. Refuse any non-local or non-empty target database.
const connectionString = process.env.SUBSCRIPTION_TEST_DATABASE_URL;
if (!connectionString) throw new Error("SUBSCRIPTION_TEST_DATABASE_URL must point to an empty local subscription_config_test database.");
const target = new URL(connectionString);
if (!["postgres:", "postgresql:"].includes(target.protocol) ||
    !["127.0.0.1", "localhost", "[::1]"].includes(target.hostname) ||
    target.pathname !== "/subscription_config_test" || target.search || target.hash) {
  throw new Error("Only an empty loopback database named subscription_config_test is allowed.");
}
const root = fileURLToPath(new URL("../", import.meta.url));
await mkdir(path.join(root, ".wrangler"), { recursive: true });
const directory = await mkdtemp(path.join(root, ".wrangler", "subscription-postgres-"));
const bundle = path.join(directory, "check.mjs");
await build({
  stdin: { contents: `
    export { createPostgresDatabase } from './src/db/postgres-database.ts';
    export { mutationLockKey } from './src/db/mutation-lock.ts';
    export { writeMutation, readConfig, readConfigList, readMutation, productAdmission } from './src/subscription-config/store.ts';
    export { writeProductAdmission } from './src/subscription-config/product-admission.ts';
    export { approvedAppleProducts } from './src/entitlements/apple-product-policy.ts';
    export { payloadHash } from './src/subscription-config/model.ts';
    export { displayFixture } from './src/subscription-config/test-fixtures.ts';
  `, resolveDir: root, loader: "ts" },
  outfile: bundle, bundle: true, platform: "node", format: "esm", target: "node22", external: ["postgres"], logLevel: "silent",
});
const { createPostgresDatabase, mutationLockKey, writeMutation, readConfig, readConfigList, readMutation, productAdmission, writeProductAdmission, approvedAppleProducts, payloadHash, displayFixture } = await import(pathToFileURL(bundle).href);
const sql = postgres(connectionString, { max: 1 });
const control = postgres(connectionString, { max: 1 });
const observer = postgres(connectionString, { max: 1 });
const first = createPostgresDatabase(connectionString);
const second = createPostgresDatabase(connectionString);
await test("subscription configuration on independent PostgreSQL connections", async (suite) => {
  suite.after(async () => {
    await Promise.all([first.close(), second.close(), sql.end(), control.end(), observer.end()]);
  });
  const existing = await sql`SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'`;
  if (existing.length) throw new Error("Target database is not empty; no migration or cleanup was executed.");
  for (const migration of ["0000_business_schema", "0006_mutation_lock", "0014_subscription_display_config"]) {
    await sql.unsafe(await readFile(path.join(root, "src/db/postgres/migrations", migration + ".sql"), "utf8"));
  }
  for (const [product, type] of [["paid.week", "subscription"], ["trial.week", "subscription"], ["lifetime", "non_consumable"]]) {
    await sql`INSERT INTO billing_product (id, store, product_id, plan_id, entitlement_id, product_type, active, created_at, updated_at)
      VALUES (${product}, 'app_store', ${product}, ${product}, 'performance_pro', ${type}, 1, '2026-10-14', '2026-10-14')`;
  }
  const settings = {
    APP_ENVIRONMENT: "development", APPLE_IAP_BUNDLE_ID: "example.app",
    APPLE_IAP_PRODUCT_IDS: "paid.week,trial.week,lifetime", SUBSCRIPTION_DISPLAY_PRODUCT_IDS: "paid.week,trial.week,lifetime",
  };
  async function mutate(database, scope, command, requestId = crypto.randomUUID()) {
    return writeMutation({ ...settings, DB: database }, scope, "local-test-admin", requestId, await payloadHash(command), command, null);
  }
  async function create(database, scope, name = "Configuration") {
    const outcome = await mutate(database, scope, { kind: "create", config: { ...displayFixture(), name } });
    assert.equal(outcome.status, 201);
    return outcome.body.data;
  }
  const activation = (id, config = displayFixture()) => ({ kind: "activate", page_type: "page", config_id: id,
    expected_active_revision: 0, expected_config_revision: 1, config });
  async function waitForLocks(fragment, count = 1) {
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      const rows = await observer`SELECT query FROM pg_stat_activity
        WHERE datname = current_database() AND wait_event_type = 'Lock' AND pid <> pg_backend_pid()`;
      if (rows.filter((row) => row.query.includes(fragment)).length >= count) return;
      await delay(25);
    }
    throw new Error("Expected independent PostgreSQL sessions blocked on: " + fragment);
  }
  async function withHeldLock(query, values, work) {
    let entered;
    let release;
    const ready = new Promise((resolve) => { entered = resolve; });
    const released = new Promise((resolve) => { release = resolve; });
    const transaction = control.begin(async (tx) => {
      await tx.unsafe(query, values);
      entered();
      await released;
    });
    await Promise.race([ready, transaction.then(() => { throw new Error("Lock holder exited prematurely."); })]);
    try { return await work(release); }
    finally { release(); await transaction; }
  }
  async function withScopeLock(scope, work) {
    const key = await mutationLockKey("subscription-display", scope);
    return withHeldLock("INSERT INTO mutation_lock (lock_key) VALUES ($1) ON CONFLICT (lock_key) DO UPDATE SET lock_key = excluded.lock_key", [key], work);
  }

  await suite.test("two independent sessions wait on the scope lock and replay exactly one creation", async () => {
    const scope = "development:native-idempotency";
    const id = crypto.randomUUID();
    await withScopeLock(scope, async (release) => {
      const command = { kind: "create", config: displayFixture() };
      const writes = [mutate(first, scope, command, id), mutate(second, scope, command, id)];
      try { await waitForLocks("INSERT INTO mutation_lock", 2); }
      finally { release(); }
      const results = await Promise.all(writes);
      assert.equal(results[0].status, 201);
      assert.deepEqual(results[0], results[1]);
    });
    assert.equal((await readConfigList(first, scope)).items.length, 1);
  });

  await suite.test("competing activations cannot both succeed against the same confirmed active revision", async () => {
    const scope = "development:native-activation";
    const a = await create(first, scope, "A");
    const b = await create(second, scope, "B");
    await withScopeLock(scope, async (release) => {
      const writes = [mutate(first, scope, activation(a.id)), mutate(second, scope, activation(b.id))];
      try { await waitForLocks("INSERT INTO mutation_lock", 2); }
      finally { release(); }
      const results = await Promise.all(writes);
      assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
    });
    const list = await readConfigList(first, scope);
    assert.equal(list.items.filter((item) => item.enabled).length, 1);
    assert.equal(list.active.find((item) => item.page_type === "page").active_revision, 1);
  });

  await suite.test("concurrent editors cannot overwrite a version they did not read", async () => {
    const scope = "development:native-edit";
    const created = await create(first, scope);
    await withScopeLock(scope, async (release) => {
      const command = (name) => ({ kind: "save", id: created.id, expected_revision: 1, config: { ...displayFixture(), name } });
      const writes = [mutate(first, scope, command("A")), mutate(second, scope, command("B"))];
      try { await waitForLocks("INSERT INTO mutation_lock", 2); }
      finally { release(); }
      assert.deepEqual((await Promise.all(writes)).map((r) => r.status).sort(), [200, 409]);
    });
    assert.equal((await readConfig(first, scope, created.id)).revision, 2);
  });

  await suite.test("admitted billing rows stay share-locked until the active pointer commits", async () => {
    const scope = "development:native-admission";
    const created = await create(first, scope);
    let activate;
    let revoke;
    try {
      await withHeldLock("SELECT scope FROM subscription_display_active WHERE scope = $1 AND page_type = 'page' FOR UPDATE", [scope], async (release) => {
        activate = mutate(first, scope, activation(created.id));
        await waitForLocks("UPDATE subscription_display_active SET");
        revoke = (async () => sql`UPDATE billing_product SET active = 0 WHERE product_id = 'paid.week'`)();
        try { await waitForLocks("UPDATE billing_product SET active"); }
        finally { release(); }
        assert.equal((await activate).status, 200);
        await revoke;
      });
      const admission = await productAdmission({ ...settings, DB: second }, [{ product_id: "paid.week", product_type: "subscription" }]);
      assert.equal(admission[0].admitted, false);
    } finally {
      await Promise.allSettled([activate, revoke].filter(Boolean));
      await sql`UPDATE billing_product SET active = 1 WHERE product_id = 'paid.week'`;
    }
  });

  await suite.test("database failures roll back content and idempotency result together on real PostgreSQL", async () => {
    const scope = "development:native-rollback";
    const id = crypto.randomUUID();
    await sql.unsafe(`CREATE FUNCTION test_subscription_result_failure() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'intentional local result failure'; END $$;
      CREATE TRIGGER test_subscription_result_failure BEFORE UPDATE ON subscription_display_mutation
      FOR EACH ROW EXECUTE FUNCTION test_subscription_result_failure();`);
    try {
      await assert.rejects(mutate(first, scope, { kind: "create", config: displayFixture() }, id), /intentional local result failure/);
      assert.equal((await readConfigList(second, scope)).items.length, 0);
      assert.equal(await readMutation(second, scope, id), null);
    } finally {
      await sql.unsafe("DROP TRIGGER test_subscription_result_failure ON subscription_display_mutation; DROP FUNCTION test_subscription_result_failure();");
    }
    assert.equal((await mutate(second, scope, { kind: "create", config: displayFixture() }, id)).status, 201);
  });

  await suite.test("concurrent approval is idempotent and never loses a second new product", async () => {
    const scope = "development:native-products";
    const e = (DB) => ({ ...settings, DB, APPLE_IAP_BUNDLE_ID: "native-products", APP_STORE_CONNECT_APP_ID: "456" });
    const approve = (DB, productId, requestId = crypto.randomUUID()) => writeProductAdmission(e(DB), scope, "super-admin", requestId, productId,
      { product_id: productId, product_type: "subscription", has_free_trial: false }, "card_monthlytest", null);
    const requestId = crypto.randomUUID();
    await withScopeLock(scope, async (release) => {
      const pending = [approve(first, "native.month", requestId), approve(second, "native.month", requestId)];
      try { await waitForLocks("INSERT INTO mutation_lock", 2); } finally { release(); }
      const results = await Promise.all(pending);
      assert.deepEqual(results[0], results[1]); assert.equal(results[0].status, 200);
    });
    const results = await Promise.all([approve(first, "native.week"), approve(second, "native.year")]);
    assert.deepEqual(results.map((r) => r.status), [200, 200]);
    assert.equal((await approvedAppleProducts(e(first))).length, 3);
    assert.equal((await approvedAppleProducts({ ...e(second), APP_ENVIRONMENT: "production" })).length, 0);
    assert.equal(Number((await sql`SELECT COUNT(*) AS count FROM billing_product WHERE product_id = 'native.month'`)[0].count), 1);
  });
  await suite.test("shared database approvals cannot race the same Product ID into two scopes", async () => {
    const approve = (DB, scope) => writeProductAdmission({ ...settings, DB }, scope, "super-admin", crypto.randomUUID(), scope,
      { product_id: "native.cross-scope", product_type: "subscription", has_free_trial: false }, "card_monthlytest", null);
    const results = await Promise.all([approve(first, "development:beta"), approve(second, "production:prod")]);
    assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
    assert.equal(results.find((r) => r.status === 409).body.error.code, "PRODUCT_SCOPE_CONFLICT");
  });
  await suite.test("registry storage failure rolls back the product and approval result together", async () => {
    const scope = "development:native-product-rollback";
    const e = { ...settings, DB: first, APPLE_IAP_BUNDLE_ID: "native-product-rollback", APP_STORE_CONNECT_APP_ID: "456" };
    await sql.unsafe(`CREATE FUNCTION test_admission_failure() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'intentional registry failure'; END $$;
      CREATE TRIGGER test_admission_failure BEFORE INSERT ON app_config FOR EACH ROW EXECUTE FUNCTION test_admission_failure();`);
    const requestId = crypto.randomUUID();
    try {
      await assert.rejects(writeProductAdmission(e, scope, "super-admin", requestId, "rollback", {
        product_id: "native.rollback", product_type: "subscription", has_free_trial: false,
      }, "card_monthlytest", null), /intentional registry failure/);
      assert.equal(await readMutation(second, scope, requestId), null);
      assert.equal((await approvedAppleProducts({ ...e, DB: second })).length, 0);
      assert.equal(Number((await sql`SELECT COUNT(*) AS count FROM billing_product WHERE product_id = 'native.rollback'`)[0].count), 0);
    } finally {
      await sql.unsafe("DROP TRIGGER test_admission_failure ON app_config; DROP FUNCTION test_admission_failure();");
    }
  });

});
