import { afterAll, beforeAll, describe, expect, it } from "vitest";
import app from "../index";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";

describe("public app configuration", () => {
  let db: PGliteDatabase;
  beforeAll(async () => {
    db = await PGliteDatabase.create();
    await db.exec("CREATE TABLE app_config (key text PRIMARY KEY, value text NOT NULL, updated_at text NOT NULL)");
    const values: Record<string, string> = {
      "admin.app_version.development.ios": JSON.stringify({
        platform: "iOS", min_supported_version: "1.0.1", recommended_version: "1.0.2",
        force_update: true, status: "enabled", store_url: "https://apps.apple.com/app/id6793017224",
        recommended_update_message: "A new version is available.", forced_update_message: "Update to continue.",
      }),
      card_share_base_url: "https://api-dev.tcgcard.fun/share/cards",
      terms_url: "https://www.tcgcard.fun/terms",
      privacy_url: "https://www.tcgcard.fun/privacy",
      announcement: "Admin only",
    };
    for (const [key, value] of Object.entries(values)) {
      await db.prepare("INSERT INTO app_config VALUES (?, ?, '2026-09-08')").bind(key, value).run();
    }
  });
  afterAll(async () => { await db?.close(); });

  it("serves the environment's update rule, legal links and client SDK configuration without Admin authentication", async () => {
    const env: Env = {
      DB: db, APP_ENVIRONMENT: "development", CACHE_KV: {} as KVNamespace, JWT_SECRET: "unused-test-secret",
      MIXPANEL_PROJECT_TOKEN: "public-project-token", MIXPANEL_API_SECRET: "server-api-secret",
      SINGULAR_API_KEY: "client-sdk-key", SINGULAR_SECRET_KEY: "client-sdk-secret",
    };
    const response = await app.request("/api/v1/app-config", {}, env);
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({ success: true, data: {
      upgrade_prompt: {
        latest_version: "1.0.2", min_version: "1.0.1", force_update: true,
        title: "Update Now", message: "New update available! Tap to upgrade",
        forced_message: "New update available! Tap to upgrade", store_url: "https://apps.apple.com/app/id6793017224",
      },
      app_store_url: "https://apps.apple.com/app/id6793017224",
      card_share_base_url: "https://api-dev.tcgcard.fun/share/cards",
      terms_url: "https://www.tcgcard.fun/terms", privacy_url: "https://www.tcgcard.fun/privacy",
      mixpanel_project_token: "public-project-token", singular_api_key: "client-sdk-key", singular_secret_key: "client-sdk-secret",
    } });
    expect(JSON.stringify(body)).not.toContain("server-api-secret");
    expect(JSON.stringify(body)).not.toContain("Admin only");
  });
});
