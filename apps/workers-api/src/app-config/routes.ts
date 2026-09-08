import { Hono } from "hono";
import type { Env } from "../env";
import {
  appVersionConfigKey,
  appVersionEnvironment,
  isValidAppVersionRule,
  VERSION_CONFIG_UNAVAILABLE,
} from "./app-version-config";

type AppConfigRow = {
  key: string;
  value: string;
};

type PublicUpgradePrompt = {
  latest_version: string;
  min_version?: string;
  force_update: boolean;
  title: string;
  message: string;
  store_url: string | null;
  forced_message?: string;
};

const SELECT_PUBLIC_APP_CONFIG_SQL = `
  SELECT key, value
  FROM app_config
  WHERE key IN (?, 'card_share_base_url', 'terms_url', 'privacy_url')
  ORDER BY key ASC
`;

export function createAppConfigRoutes(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();

  routes.get("/app-config", async (c) => {
    c.header("Cache-Control", "no-store");
    const environment = appVersionEnvironment(c.env.APP_ENVIRONMENT);
    if (!environment) return c.json(VERSION_CONFIG_UNAVAILABLE, 503);
    const platform = normalizePlatform(c.req.query("platform"));
    const versionKey = appVersionConfigKey(environment, platform);
    const { results = [] } = await c.env.DB.prepare(
      SELECT_PUBLIC_APP_CONFIG_SQL,
    ).bind(versionKey).all<AppConfigRow>();
    const configs = new Map(results.map((row) => [row.key, row.value]));
    const version = parseVersionRule(configs.get(versionKey));
    if (!version) return c.json(VERSION_CONFIG_UNAVAILABLE, 503);

    return c.json({
      success: true,
      data: {
        upgrade_prompt: version.status === "enabled" ? toUpgradePrompt(version) : null,
        app_store_url: stringOrNull(version.store_url),
        card_share_base_url: stringOrNull(configs.get("card_share_base_url")),
        terms_url: stringOrNull(configs.get("terms_url")),
        privacy_url: stringOrNull(configs.get("privacy_url")),
        mixpanel_project_token: stringOrNull(c.env.MIXPANEL_PROJECT_TOKEN),
        singular_api_key: stringOrNull(c.env.SINGULAR_API_KEY),
        singular_secret_key: stringOrNull(c.env.SINGULAR_SECRET_KEY),
      },
    });
  });

  return routes;
}

function parseVersionRule(value: string | undefined): Record<string, unknown> | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(value) as unknown;
    return isRecord(parsed) && isValidAppVersionRule(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function toUpgradePrompt(parsed: Record<string, unknown>): PublicUpgradePrompt {
  return {
    latest_version: parsed.recommended_version as string,
    min_version: parsed.min_supported_version as string,
    force_update: parsed.force_update === true,
    title: "Update available",
    message:
      stringOrNull(parsed.recommended_update_message) ??
      "Please install the latest Kando version.",
    forced_message:
      stringOrNull(parsed.forced_update_message) ??
      "Please update Kando to continue.",
    store_url: stringOrNull(parsed.store_url),
  };
}

function normalizePlatform(value: string | undefined): "ios" | "google" {
  return value?.trim().toLowerCase() === "google" ? "google" : "ios";
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
