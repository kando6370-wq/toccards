type ViteEnvironment = {
  DEV: boolean;
  VITE_API_BASE_URL?: string;
};

const PRODUCTION_ADMIN_API_BASE = "https://api.tcgcard.fun/api/v1/admin";

export function resolveAdminApiBase(environment: ViteEnvironment): string {
  const configuredBase = environment.VITE_API_BASE_URL?.trim();
  if (configuredBase) return configuredBase.replace(/\/+$/, "");
  return environment.DEV ? "/api/v1/admin" : PRODUCTION_ADMIN_API_BASE;
}
