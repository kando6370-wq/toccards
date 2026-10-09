import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import test from "node:test";

test("Linux share requests preserve the external host so canonical URLs do not expose the API container", async (t) => {
  const upstream = createServer((request, response) => {
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({ host: request.headers.host, path: request.url }));
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  t.after(() => { upstream.closeAllConnections(); upstream.close(); });
  const reservedPort = createServer();
  reservedPort.listen(0, "127.0.0.1");
  await once(reservedPort, "listening");
  const port = reservedPort.address().port;
  await new Promise((resolve) => reservedPort.close(resolve));

  const child = spawn(process.execPath, [fileURLToPath(new URL("./web-server.mjs", import.meta.url))], {
    env: { ...process.env, WEB_PORT: String(port), API_ORIGIN: `http://127.0.0.1:${upstream.address().port}` },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  t.after(async () => {
    if (child.exitCode === null) {
      const closed = once(child, "close");
      child.kill();
      await closed;
    }
  });
  await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => reject(new Error(`Proxy exited ${code}`)));
    child.stdout.on("data", (chunk) => {
      if (chunk.toString().includes("Offline Linux web listening")) resolve();
    });
  });
  const response = await fetch(`http://127.0.0.1:${port}/share/cards/107055`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { host: `127.0.0.1:${port}`, path: "/share/cards/107055" });
});

test("plugin proxy requests overwrite forged forwarding chains so public clients cannot choose rate-limit identities", async (t) => {
  const upstream = createServer((request, response) => {
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({ forwarded: request.headers["x-forwarded-for"], authorization: request.headers.authorization }));
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  t.after(() => { upstream.closeAllConnections(); upstream.close(); });
  const reservedPort = createServer();
  reservedPort.listen(0, "127.0.0.1");
  await once(reservedPort, "listening");
  const port = reservedPort.address().port;
  await new Promise((resolve) => reservedPort.close(resolve));
  const child = spawn(process.execPath, [fileURLToPath(new URL("./web-server.mjs", import.meta.url))], {
    env: { ...process.env, WEB_PORT: String(port), API_ORIGIN: `http://127.0.0.1:${upstream.address().port}` },
    stdio: ["ignore", "pipe", "pipe"], windowsHide: true,
  });
  t.after(async () => {
    if (child.exitCode === null) {
      const closed = once(child, "close");
      child.kill();
      await closed;
    }
  });
  await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => reject(new Error(`Proxy exited ${code}`)));
    child.stdout.on("data", (chunk) => {
      if (chunk.toString().includes("Offline Linux web listening")) resolve();
    });
  });
  for (const path of ["/api/v1/extension/recognize?test=1", "/api/v1/extension/%72ecognize"]) {
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method: "POST",
      headers: { "X-Forwarded-For": "192.0.2.99, 192.0.2.98", Authorization: "Bearer proxy-test-only" },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.ok(body.forwarded === "127.0.0.1" || body.forwarded === "::ffff:127.0.0.1",
      "Encoded paths accepted by the API router must not bypass IP header sanitization");
    assert.equal(body.authorization, "Bearer proxy-test-only");
  }
});
