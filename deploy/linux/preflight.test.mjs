import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { once } from "node:events";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { runPreflight, validateDeploymentEnvironment } from "./preflight.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const migrations = readdirSync(new URL("../../apps/workers-api/src/db/postgres/migrations", import.meta.url)).filter((name) => name.endsWith(".sql")).sort();
const environment = {
  APP_ENVIRONMENT: "development", POSTGRES_DB: "toccards_test", POSTGRES_USER: "toccards",
  POSTGRES_PASSWORD: "test-password", DATABASE_URL: "postgres://toccards:test-password@db:5432/toccards_test",
  JWT_SECRET: "independent-test-secret", OBJECT_STORAGE_PATH: "/data/scan-images",
  ALLOWED_ORIGINS: "http://192.168.50.201:8080", VECTOR_RECOGNITION_BASE_URL: "https://recognize-vec.tcgcard.fun",
};

test("dev deployment rejects cloud database URLs before any process can change containers", () => {
  for (const host of ["aws-us-east-1-5.pg.psdb.cloud", "192.168.50.201"]) {
    assert.throws(() => validateDeploymentEnvironment({ ...environment, DATABASE_URL: `postgres://toccards:test-password@${host}:5432/toccards_test` }), /Compose db:5432/);
  }
  assert.throws(() => validateDeploymentEnvironment({ ...environment, APP_ENVIRONMENT: "production" }), /APP_ENVIRONMENT=development/);
  assert.throws(() => validateDeploymentEnvironment({ ...environment, POSTGRES_PASSWORD: "different-secret" }), /matching POSTGRES/);
  assert.throws(() => validateDeploymentEnvironment({ ...environment, VECTOR_RECOGNITION_BASE_URL: undefined }), /VECTOR_RECOGNITION_BASE_URL is required/);
});

test("preflight lists missing migrations and checks the recognition contract using only read-only database commands", async (t) => {
  const server = createServer((request, response) => {
    assert.equal(request.method, "GET");
    assert.equal(request.url, "/health");
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({ ok: true, dimensions: 512, metric: "cosine", top_k: 5 }));
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => { server.closeAllConnections(); server.close(); });
  const commands = [];
  const result = await runPreflight(root, {
    ...environment, VECTOR_RECOGNITION_BASE_URL: `http://127.0.0.1:${server.address().port}`,
  }, (args) => {
    commands.push(args);
    return databaseCommand(args, { migrations: migrations.slice(0, -1) });
  });
  assert.deepEqual(result.pendingMigrations, [migrations.at(-1)]);
  assert.deepEqual(commands.map((args) => args[0]), ["ps", "inspect", "exec"]);
  assert.ok(commands[2].some((arg) => arg.includes("default_transaction_read_only=on")));
  assert.ok(commands[2].some((arg) => arg.includes("-h 127.0.0.1")));
  assert.ok(!commands[2].includes(environment.POSTGRES_PASSWORD));
});

test("preflight refuses a major-version mismatch, stopped database or schema newer than the release", async () => {
  await assert.rejects(runPreflight(root, environment, (args) => databaseCommand(args, { version: "160010" })), /PostgreSQL 18/);
  await assert.rejects(runPreflight(root, environment, (args) => args[0] === "inspect" ? "false" : databaseCommand(args)), /database is stopped/);
  await assert.rejects(runPreflight(root, environment, (args) => databaseCommand(args, { migrations: [...migrations, "9999_unknown.sql"] })), /ahead of this release/);
});

test("an unrelated healthy HTTP service cannot satisfy the CF recognition preflight", async (t) => {
  const server = createServer((_request, response) => response.end(JSON.stringify({ status: "ok" })));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => { server.closeAllConnections(); server.close(); });
  await assert.rejects(runPreflight(root, {
    ...environment, VECTOR_RECOGNITION_BASE_URL: `http://127.0.0.1:${server.address().port}`,
  }, databaseCommand), /512-dimensional cosine contract/);
});

test("manual deployment requires an explicit SSH destination before building or touching a server", () => {
  assert.throws(() => execFileSync(process.execPath, [fileURLToPath(new URL("./deploy-dev.mjs", import.meta.url))], {
    env: { ...process.env, TOCCARDS_SSH_TARGET: "" }, stdio: "pipe",
  }), (error) => error.status === 1 && error.stderr.toString().includes("Set TOCCARDS_SSH_TARGET"));
});

test("preflight invoked through the current release symlink must still reject an invalid deployment", (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), "kando-preflight-symlink-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const current = path.join(directory, "current");
  symlinkSync(root, current, process.platform === "win32" ? "junction" : "dir");
  assert.throws(() => execFileSync(process.execPath, [path.join(current, "deploy/linux/preflight.mjs"), current], {
    env: { ...process.env, ...environment, APP_ENVIRONMENT: "production" }, stdio: "pipe",
  }), (error) => error.status === 1 && error.stderr.toString().includes("Linux deployment requires APP_ENVIRONMENT=development"));
});

test("an existing database is backed up even when the current release symlink is missing", (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), "kando-deploy-backup-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const releaseScript = readFileSync(new URL("./ci/deploy-release.sh", import.meta.url), "utf8");
  const backup = releaseScript.match(/backup_database\(\) \{[\s\S]*?\n\}/)[0];
  execFileSync(bashExecutable(), ["--noprofile", "--norc", "-s"], {
    env: { ...process.env, TEST_BACKUP_DIRECTORY: directory.replaceAll("\\", "/") },
    input: `set -Eeuo pipefail\nprevious_release=''\nbackups_dir="$TEST_BACKUP_DIRECTORY"\nrelease_id=fixture\ndocker() { if [[ "$1" == inspect ]]; then printf 'true'; else printf 'PGDMP-test-backup'; fi; }\n${backup}\nbackup_database\n`,
    encoding: "utf8", stdio: ["pipe", "pipe", "pipe"],
  });
  const backups = readdirSync(directory).filter((name) => name.endsWith(".dump"));
  assert.equal(backups.length, 1);
  assert.equal(readFileSync(path.join(directory, backups[0]), "utf8"), "PGDMP-test-backup");
});

test("a failed preflight stops the real release script before backup or container changes", (t) => {
  const directory = mkdtempSync(path.join(tmpdir(), "kando-deploy-preflight-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const artifact = path.join(directory, "artifact");
  const script = readFileSync(new URL("./ci/deploy-release.sh", import.meta.url), "utf8");
  const paths = [...script.match(/required_paths=\(([\s\S]*?)\n\)/)[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  for (const name of paths) {
    mkdirSync(path.dirname(path.join(artifact, name)), { recursive: true });
    writeFileSync(path.join(artifact, name), "fixture");
  }
  const envFile = path.join(directory, "private.env");
  writeFileSync(envFile, "APP_ENVIRONMENT=development\n");
  assert.throws(() => execFileSync(bashExecutable(), ["--noprofile", "--norc", "-s"], {
    env: {
      ...process.env,
      TOCCARDS_DEPLOY_ROOT: path.join(directory, "deployment").replaceAll("\\", "/"),
      TOCCARDS_ENV_FILE: envFile.replaceAll("\\", "/"),
      TEST_RELEASE_SCRIPT: fileURLToPath(new URL("./ci/deploy-release.sh", import.meta.url)).replaceAll("\\", "/"),
      TEST_ARTIFACT: artifact.replaceAll("\\", "/"),
      TEST_DOCKER_CALLS: path.join(directory, "docker-called").replaceAll("\\", "/"),
    },
    input: 'flock() { return 0; }\nnode() { return 9; }\ndocker() { touch "$TEST_DOCKER_CALLS"; }\nsource "$TEST_RELEASE_SCRIPT" "$TEST_ARTIFACT"\n',
    encoding: "utf8", stdio: ["pipe", "pipe", "pipe"],
  }), (error) => error.status === 9);
  assert.equal(existsSync(path.join(directory, "docker-called")), false);
  assert.deepEqual(readdirSync(path.join(directory, "deployment/backups")), []);
});

function bashExecutable() {
  if (process.platform !== "win32") return "bash";
  return path.resolve(execFileSync("git", ["--exec-path"], { encoding: "utf8" }).trim(), "../../../bin/bash.exe");
}

function databaseCommand(args, overrides = {}) {
  if (args[0] === "ps") return "toccards-linux-test-db-1";
  if (args[0] === "inspect") return "true";
  if (args[0] === "exec") return JSON.stringify({ database: "toccards_test", username: "toccards", version: "180006", migrations, ...overrides });
  throw new Error(`Unexpected Docker command: ${args[0]}`);
}
