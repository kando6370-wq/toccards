import { Hono } from "hono";
import type { Env } from "../env";

type AppConfigRow = {
  key: string;
  value: string;
};

type PublicUpgradePrompt = {
  latest_version: string;
  force_update: boolean;
  title: string;
  message: string;
  store_url: string | null;
};

const SELECT_PUBLIC_APP_CONFIG_SQL = `
  SELECT key, value
  FROM app_config
  ORDER BY key ASC
`;

const PUBLIC_APP_CONFIG_KEYS = new Set(["upgrade_prompt", "app_store_url"]);

export function createAppConfigRoutes(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();

  routes.get("/app-config", async (c) => {
    const { results = [] } = await c.env.DB.prepare(
      SELECT_PUBLIC_APP_CONFIG_SQL,
    ).all<AppConfigRow>();
    const configs = publicConfigMap(results);

    return c.json({
      success: true,
      data: {
        upgrade_prompt: parseUpgradePrompt(configs.get("upgrade_prompt")),
        app_store_url: stringOrNull(configs.get("app_store_url")),
      },
    });
  });

  return routes;
}

function publicConfigMap(rows: AppConfigRow[]): Map<string, string> {
  const configs = new Map<string, string>();

  for (const row of rows) {
    if (PUBLIC_APP_CONFIG_KEYS.has(row.key)) {
      configs.set(row.key, row.value);
    }
  }

  return configs;
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
