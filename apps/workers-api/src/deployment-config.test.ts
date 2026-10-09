import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const directory = dirname(fileURLToPath(import.meta.url));
const config = readFileSync(join(directory, "../wrangler.toml"), "utf8");

describe("production Worker deployment configuration", () => {
  it("keeps service-wide settings explicit because version deployment synchronizes them outside the script", () => {
    expect(config).toMatch(/\[observability\]\s+enabled = true/);
    expect(config).toMatch(/\[cache\]\s+enabled = true/);
    expect(config).toMatch(/\[env\.prod\][\s\S]*?workers_dev = false\s+preview_urls = false/);
    expect(config).toContain('zone_name = "tcgcard.fun"');
    expect(config).toContain("enabled = true, previews_enabled = false");
    expect(config).toMatch(
      /\[\[env\.prod\.services\]\][\s\S]*?service = "recognize-vec"\s+environment = "production"/,
    );
  });

  it("uses Smart Placement only for production because database round trips should not retarget Linux dev", () => {
    expect(config).toMatch(/\[env\.prod\.placement\]\s+mode = "smart"/);
    expect(config).not.toMatch(/^\[placement\]/m);
  });

  it("uses a separate native plugin limiter so Workers isolates do not each get an unlimited local counter", () => {
    expect(config).toMatch(/\[\[env\.prod\.ratelimits\]\][\s\S]*?name = "EXTENSION_RECOGNITION_RATE_LIMITER"/);
    expect(config).toContain('namespace_id = "2026100801"');
    expect(config).toContain("simple = { limit = 60, period = 60 }");
    expect(config).not.toContain("EXTENSION_RECOGNITION_KEY");
  });

  it("cannot restore retired Cloudflare dev or D1 deployment targets", () => {
    expect(config).not.toContain("[env.dev]");
    expect(config).not.toContain("d1_databases");
  });
});
