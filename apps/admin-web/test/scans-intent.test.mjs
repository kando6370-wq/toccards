import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const css = await readFile(new URL("../src/App.css", import.meta.url), "utf8");

test("scan images use authenticated blobs because private R2 keys must not become public image URLs", () => {
  assert.match(app, /Authorization: `Bearer \$\{session\.accessToken\}`/);
  assert.match(app, /URL\.createObjectURL\(blob\)/);
  assert.match(app, /URL\.revokeObjectURL\(objectUrl\)/);
  assert.doesNotMatch(app, /numeric <= 1/);
  assert.match(app, /confidence: 80\.99/);
  assert.match(app, /confidence: 80\.729/);
});

test("scan visual rules are page-scoped because other admin modules must not change", () => {
  for (const selector of ["scan-thumb", "scan-preview", "detail-section", "info-grid", "candidate-card"]) {
    assert.doesNotMatch(css, new RegExp(`(^|\\n)\\.${selector}\\s*\\{`));
  }
  assert.match(css, /\.scans-page \.scan-thumb/);
  assert.match(css, /\.scan-detail-drawer \.detail-section/);
});
