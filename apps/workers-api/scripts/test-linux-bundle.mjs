import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { once } from "node:events";
import { createServer as createHttpServer } from "node:http";
import { mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";
import { linuxBuildOptions } from "./linux-build-options.mjs";

test("the complete Linux API bundle serves health and anonymous no-match recognition without accessing the database", async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), "kando-linux-server-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const outfile = path.join(directory, "server.mjs");
  await build({
    ...linuxBuildOptions,
    entryPoints: [fileURLToPath(new URL("../src/linux/server.ts", import.meta.url))],
    outfile,
  });
  execFileSync(process.execPath, ["--check", outfile], { stdio: "pipe" });

  const recognitionRequests = [];
  const recognizer = createHttpServer((request, response) => {
    let body = "";
    request.on("data", (chunk) => { body += chunk; });
    request.on("end", () => {
      recognitionRequests.push({ body: JSON.parse(body), authorization: request.headers.authorization, path: request.url });
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ candidates: [] }));
    });
  });
  recognizer.listen(0, "127.0.0.1");
  await once(recognizer, "listening");
  t.after(() => { recognizer.closeAllConnections(); recognizer.close(); });

  const reservation = createServer();
  reservation.listen(0, "127.0.0.1");
  await once(reservation, "listening");
  const { port } = reservation.address();
  await new Promise((resolve) => reservation.close(resolve));
  const server = spawn(process.execPath, [outfile], {
    cwd: directory,
    stdio: ["ignore", "pipe", "pipe"],
    timeout: 15_000,
    windowsHide: true,
    env: {
      ...process.env, NODE_OPTIONS: "", NODE_PATH: "",
      APP_ENVIRONMENT: "development", HOST: "127.0.0.1", PORT: String(port),
      DATABASE_URL: "postgres://test:test@127.0.0.1:1/toccards_test",
      OBJECT_STORAGE_PATH: directory, JWT_SECRET: "bundle-test-only",
      ALLOWED_ORIGINS: "http://localhost:8080",
      VECTOR_RECOGNITION_BASE_URL: `http://127.0.0.1:${recognizer.address().port}`,
      EXTENSION_RECOGNITION_KEY: "bundle-plugin-test-only",
      EXTENSION_RECOGNITION_REQUESTS_PER_MINUTE: "1",
      EXTENSION_TRUST_PROXY: "false",
      SCHEDULED_TASK_INTERVAL_SECONDS: "3600",
    },
  });
  const exit = once(server, "exit");
  try {
    await new Promise((resolve, reject) => {
      let stdout = "";
      let stderr = "";
      server.once("error", reject);
      server.stderr.on("data", (chunk) => { stderr += chunk; });
      server.stdout.on("data", (chunk) => {
        stdout += chunk;
        if (stdout.includes(`Linux test API listening on http://127.0.0.1:${port}`)) resolve();
      });
      server.once("exit", (code) => reject(new Error(`Linux bundle exited ${code}: ${stderr}`)));
    });
    const response = await fetch(`http://127.0.0.1:${port}/api/v1/health`, {
      signal: AbortSignal.timeout(5_000),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: "ok" });
    const input = { vector: [1, ...Array(511).fill(0)], card_type: 1 };
    const identify = (key, forgedIp) => fetch(`http://127.0.0.1:${port}/api/v1/extension/recognize`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "X-Forwarded-For": forgedIp, "CF-Connecting-IP": forgedIp },
      body: JSON.stringify(input),
      signal: AbortSignal.timeout(5_000),
    });
    assert.equal((await identify("wrong", "192.0.2.99")).status, 401);
    const identified = await identify("bundle-plugin-test-only", "192.0.2.99");
    assert.equal(identified.status, 200);
    assert.deepEqual(await identified.json(), { candidates: [] });
    assert.equal((await identify("bundle-plugin-test-only", "192.0.2.98")).status, 429,
      "Changing caller-supplied IP headers must not bypass direct Node burst protection");
    assert.deepEqual(recognitionRequests, [{ body: input, authorization: undefined, path: "/recognize" }]);
  } finally {
    server.kill();
    await exit;
  }
});

test("standalone Linux bundles can verify Apple evidence and initialize Server API correction", async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), "kando-linux-apple-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const outfile = path.join(directory, "apple.mjs");
  await build({
    ...linuxBuildOptions,
    outfile,
    stdin: {
      resolveDir: fileURLToPath(new URL("../src/linux/", import.meta.url)),
      contents: `
        import assert from "node:assert/strict";
        import { generateKeyPairSync } from "node:crypto";
        import { rootCertificates } from "node:tls";
        import { loadLinuxRuntime } from "./config.ts";
        import {
          classifyAppleVerificationFailure,
          createAppleNotificationVerifier,
          createAppleVerifier,
        } from "../entitlements/apple-signed-data.ts";
        import { createAppleServerApiClient } from "../entitlements/apple-server-api-correction.ts";

        const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
        const runtime = loadLinuxRuntime({
          APP_ENVIRONMENT: "development",
          DATABASE_URL: "postgres://test:test@127.0.0.1:1/toccards_test",
          OBJECT_STORAGE_PATH: ".",
          JWT_SECRET: "bundle-test-only",
          ALLOWED_ORIGINS: "http://localhost:8080",
          VECTOR_RECOGNITION_BASE_URL: "https://recognition.invalid",
          APPLE_IAP_BUNDLE_ID: "com.kando.kandoApp.beta",
          APPLE_ROOT_CERTIFICATES_BASE64: Buffer.from(rootCertificates[0]).toString("base64"),
          APPLE_IAP_KEY_ID: "TESTKEY123",
          APPLE_IAP_ISSUER_ID: "00000000-0000-4000-8000-000000000000",
          APPLE_IAP_PRIVATE_KEY: privateKey.export({ type: "pkcs8", format: "pem" }),
        });
        try {
          const notification = await createAppleNotificationVerifier(runtime.env);
          assert.ok(notification, "Linux callbacks require the real bundled Apple verifier");
          assert.equal(notification.environment, "Sandbox");
          try {
            await notification.verifier.verifyAndDecodeNotification("invalid.signed.payload");
            assert.fail("invalid Apple evidence must not be accepted");
          } catch (error) {
            assert.deepEqual(await classifyAppleVerificationFailure(error), {
              status: "VERIFICATION_FAILURE", retryable: false,
            });
          }
          const transaction = await createAppleVerifier(runtime.env);
          assert.ok(transaction, "purchases must retain the official transaction verifier");
          const client = await createAppleServerApiClient(runtime.env);
          assert.ok(client, "Server API correction must load the same Apple SDK");
          assert.equal(typeof client.getTransactionInfo, "function");
          console.log("apple-bundle-ok");
        } finally {
          await runtime.database.close();
        }
      `,
    },
  });
  const output = execFileSync(process.execPath, [outfile], {
    cwd: directory,
    encoding: "utf8",
    timeout: 15_000,
    stdio: "pipe",
    env: { ...process.env, NODE_OPTIONS: "", NODE_PATH: "" },
  });
  assert.equal(output.trim(), "apple-bundle-ok");
});

test("standalone Linux bundles enrich plugin candidates with shared public card details instead of leaking raw retrieval results", async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), "kando-linux-plugin-details-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const outfile = path.join(directory, "plugin-details.mjs");
  await build({
    ...linuxBuildOptions,
    outfile,
    stdin: {
      resolveDir: fileURLToPath(new URL("../src/", import.meta.url)),
      contents: `
        import assert from "node:assert/strict";
        import { app } from "./app.ts";
        const card = {
          product_id: "10738", game_id: 1, game: "Pokemon", set_id: "base",
          name: "Provider card", set_name: "Base Set", set_code: "BS", number: "4/102",
          rarity: "Rare", product_type_name: "Cards",
        };
        const price = {
          series_id: 1, product_id: "10738", source_code: "tcgplayer", source_record_id: "raw",
          metric_code: "ungraded", grader_code: "Raw", grade_min_x10: null, grade_max_x10: null,
          condition_code: "NM", condition_name: "Near Mint", language_code: "EN", language_name: "English",
          variant_code: "N", variant_name: "Normal", observed_on: "2026-10-09", amount_micros: 25000000,
          baseline_1d_on: null, baseline_1d_amount_micros: null, baseline_7d_on: null, baseline_7d_amount_micros: null,
          baseline_30d_on: null, baseline_30d_amount_micros: null, change_1d_percent: null, change_7d_percent: null, change_30d_percent: null,
        };
        const env = {
          DB: { prepare(sql) {
            assert.match(sql.trim(), /^(SELECT|WITH)\\b/);
            assert.ok(sql.includes("card_override") || sql.includes("cards_all") || sql.includes("price_current_snapshot"));
            return { bind(cardRef) { return {
              async first() {
                if (cardRef !== "10738") return null;
                return sql.includes("card_override")
                  ? { card_ref: "10738", override_fields: JSON.stringify({ name: "Corrected bundle card" }), is_missing_card: 0, image_url: null }
                  : card;
              },
              async all() { return { results: cardRef === "10738" ? [price] : [] }; },
            }; } };
          } },
          CACHE_KV: {}, EXTENSION_CLIENT_IP: "192.0.2.1",
          EXTENSION_RECOGNITION_KEY: "bundle-detail-test-only",
          EXTENSION_RECOGNITION_RATE_LIMITER: { async limit() { return { success: true }; } },
          VECTOR_RECOGNITION: { async fetch() { return Response.json({ candidates: [{ product_id: "10738", confidence: 92.125 }] }); } },
        };
        const response = await app.request("/api/v1/extension/recognize", {
          method: "POST", headers: { Authorization: "Bearer bundle-detail-test-only", "Content-Type": "application/json" },
          body: JSON.stringify({ vector: [1, ...Array(511).fill(0)], card_type: 0 }),
        }, env);
        assert.equal(response.status, 200);
        const payload = await response.json();
        assert.equal(payload.candidates.length, 1);
        const candidate = payload.candidates[0];
        assert.equal(candidate.product_id, "10738");
        assert.equal(candidate.confidence, 92.125);
        assert.equal(candidate.name, "Corrected bundle card");
        assert.equal(candidate.image_url, "https://image.tcgcard.fun/cards/10738.jpg");
        assert.equal(candidate.price_usd, 25);
        assert.equal(candidate.override_applied, true);
        assert.deepEqual(candidate.available_finishes, ["Normal"]);
        assert.deepEqual(candidate.available_languages, ["English"]);
        console.log("plugin-details-bundle-ok");
      `,
    },
  });
  const output = execFileSync(process.execPath, [outfile], {
    cwd: directory, encoding: "utf8", timeout: 15_000, stdio: "pipe",
    env: { ...process.env, NODE_OPTIONS: "", NODE_PATH: "" },
  });
  assert.equal(output.trim().split(/\r?\n/).at(-1), "plugin-details-bundle-ok");
});
