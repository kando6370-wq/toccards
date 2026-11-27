import type { Env } from "../env";
import { googlePlayAccess } from "../google-play/access";
import type { AuthenticatedOwner } from "../owner-auth";
import { resolvePremiumAccess, type PremiumAccess } from "./premium-access";

export async function platformAccess(
  env: Env, owner: AuthenticatedOwner, localState: string | undefined,
  appleAccess: (env: Env, session: string, localState: string | undefined) => Promise<PremiumAccess> = resolvePremiumAccess,
): Promise<{ access: PremiumAccess; freeLaunch: boolean; cohort: string | null }> {
  if (owner.platform === "android") {
    const policy = await googlePlayAccess(env, owner);
    return { access: policy.premium ? "premium" : "free", freeLaunch: policy.access_policy !== "metered", cohort: policy.cohort };
  }
  return { access: await appleAccess(env, owner.session_id, localState), freeLaunch: false, cohort: null };
}
