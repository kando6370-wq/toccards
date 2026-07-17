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
  assert.doesNotMatch(app, /demoScanDetail/);
});

test("admin runtime has no demo session or static data fallback because API failures must stay visible", () => {
  assert.doesNotMatch(app, /demo_admin|local-token|demoAdminResponse/);
  assert.doesNotMatch(app, /demoInstallationAnalytics|demoUsers|demoFeedbacks|demoPermissions|demoAppVersions/);
  assert.doesNotMatch(app, /images\.pokemontcg\.io/);
  assert.match(app, /\.catch\(\(requestError\) => \{/);
  assert.match(app, /setError\(errorMessage\(requestError\)\)/);
});

test("scan visual rules are page-scoped because other admin modules must not change", () => {
  for (const selector of ["scan-thumb", "scan-preview", "detail-section", "info-grid", "candidate-card"]) {
    assert.doesNotMatch(css, new RegExp(`(^|\\n)\\.${selector}\\s*\\{`));
  }
  assert.match(css, /\.scans-page \.scan-thumb/);
  assert.match(css, /\.scan-detail-drawer \.detail-section/);
});
