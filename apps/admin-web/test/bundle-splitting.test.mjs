import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const viteConfig = await readFile(new URL("../vite.config.ts", import.meta.url), "utf8");

test("large UI dependencies use explicit vendor boundaries so routine admin changes do not invalidate the entire bundle", () => {
  assert.match(viteConfig, /onlyExplicitManualChunks: true/);
  for (const chunk of ["react-vendor", "query-vendor", "antd-rc", "antd-vendor", "date-vendor"]) {
    assert.match(viteConfig, new RegExp(`return "${chunk}"`));
  }
  assert.match(viteConfig, /id\.includes\("@babel\/runtime"\)/);
  assert.doesNotMatch(viteConfig, /chunkSizeWarningLimit/);
});
