import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const directory = dirname(fileURLToPath(import.meta.url));
const scripts = JSON.parse(readFileSync(join(directory, "../package.json"), "utf8")).scripts;

describe("Workers default regression scope", () => {
  it("excludes generated deployment history without silently narrowing away existing tests outside src", () => {
    expect(scripts.test).toBe('vitest run --exclude "**/.wrangler/**"');
  });
});
