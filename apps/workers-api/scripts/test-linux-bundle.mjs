import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";
import { linuxBuildOptions } from "./linux-build-options.mjs";

test("the complete Linux API bundle starts with all dependencies and serves health", async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), "kando-linux-server-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const outfile = path.join(directory, "server.mjs");
  await build({
    ...linuxBuildOptions,
    entryPoints: [fileURLToPath(new URL("../src/linux/server.ts", import.meta.url))],
    outfile,
  });
  execFileSync(process.execPath, ["--check", outfile], { stdio: "pipe" });

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
      VECTOR_RECOGNITION_BASE_URL: "https://recognition.invalid",
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
