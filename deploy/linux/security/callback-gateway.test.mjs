import assert from "node:assert/strict";
import { once } from "node:events";
import http from "node:http";
import test from "node:test";

import { createCallbackGateway } from "./callback-gateway.mjs";

const callback = "/api/v1/apple/notifications/v2/sandbox";

test("only the Apple Sandbox POST reaches the fixed Linux API without caller credentials", async (t) => {
  const calls = [];
  const upstream = http.createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    calls.push({ method: request.method, path: request.url, headers: request.headers, body });
    response.writeHead(400, { "Content-Type": "application/json" });
    response.end('{"error":"INVALID_REQUEST"}');
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  t.after(() => upstream.close());

  const gateway = createCallbackGateway({ origin: `http://127.0.0.1:${upstream.address().port}` });
  gateway.listen(0, "127.0.0.1");
  await once(gateway, "listening");
  t.after(() => gateway.close());
  const base = `http://127.0.0.1:${gateway.address().port}`;

  for (const path of ["/", "/api/v1/health", "/api/v1/admin/scans", "/api/v1/apple/notifications/v2", `${callback}?redirect=1`]) {
    const response = await fetch(base + path, { headers: { Host: "192.168.50.201:8080" } });
    assert.equal(response.status, 404);
  }
  const wrongMethod = await fetch(base + callback);
  assert.equal(wrongMethod.status, 405);
  assert.equal(wrongMethod.headers.get("Allow"), "POST");
  assert.equal(calls.length, 0);

  const body = '{"signedPayload":"test.jws","extra":"校验"}';
  const accepted = await fetch(base + callback, {
    method: "POST", headers: { Host: "192.168.50.201:8080", Authorization: "private", Cookie: "private" }, body,
  });
  assert.equal(accepted.status, 400);
  assert.deepEqual(await accepted.json(), { error: "INVALID_REQUEST" });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].method, "POST");
  assert.equal(calls[0].path, callback);
  assert.equal(calls[0].body, body);
  assert.equal(calls[0].headers.authorization, undefined);
  assert.equal(calls[0].headers.cookie, undefined);
});

test("oversized callbacks, redirects and timeout cannot bypass the gateway", async (t) => {
  let calls = 0;
  const upstream = http.createServer((_request, response) => {
    calls++;
    response.writeHead(307, { Location: "https://other.example" });
    response.end();
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  t.after(() => upstream.close());
  const gateway = createCallbackGateway({ origin: `http://127.0.0.1:${upstream.address().port}`, timeoutMs: 100 });
  gateway.listen(0, "127.0.0.1");
  await once(gateway, "listening");
  t.after(() => gateway.close());
  const base = `http://127.0.0.1:${gateway.address().port}`;

  const oversized = await fetch(base + callback, { method: "POST", body: "x".repeat(200_001) });
  assert.equal(oversized.status, 413);
  assert.equal(calls, 0);
  const chunked = await new Promise((resolve, reject) => {
    const request = http.request(base + callback, {
      method: "POST", headers: { "Transfer-Encoding": "chunked" },
    }, (response) => {
      response.resume();
      response.on("end", () => resolve(response.statusCode));
    });
    request.on("error", reject);
    request.end("x".repeat(200_001));
  });
  assert.equal(chunked, 413);
  assert.equal(calls, 0);
  const redirect = await fetch(base + callback, { method: "POST", body: "{}" });
  assert.equal(redirect.status, 502);
  assert.equal(calls, 1);

  upstream.removeAllListeners("request");
  upstream.on("request", (_request, response) => {
    response.writeHead(200);
    response.write("partial");
  });
  const timeout = await fetch(base + callback, { method: "POST", body: "{}" });
  assert.equal(timeout.status, 502);
});
