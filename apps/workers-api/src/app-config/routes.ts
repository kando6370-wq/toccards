import { Hono } from "hono";
import type { Env } from "../env";

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
  ORDER BY key ASC
`;

const PUBLIC_APP_CONFIG_KEYS = new Set([
  "upgrade_prompt",
  "app_store_url",
  "terms_url",
  "privacy_url",
]);

export function createAppConfigRoutes(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();

  routes.get("/app-config", async (c) => {
    const { results = [] } = await c.env.DB.prepare(
      SELECT_PUBLIC_APP_CONFIG_SQL,
    ).all<AppConfigRow>();
    const configs = configMap(results);
    const platform = normalizePlatform(c.req.query("platform"));
    const platformVersion = configs.get(`admin.app_version.${platform}`);

    return c.json({
      success: true,
      data: {
        upgrade_prompt: platformVersion === undefined
          ? parseUpgradePrompt(configs.get("upgrade_prompt"))
          : parseAdminUpgradePrompt(platformVersion),
        app_store_url: stringOrNull(configs.get("app_store_url")),
        terms_url: stringOrNull(configs.get("terms_url")),
        privacy_url: stringOrNull(configs.get("privacy_url")),
      },
    });
  });

  return routes;
}

function configMap(rows: AppConfigRow[]): Map<string, string> {
  const configs = new Map<string, string>();

  for (const row of rows) {
    if (
      PUBLIC_APP_CONFIG_KEYS.has(row.key) ||
      row.key.startsWith("admin.app_version.")
    ) {
      configs.set(row.key, row.value);
    }
  }

  return configs;
}

function parseAdminUpgradePrompt(value: string | undefined): PublicUpgradePrompt | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(value) as unknown;
    if (!isRecord(parsed) || parsed.status !== "enabled") return null;
    const latestVersion = stringOrNull(parsed.recommended_version);
    const minVersion = stringOrNull(parsed.min_supported_version);
    if (!latestVersion || !minVersion) return null;
    return {
      latest_version: latestVersion,
      min_version: minVersion,
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
  } catch {
    return null;
  }
}

function normalizePlatform(value: string | undefined): "ios" | "google" {
  return value?.trim().toLowerCase() === "google" ? "google" : "ios";
}

function parseUpgradePrompt(value: string | undefined): PublicUpgradePrompt | null {
  if (!value) return null;

  try {
    const parsed = JSON.parse(value) as unknown;
    if (!isRecord(parsed)) return null;

    const latestVersion =
      stringOrNull(parsed.latest_version) ?? stringOrNull(parsed.min_version);
    if (!latestVersion) return null;

    return {
      latest_version: latestVersion,
      force_update: parsed.force_update === true,
      title: stringOrNull(parsed.title) ?? "Update available",
      message:
        stringOrNull(parsed.message) ??
        "Please install the latest Kando version.",
      store_url: stringOrNull(parsed.store_url),
    };
  } catch {
    return null;
  }
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
