import type { Env } from "../env";
import { authenticateOwner } from "../owner-auth";
import { verifyAndroidInstallation, type AndroidPlayBuild, type AndroidIntegrityBinding } from "./android-integrity";
import type { AuthPlatform } from "./platform-account";

export type AuthPlatformResult =
  | { status: "ok"; platform: AuthPlatform; build?: AndroidPlayBuild }
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
    return typeof verification !== "string" ? { ...verification, status: "ok", platform: "android" }
      : { status: verification === "invalid" ? "unauthorized" : "unavailable" };
  }
  if (authorization) {
    const auth = await authenticateOwner(env, authorization);
    if (auth.status !== "ok") {
      return { status: auth.status === "internal_error" ? "unavailable" : "unauthorized" };
    }
    if (!auth.owner.platform) return { status: "unavailable" };
    if (platform && auth.owner.platform !== platform) return { status: "unauthorized" };
    if (auth.owner.platform === "android" && env.ANDROID_PLAY_PACKAGE_NAME?.trim()) {
      const build = await env.DB.prepare(`SELECT package_name, certificate_digest, version_code, verified_at
        FROM google_play_session_build WHERE session_id = ? AND package_name = ?`)
        .bind(auth.owner.session_id, env.ANDROID_PLAY_PACKAGE_NAME.trim()).first<AndroidPlayBuild>();
      if (build) return { status: "ok", platform: "android", build };
    }
    return { status: "ok", platform: auth.owner.platform };
  }
  if (platform === "android") return { status: "unauthorized" };
  return { status: "ok", platform: "ios" };
}
