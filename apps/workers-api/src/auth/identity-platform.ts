import type { Env } from "../env";
import { authenticateOwner } from "../owner-auth";
import { resolveAuthPlatform, type AuthPlatformResult } from "./platform";

export async function resolveIdentityAuthPlatform(
  env: Env,
  authorization: string | undefined,
  requestedPlatform: unknown,
): Promise<AuthPlatformResult> {
  const strict = await resolveAuthPlatform(env, authorization, requestedPlatform);
  if (strict.status !== "unauthorized") return strict;
  const requested = typeof requestedPlatform === "string"
    ? requestedPlatform.trim().toLowerCase()
    : null;
  if (requested === "android") return strict;

  const auth = await authenticateOwner(env, authorization);
  if (auth.status === "internal_error") return { status: "unavailable" };
  if (auth.status === "ok") {
    return auth.owner.platform === "ios"
      ? { status: "ok", platform: "ios" }
      : { status: "unauthorized" };
  }

  // Legacy iOS treats a stale guest token as failed migration proof. Email or
  // provider identity still authenticates; no guest assets are transferred.
  return { status: "ok", platform: "ios" };
}
