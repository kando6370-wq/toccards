export type AppVersionEnvironment = "development" | "production";

export const APP_VERSION_CONFIG_PREFIX = "admin.app_version.";
export const VERSION_CONFIG_UNAVAILABLE = {
  success: false,
  error: { code: "APP_VERSION_CONFIG_UNAVAILABLE", message: "Version configuration is unavailable. Please try again." },
} as const;

export function appVersionEnvironment(value: unknown): AppVersionEnvironment | null {
  return value === "development" || value === "production" ? value : null;
}

export function appVersionConfigKey(environment: AppVersionEnvironment, platform: string): string {
  return `${APP_VERSION_CONFIG_PREFIX}${environment}.${platform.toLowerCase()}`;
}

export function isVersionConfigKey(key: string): boolean {
  return key.startsWith(APP_VERSION_CONFIG_PREFIX) || key === "upgrade_prompt" || key === "app_store_url";
}

export function isValidAppVersionRule(input: Record<string, unknown>): boolean {
  const minimum = parseVersion(input.min_supported_version);
  const recommended = parseVersion(input.recommended_version);
  if (!minimum || !recommended || typeof input.force_update !== "boolean"
    || (input.status !== "enabled" && input.status !== "disabled")) return false;
  for (let i = 0; i < minimum.length; i++) {
    if (minimum[i]! > recommended[i]!) return false;
    if (minimum[i]! < recommended[i]!) break;
  }
  if (typeof input.store_url !== "string") return false;
  if (!input.store_url.trim()) return input.status === "disabled";
  try {
    const url = new URL(input.store_url);
    return (url.protocol === "https:" || url.protocol === "http:") && !!url.hostname && !url.username && !url.password;
  } catch {
    return false;
  }
}

function parseVersion(value: unknown): number[] | null {
  if (typeof value !== "string" || !/^\d+\.\d+\.\d+$/.test(value)) return null;
  const parts = value.split(".").map(Number);
  return parts.every(Number.isSafeInteger) ? parts : null;
}
