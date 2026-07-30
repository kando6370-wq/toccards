import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const css = await readFile(new URL("../src/App.css", import.meta.url), "utf8");

test("user filters stay fixed while only the fixed-layout table body scrolls because account data lengths vary", () => {
  assert.match(app, /className="users-page"/);
  assert.match(app, /className="users-table-panel"/);
  assert.match(app, /tableLayout="fixed"/);
  assert.match(app, /scroll=\{\{ x: 840, y: "calc\(100dvh - 390px\)" \}\}/);
  assert.match(css, /\.users-page \{[\s\S]*?overflow: hidden;/);
  assert.match(css, /\.users-page \.filter-bar \{[\s\S]*?position: sticky;/);
  assert.match(css, /\.users-table-panel \.ant-table-body \{[\s\S]*?height: clamp/);
});
