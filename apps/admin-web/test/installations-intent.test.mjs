import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { installationTrendForPeriod } from "../src/installation-analytics.ts";

const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const css = await readFile(new URL("../src/App.css", import.meta.url), "utf8");

test("installation filters drive the API because search and reset must change the displayed statistics", () => {
  assert.match(app, /const \[draft, setDraft\] = useState<InstallationFilters>/);
  assert.match(app, /const \[filters, setFilters\] = useState<InstallationFilters>/);
  assert.match(app, /\/analytics\/installations\?\$\{params\.toString\(\)\}/);
  assert.match(app, /function applyInstallationFilters\(\)[\s\S]*?setFilters\(\{ \.\.\.draft \}\);[\s\S]*?reload\(\);/);
  assert.match(app, /function resetInstallationFilters\(\)[\s\S]*?setDraft\(empty\);[\s\S]*?setFilters\(empty\);[\s\S]*?setDateRangeKey/);
  assert.match(app, /onClick=\{applyInstallationFilters\}>搜索<\/Button>/);
  assert.match(app, /onClick=\{resetInstallationFilters\}>重置<\/Button>/);
});

test("installation periods and chart points are interactive because operators must inspect the selected time window", () => {
  assert.match(app, /installationTrendForPeriod\(data\?\.trend \?\? \[\], period, filters\.date_to\)/);
  assert.match(app, /onClick=\{\(\) => setSelectedDate\(item\.date\)\}/);
  assert.match(app, /tabIndex=\{0\}/);
  assert.match(app, /className="chart-tooltip"/);
  assert.match(css, /\.line-chart \.chart-point \{[\s\S]*?cursor: pointer;/);
  assert.doesNotMatch(app, /index < INSTALLATION_PERIOD_OPTIONS\.length \? INSTALLATION_PERIOD_OPTIONS\[index\]/);
});

test("installation periods use inclusive UTC windows ending at the applied filter date", () => {
  const data = [
    { date: "2026-05-29", total: 1 },
    { date: "2026-05-30", total: 2 },
    { date: "2026-07-29", total: 3 },
    { date: "2026-08-12", total: 4 },
    { date: "2026-08-13", total: 5 },
    { date: "2026-08-21", total: 6 },
    { date: "2026-08-27", total: 7 },
    { date: "2026-08-28", total: 8 },
  ];

  assert.deepEqual(installationTrendForPeriod(data, "1d", "2026-08-27"), data.slice(6, 7));
  assert.deepEqual(installationTrendForPeriod(data, "7d", "2026-08-27"), data.slice(5, 7));
  assert.deepEqual(installationTrendForPeriod(data, "15d", "2026-08-27"), data.slice(4, 7));
  assert.deepEqual(installationTrendForPeriod(data, "1m", "2026-08-27"), data.slice(2, 7));
  assert.deepEqual(installationTrendForPeriod(data, "3m", "2026-08-27"), data.slice(1, 7));
});
