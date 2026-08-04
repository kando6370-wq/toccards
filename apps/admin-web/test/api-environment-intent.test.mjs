import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const adminPackage = JSON.parse(
  await readFile(new URL("../package.json", import.meta.url), "utf8"),
);
const workersPackage = JSON.parse(
  await readFile(new URL("../../workers-api/package.json", import.meta.url), "utf8"),
);
const productionEnvironment = await readFile(
  new URL("../.env.production", import.meta.url),
  "utf8",
);
const developmentEnvironment = await readFile(
  new URL("../.env.development", import.meta.url),
  "utf8",
);
const apiBase = await readFile(new URL("../src/api-base.ts", import.meta.url), "utf8");

test("prod and dev builds use isolated APIs because admin actions must not cross environments", () => {
  assert.equal(adminPackage.scripts["build:prod"], "vite build --mode production");
  assert.equal(adminPackage.scripts["build:dev"], "vite build --mode development");
  assert.match(productionEnvironment, /^VITE_API_BASE_URL=https:\/\/api\.tcgcard\.fun\/api\/v1\/admin\s*$/);
  assert.match(developmentEnvironment, /^VITE_API_BASE_URL=https:\/\/api-dev\.tcgcard\.fun\/api\/v1\/admin\s*$/);
  assert.match(workersPackage.scripts["deploy:prod"], /build:assets:prod/);
  assert.match(workersPackage.scripts["deploy:dev"], /build:assets:dev/);
});

test("non-development builds fail loudly when their API environment is missing", () => {
  assert.match(apiBase, /if \(environment\.DEV\) return "\/api\/v1\/admin"/);
  assert.match(apiBase, /throw new Error\("VITE_API_BASE_URL is required/);
});
