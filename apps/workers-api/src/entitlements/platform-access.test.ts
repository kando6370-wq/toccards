import { describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import type { AuthenticatedOwner } from "../owner-auth";
import { platformAccess } from "./platform-commercial-access";

describe("platform-scoped access", () => {
  it("keeps the free Android release usable without Apple credentials and delegates iOS to the verified Apple session", async () => {
    const apple = vi.fn(async () => "sync_required" as const);
    const owner = { platform: "android", session_id: "installation" } as AuthenticatedOwner;
    expect(await platformAccess({} as Env, owner, "verified", apple)).toEqual({ access: "free", freeLaunch: true, cohort: null });
    expect(apple).not.toHaveBeenCalled();
    expect((await platformAccess({} as Env, { ...owner, platform: "ios" }, "verified", apple)).access).toBe("sync_required");
    expect(apple).toHaveBeenCalledWith({}, "installation", "verified");
  });
});
