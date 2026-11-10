import type { Env } from "../env";
import { authenticateOwner } from "../owner-auth";
import { verifyAndroidInstallation, type AndroidIntegrityBinding } from "./android-integrity";
import type { AuthPlatform } from "./platform-account";

export type AuthPlatformResult =
  | { status: "ok"; platform: AuthPlatform }
  | { status: "unauthorized" | "unavailable" | "invalid" };

export async function resolveAuthPlatform(
  env: Env,
  authorization: string | undefined,
  requestedPlatform: unknown,
  integrityToken?: unknown,
  requestBinding?: AndroidIntegrityBinding,
): Promise<AuthPlatformResult> {
  const requested = typeof requestedPlatform === "string"
    ? requestedPlatform.trim().toLowerCase() : null;
  if (requestedPlatform != null && typeof requestedPlatform !== "string") return { status: "invalid" };
  if (requested !== null && requested !== "ios" && requested !== "android") {
    return { status: "invalid" };
  }
  const platform = requested as AuthPlatform | null;

  // A new Android installation must prove its package and request; an existing
  // session is sufficient only for subsequent sign-in on that same platform.
  if (requestBinding && platform === "android") {
    const verification = await verifyAndroidInstallation(env, integrityToken, requestBinding);
    return verification === "verified" ? { status: "ok", platform: "android" }
      : { status: verification === "invalid" ? "unauthorized" : "unavailable" };
  }
  if (authorization) {
    const auth = await authenticateOwner(env, authorization);
    if (auth.status !== "ok") {
      return { status: auth.status === "internal_error" ? "unavailable" : "unauthorized" };
    }
    if (!auth.owner.platform) return { status: "unavailable" };
    if (platform && auth.owner.platform !== platform) return { status: "unauthorized" };
    return { status: "ok", platform: auth.owner.platform };
  }
  if (platform === "android") return { status: "unauthorized" };
  return { status: "ok", platform: "ios" };
}
