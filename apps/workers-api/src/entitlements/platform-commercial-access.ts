import type { AuthenticatedOwner } from "../owner-auth";

export type PlatformCommercialAccess =
  | "android_free_launch"
  | "ios_apple_entitlement";

export function platformCommercialAccess(
  owner: Pick<AuthenticatedOwner, "platform"> | { platform?: unknown },
): PlatformCommercialAccess {
  return owner.platform === "android"
    ? "android_free_launch"
    : "ios_apple_entitlement";
}

export function usesAndroidFreeLaunch(
  owner: Pick<AuthenticatedOwner, "platform"> | { platform?: unknown },
): boolean {
  return platformCommercialAccess(owner) === "android_free_launch";
}
