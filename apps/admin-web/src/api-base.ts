type ViteEnvironment = {
  DEV: boolean;
  VITE_API_BASE_URL?: string;
};

export function resolveAdminApiBase(environment: ViteEnvironment): string {
  const configuredBase = environment.VITE_API_BASE_URL?.trim();
  if (configuredBase) return configuredBase.replace(/\/+$/, "");
  if (environment.DEV) return "/api/v1/admin";
  throw new Error("VITE_API_BASE_URL is required for admin production builds");
}
