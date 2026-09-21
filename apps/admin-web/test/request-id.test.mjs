import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const requestIdSource = await readFile(
  new URL("../src/request-id.ts", import.meta.url),
  "utf8",
);
const appSource = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");

test("Admin uses a UUID request id helper for every data fetch", () => {
  assert.match(requestIdSource, /export const REQUEST_ID_HEADER = "X-Request-ID"/);
  assert.match(requestIdSource, /crypto\.randomUUID\(\)/);
  assert.match(requestIdSource, /headers\.set\(REQUEST_ID_HEADER,/);
  assert.equal(
    [...appSource.matchAll(/createAdminRequestHeaders\(/g)].length,
    3,
    "JSON requests, file downloads and authenticated scan images must share request correlation",
  );
});
