import assert from "node:assert/strict";
import test from "node:test";
import { SubscriptionMutation, parsePendingOperation } from "../src/subscription-config/mutation.ts";
import { memoryStorage, operationFixture, REQUEST_ID } from "./subscription-fixtures.mjs";

const key = "test-admin-scope";
const timings = { writeMs: 15, checkMs: 35, pollMs: 2 };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const deferred = () => { let resolve; let reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { promise, resolve, reject }; };
const succeeded = (data = { id: "saved" }) => ({ request_id: REQUEST_ID, status: "succeeded", http_status: 201, response: { success: true, data } });
const unknown = () => ({ request_id: REQUEST_ID, status: "unknown" });
const apiFailure = (code, status = 422) => Object.assign(new Error(code), { code, status });

function coordinator(request, storage = memoryStorage()) {
  return { storage, mutation: new SubscriptionMutation({ request, storage, key, ...timings }) };
}

test("persists the immutable operation before sending and drops it only after confirmed success", async () => {
  const storage = memoryStorage();
  const input = operationFixture();
  const pending = deferred();
  const machine = coordinator(async (_path, init) => {
    assert.deepEqual(JSON.parse(storage.getItem(key)).body, init.body);
    return pending.promise;
  }, storage).mutation;
  const run = machine.start(input);
  input.body.config.name = "Changed outside the operation";
  pending.resolve({ id: "created" }); await run;
  assert.equal(machine.state.phase, "succeeded");
  assert.equal(machine.state.result.operation.body.config.name, "订阅页标准配置");
  assert.deepEqual(machine.state.result.data, { id: "created" });
  assert.equal(storage.getItem(key), null);
});

test("double submit cannot create a second request while the first write is pending", async () => {
  let writes = 0;
  const pending = deferred();
  const { mutation } = coordinator(async () => { writes++; return pending.promise; });
  const run = mutation.start(operationFixture());
  await mutation.start({ ...operationFixture(), body: { ...operationFixture().body, request_id: "22222222-2222-4222-8222-222222222222" } });
  pending.resolve({ id: "one" }); await run;
  assert.equal(writes, 1);
});

test("a timed-out write is reconciled without being resent or losing input", async () => {
  const pending = deferred();
  let writes = 0;
  const phases = [];
  const { mutation, storage } = coordinator(async (path) => {
    if (path.includes("mutations")) return succeeded();
    writes++; return pending.promise;
  });
  mutation.subscribe((state) => phases.push(state.phase));
  await mutation.start(operationFixture());
  assert.equal(writes, 1);
  assert.ok(phases.includes("checking"));
  assert.equal(mutation.state.phase, "succeeded");
  assert.equal(storage.getItem(key), null);
  pending.resolve({ id: "late" }); await sleep(2);
  assert.equal(mutation.state.result.data.id, "saved");
});

test("unknown is not failure: bounded reconciliation preserves the original request and blocks new writes", async () => {
  const pending = deferred();
  let writes = 0;
  const { mutation, storage } = coordinator(async (path) => {
    if (path.includes("mutations")) return unknown();
    writes++; return pending.promise;
  });
  await mutation.start(operationFixture());
  assert.equal(mutation.state.phase, "unknown");
  assert.ok(mutation.state.pending.editor.body.skus[0].trial);
  assert.equal(JSON.parse(storage.getItem(key)).body.request_id, REQUEST_ID);
  assert.equal(mutation.blocked, true);
  await mutation.start(operationFixture());
  assert.equal(writes, 1);
  pending.resolve({ id: "too-late" }); await sleep(2);
  assert.equal(mutation.state.phase, "unknown");
  assert.equal(mutation.state.result, null);
});

test("confirmed write validation/conflict keeps the editor but ends uncertainty", async () => {
  const error = apiFailure("CONFIG_CONFLICT", 409);
  error.fields = [{ path: "name", message: "conflict" }];
  const { mutation, storage } = coordinator(async () => { throw error; });
  await mutation.start(operationFixture());
  assert.equal(mutation.state.phase, "failed");
  assert.equal(mutation.state.result.error.code, "CONFIG_CONFLICT");
  assert.equal(mutation.state.result.operation.editor.body.name, "订阅页标准配置");
  assert.equal(mutation.blocked, false);
  assert.equal(storage.getItem(key), null);
});

test("an HTTP 503 is not assumed unwritten until the original mutation reports its final result", async () => {
  const phases = [];
  const { mutation } = coordinator(async (path) => {
    if (path.includes("mutations")) return { request_id: REQUEST_ID, status: "failed", http_status: 503, response: { success: false, error: { code: "CATALOG_UNAVAILABLE", message: "unavailable" } } };
    throw apiFailure("SUBSCRIPTION_CONFIG_UNAVAILABLE", 503);
  });
  mutation.subscribe((state) => phases.push(state.phase));
  await mutation.start(operationFixture());
  assert.ok(phases.includes("checking"));
  assert.equal(mutation.state.result.error.code, "CATALOG_UNAVAILABLE");
  assert.equal(mutation.state.phase, "failed");
});

test("network failure during reconciliation leaves an unknown operation recoverable", async () => {
  const { mutation, storage } = coordinator(async () => { throw new TypeError("offline"); });
  await mutation.start(operationFixture());
  assert.equal(mutation.state.phase, "unknown");
  assert.ok(storage.getItem(key));
  assert.match(mutation.state.warning, /暂时无法确认/);
});

test("re-entry reads the persisted request and checks it without automatically replaying writes", async () => {
  const storage = memoryStorage(); storage.setItem(key, JSON.stringify(operationFixture()));
  const calls = [];
  const { mutation } = coordinator(async (path) => { calls.push(path); return succeeded(); }, storage);
  assert.equal(mutation.state.phase, "unknown");
  await mutation.reconcile();
  assert.deepEqual(calls, ["/subscription-config-mutations/" + REQUEST_ID]);
  assert.equal(mutation.state.phase, "succeeded");
});

test("manual retry checks first and replays only the exact persisted UUID and payload", async () => {
  const storage = memoryStorage(); const original = operationFixture(); storage.setItem(key, JSON.stringify(original));
  const calls = [];
  const { mutation } = coordinator(async (path, init) => {
    calls.push({ path, body: init?.body });
    return path.includes("mutations") ? unknown() : { id: "replayed" };
  }, storage);
  await mutation.reconcile(true);
  assert.equal(calls[0].path, "/subscription-config-mutations/" + REQUEST_ID);
  assert.equal(calls[1].path, original.path);
  assert.deepEqual(calls[1].body, original.body);
  assert.equal(mutation.state.phase, "succeeded");
});

test("manual retry does not replay a request whose original result is already successful", async () => {
  const storage = memoryStorage(); storage.setItem(key, JSON.stringify(operationFixture()));
  let calls = 0;
  const { mutation } = coordinator(async () => { calls++; return succeeded(); }, storage);
  await mutation.reconcile(true);
  assert.equal(calls, 1);
});

test("leaving stops UI updates but preserves the operation for the same administrator", async () => {
  const pending = deferred();
  const { mutation, storage } = coordinator(async () => pending.promise);
  const run = mutation.start(operationFixture());
  mutation.stop();
  pending.resolve({ id: "late" }); await run;
  assert.equal(mutation.state.phase, "unknown");
  assert.equal(mutation.state.result, null);
  assert.ok(storage.getItem(key));
  const other = new SubscriptionMutation({ request: async () => {}, storage, key: "different-admin" });
  assert.equal(other.state.pending, null);
});

test("storage failure prevents a write that could not be reconciled after navigation", async () => {
  const storage = memoryStorage(); storage.setItem = () => { throw new Error("quota"); };
  let writes = 0;
  const { mutation } = coordinator(async () => { writes++; }, storage);
  await mutation.start(operationFixture());
  assert.equal(writes, 0);
  assert.match(mutation.state.warning, /本次未发送请求/);
});

test("malformed retained operations cannot redirect replay to arbitrary Admin endpoints", () => {
  const original = operationFixture();
  assert.throws(() => parsePendingOperation(JSON.stringify({ ...original, path: "/permissions" })));
  assert.throws(() => parsePendingOperation(JSON.stringify({ ...original, method: "DELETE" })));
  const storage = memoryStorage(); storage.setItem(key, "invalid json");
  assert.equal(coordinator(async () => {}, storage).mutation.blocked, true);
});

test("mismatched result IDs are unknown instead of acknowledging another operation", async () => {
  const storage = memoryStorage(); storage.setItem(key, JSON.stringify(operationFixture()));
  const { mutation } = coordinator(async () => ({ ...succeeded(), request_id: "different" }), storage);
  await mutation.reconcile();
  assert.equal(mutation.state.phase, "unknown");
  assert.ok(storage.getItem(key));
});

test("authentication failures during replay cannot erase an unresolved original write", async () => {
  const storage = memoryStorage(); storage.setItem(key, JSON.stringify(operationFixture()));
  const { mutation } = coordinator(async (path) => {
    if (path.includes("mutations")) return unknown();
    throw apiFailure("UNAUTHORIZED", 401);
  }, storage);
  await mutation.reconcile(true);
  assert.equal(mutation.state.phase, "unknown");
  assert.ok(storage.getItem(key));
});

test("damaged persisted editor state stays blocked instead of crashing or silently losing the original request", () => {
  const op = operationFixture(); op.editor = { body: {} };
  assert.throws(() => parsePendingOperation(JSON.stringify(op)), /编辑记录不完整/);
});

test("a one-time type change can explicitly release its old trial while retaining the copy", async () => {
  const { changeProduct, productMap, unlinkTrial, validateEditor } = await import("../src/subscription-config/model.ts");
  const { editorFixture, catalogFixture } = await import("./subscription-fixtures.mjs");
  const body = editorFixture().body;
  body.skus[0] = changeProduct(body.skus[0], "", productMap(catalogFixture()), "non_consumable");
  assert.equal(body.skus[0].needs_trial_repair, true);
  const released = unlinkTrial(body, body.skus[0].key);
  assert.equal(released.trial_enabled, false);
  assert.equal(released.skus[0].trial.cta, "START FREE TRIAL");
  assert.ok(!validateEditor(released, catalogFixture()).some((i) => i.path.endsWith("trial.product_id")));
});

test("an initial authentication rejection retains the pending snapshot for reconciliation after login", async () => {
  const { mutation, storage } = coordinator(async () => { throw apiFailure("UNAUTHORIZED", 401); });
  await mutation.start(operationFixture());
  assert.equal(mutation.state.phase, "unknown");
  assert.equal(JSON.parse(storage.getItem(key)).editor.body.name, "订阅页标准配置");
  assert.equal(mutation.state.result, null);
});


test("product approval retains scope and the exact request across reload/reconciliation", async () => {
  const input = { ...operationFixture(), kind: "admit", method: "POST", path: "/subscription-products/admit",
    body: { request_id: REQUEST_ID, product_id: "cardx.month", product_type: "subscription",
      expected_scope: "development:beta.app", singular_event_name: "card_monthlytest", acknowledge_legacy_restore_limit: true } };
  assert.deepEqual(parsePendingOperation(JSON.stringify(input)), input);
  const storage = memoryStorage();
  const machine = coordinator(async (_path, init) => { assert.equal(init.body.expected_scope, "development:beta.app"); return { product_id: "cardx.month" }; }, storage).mutation;
  await machine.start(input);
  assert.equal(machine.state.phase, "succeeded");
  assert.equal(machine.state.result.operation.kind, "admit");
});


test("damaged retained approval editors cannot crash the recovery page or replay a new write", () => {
  const input = { ...operationFixture(), kind: "admit", method: "POST", path: "/subscription-products/admit", editor: {} };
  assert.throws(() => parsePendingOperation(JSON.stringify(input)), /编辑记录不完整/);
});
