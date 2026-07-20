import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");

test("authenticated 401 responses return to login because expired tokens must not leave the admin shell visible", () => {
  assert.match(app, /response\.status === 401/);
  assert.match(app, /window\.dispatchEvent\(new Event\(SESSION_EXPIRED_EVENT\)\)/);
  assert.match(app, /window\.addEventListener\(SESSION_EXPIRED_EVENT, handleSessionExpired\)/);
  assert.match(app, /setAuthView\("login"\)/);
  assert.match(app, /setSession\(null\)/);
  assert.match(app, /if \(token && response\.status === 401\)/);
  assert.match(app, /dispatchSessionExpiredOnUnauthorized\(response, init\.token\)/);
});

test("private scan image requests share expiry handling because they bypass the JSON request helper", () => {
  assert.match(app, /dispatchSessionExpiredOnUnauthorized\(response, session\.accessToken\)/);
});
