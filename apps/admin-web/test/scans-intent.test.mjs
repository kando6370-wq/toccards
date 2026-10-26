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

test("scan search reloads when filters are unchanged because every query click must call the paginated API", () => {
  assert.match(
    app,
    /function applyScanFilters\(\) \{[\s\S]*?setPage\(1\);[\s\S]*?setFilters\(draft\);[\s\S]*?reload\(\);[\s\S]*?\}/,
  );
  assert.match(app, /onClick=\{applyScanFilters\}>查询<\/Button>/);
});

test("scan records expose and filter the persisted app environment", () => {
  assert.match(app, /type ScanListItem = \{[\s\S]*?environment: string;/);
  assert.match(app, /<ScanFilterField label="环境">[\s\S]*?draft\.environment/);
  assert.match(app, /title: "环境", dataIndex: "environment"/);
});

test("candidate artwork opens a preview because reviewers need to inspect details without leaving the scan", () => {
  const drawer = app.slice(app.indexOf("function ScanDetailDrawer("), app.indexOf("function AuthenticatedScanImage("));
  const thumbnail = drawer.match(/<span className="candidate-thumb">([\s\S]*?)<\/span>/)?.[1] ?? "";
  assert.match(thumbnail, /typeof candidate\.image_url === "string" && candidate\.image_url/);
  assert.match(thumbnail, /<Image\b/);
  assert.match(thumbnail, /src=\{candidate\.image_url\}/);
  assert.match(thumbnail, /preview=\{\{ mask: false \}\}/);
  assert.match(thumbnail, /width="100%"[\s\S]*?height="100%"/);
  assert.match(drawer, /<AuthenticatedScanImage path=\{scan\.image_url\} session=\{session\}/);
});

test("scan detail image opens an authenticated preview while list thumbnails keep their existing behavior", () => {
  const drawer = app.slice(app.indexOf("function ScanDetailDrawer("), app.indexOf("function AuthenticatedScanImage("));
  const authenticatedImage = app.slice(app.indexOf("function AuthenticatedScanImage("), app.indexOf("function DetailSection("));

  assert.match(drawer, /<AuthenticatedScanImage path=\{scan\.image_url\} session=\{session\} className="scan-preview" preview \/>/);
  assert.match(authenticatedImage, /preview = false/);
  assert.match(authenticatedImage, /return source[\s\S]*?preview[\s\S]*?<Image[\s\S]*?src=\{source\}[\s\S]*?title="点击放大"[\s\S]*?preview=\{\{ mask: false \}\}/);
  assert.match(authenticatedImage, /<img className=\{className\} src=\{source\} alt="扫描卡牌" \/>/);
});

test("candidate preview wrappers keep the thumbnail layout and failed artwork has no empty preview target", () => {
  assert.match(css, /\.scan-detail-drawer \.candidate-card > div\s*\{/);
  assert.doesNotMatch(css, /\.scan-detail-drawer \.candidate-card div\s*\{/);
  assert.match(css, /\.scan-detail-drawer \.candidate-thumb \.ant-image-error\s*\{\s*display: none;/);
});

test("scan detail shows persisted OCR text and leaves missing values blank", () => {
  const drawer = app.slice(app.indexOf("function ScanDetailDrawer("), app.indexOf("function AuthenticatedScanImage("));

  assert.match(drawer, /label: "OCR 文本", value: displayOptionalText\(scan\.system_result\.ocr_text\)/);
  assert.match(app, /function displayOptionalText\(value: unknown\) \{\s*return typeof value === "string" \? value : "";\s*\}/);
});
