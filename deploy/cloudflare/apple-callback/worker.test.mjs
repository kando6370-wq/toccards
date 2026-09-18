import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { handleCallback } from "./worker.mjs";

const path = "/api/v1/apple/notifications/v2/sandbox";
const env = { LINUX_CALLBACK_ORIGIN: "http://dev-callback-origin.tcgcard.fun:8089" };
const require = createRequire(new URL("../../../apps/workers-api/package.json", import.meta.url));
const { Miniflare, createFetchMock } = require("miniflare");
const request = (body = "{}", suffix = path, headers = {}) => new Request(`https://callback.example${suffix}`, {
  method: "POST", headers, body,
});

test("Cloudflare runtime can forward a notification because Node fetch options are not always supported at the edge", async (t) => {
  const fetchMock = createFetchMock();
  fetchMock.disableNetConnect();
  fetchMock.get(env.LINUX_CALLBACK_ORIGIN).intercept({ path, method: "POST" }).reply(200, "");
  const runtime = new Miniflare({
    modules: true,
    scriptPath: fileURLToPath(new URL("./worker.mjs", import.meta.url)),
    compatibilityDate: "2026-06-30",
    bindings: env,
    fetchMock,
  });
  t.after(() => runtime.dispose());
  const response = await runtime.dispatchFetch(`https://callback.example${path}`, { method: "POST", body: "{}" });
  assert.equal(response.status, 200);
  fetchMock.assertNoPendingInterceptors();
});

test("the public relay cannot expose Admin, other APIs or production notifications", async () => {
  const neverFetch = () => { throw new Error("Unexpected upstream request"); };
  for (const suffix of ["/", "/api/v1/admin/scans", "/api/v1/health", "/api/v1/apple/notifications/v2", `${path}?origin=https://other.example`]) {
    assert.equal((await handleCallback(request("{}", suffix), env, neverFetch)).status, 404);
  }
  const result = await handleCallback(new Request(`https://callback.example${path}`), env, neverFetch);
  assert.equal(result.status, 405);
  assert.equal(result.headers.get("Allow"), "POST");
});

test("Apple signed payload bytes reach only the configured Linux path without forwarding client credentials", async () => {
  const payload = '{"signedPayload":"header.payload.signature","test":"校验"}';
  let calls = 0;
  const response = await handleCallback(request(payload, path, { Authorization: "private-token", Cookie: "private-cookie" }), env, async (url, init) => {
    calls++;
    assert.equal(url, `${env.LINUX_CALLBACK_ORIGIN}${path}`);
    assert.equal(init.method, "POST");
    assert.equal(new TextDecoder().decode(init.body), payload);
    assert.equal(init.redirect, "manual");
    assert.deepEqual(init.headers, { "Content-Type": "application/json", Accept: "application/json" });
    return new Response(null, { status: 200 });
  });
  assert.equal(calls, 1);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});

test("Linux persistence failures and invalid requests must not become successful Apple acknowledgements", async () => {
  for (const status of [400, 500, 503]) {
    const response = await handleCallback(request(), env, async () => Response.json({ error: "LINUX_FAILURE" }, { status }));
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), { error: "LINUX_FAILURE" });
  }
});

test("oversized bodies are rejected before forwarding even without Content-Length", async () => {
  let calls = 0;
  const fetcher = () => { calls++; return new Response(null); };
  for (const headers of [{}, { "Content-Length": "200001" }]) {
    assert.equal((await handleCallback(request("x".repeat(200001), path, headers), env, fetcher)).status, 413);
  }
  assert.equal(calls, 0);
});

test("invalid origin configuration cannot silently route callbacks to an unintended path", async () => {
  for (const origin of [undefined, "ftp://example.com", "https://user:secret@example.com", "https://example.com/other", "https://example.com?target=other"]) {
    assert.equal((await handleCallback(request(), { LINUX_CALLBACK_ORIGIN: origin })).status, 503);
  }
});

test("upstream network failure returns retryable failure without a relay retry", async () => {
  let calls = 0;
  const response = await handleCallback(request(), env, async () => { calls++; throw new Error("connection failed"); });
  assert.equal(response.status, 502);
  assert.equal(calls, 1);
  assert.deepEqual(await response.json(), { error: "CALLBACK_UPSTREAM_UNAVAILABLE" });
});

test("the deadline covers the response body and redirects cannot move signed payloads to another service", async (t) => {
  const server = createServer((_request, response) => {
    response.writeHead(200, { "Content-Type": "application/json" });
    response.write('{"incomplete":');
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => { server.closeAllConnections(); server.close(); });
  const origin = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await handleCallback(request(), { LINUX_CALLBACK_ORIGIN: origin }, fetch, 100)).status, 502);
  server.removeAllListeners("request");
  server.on("request", (_request, response) => {
    response.writeHead(307, { Location: "https://must-not-receive.example" });
    response.end();
  });
  assert.equal((await handleCallback(request(), { LINUX_CALLBACK_ORIGIN: origin })).status, 502);
});
