import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const countryName = await readFile(new URL("../src/country-name.ts", import.meta.url), "utf8");
const css = await readFile(new URL("../src/App.css", import.meta.url), "utf8");

test("user filters stay fixed while the table body reserves enough viewport space for pagination", () => {
  assert.match(app, /className="users-page"/);
  assert.match(app, /className="users-table-panel"/);
  assert.match(app, /tableLayout="fixed"/);
  assert.match(app, /title: "国家", dataIndex: "country", width: 90, ellipsis: true, render: countryName/);
  assert.match(countryName, /new Intl\.DisplayNames\(\["zh-CN"\], \{ type: "region" \}\)/);
  assert.match(app, /scroll=\{\{ x: 760, y: "calc\(100dvh - 470px\)" \}\}/);
  assert.match(css, /\.users-page \{[\s\S]*?overflow: hidden;/);
  assert.match(css, /\.users-page \.filter-bar \{[\s\S]*?position: sticky;/);
  assert.match(css, /\.users-table-panel \.ant-table-body \{[\s\S]*?height: clamp\(220px, calc\(100dvh - 470px\), 520px\)/);
  assert.match(css, /\.users-table-panel \.ant-pagination \{[\s\S]*?flex: 0 0 auto;[\s\S]*?margin-bottom: 0;/);
});
