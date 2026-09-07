import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDirectory = dirname(fileURLToPath(import.meta.url));

describe("PostgreSQL Apple notification app scope migration", () => {
  it("isolates pre-verification inbox leases by trusted Bundle because dev and production share Sandbox storage", () => {
    const migration = readFileSync(
      join(testDirectory, "migrations/0009_apple_notification_app_bundle.sql"),
      "utf8",
    ).replace(/\s+/g, " ").trim();

    expect(migration).toContain("ADD COLUMN app_bundle_id text");
    expect(migration).toContain("WHEN 'Sandbox' THEN 'com.kando.kandoApp.beta'");
    expect(migration).toContain("WHEN 'Production' THEN 'com.cardai.tcg'");
    expect(migration).toContain("ALTER COLUMN app_bundle_id SET NOT NULL");
    expect(migration).toContain(
      "CREATE TRIGGER trg_legacy_apple_notification_app_bundle BEFORE INSERT ON apple_notification_inbox",
    );
    expect(migration).toContain(
      "UNIQUE (app_bundle_id, environment, payload_sha256)",
    );
    expect(migration).toContain(
      "app_bundle_id, environment, processing_status, processing_expires_at, received_at",
    );
  });
});
