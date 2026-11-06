import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { resolveAuthPlatform } from "./platform";

const { authenticate } = vi.hoisted(() => ({ authenticate: vi.fn() }));
vi.mock("../owner-auth", () => ({ authenticateOwner: authenticate }));

const env = { APP_ENVIRONMENT: "development", ANDROID_INTEGRITY_ALLOW_DEVELOPMENT: "true" } as Env;

beforeEach(() => authenticate.mockReset());

describe("authentication platform binding", () => {
  it("preserves the legacy iOS authentication input without granting Android access", async () => {
    expect(await resolveAuthPlatform(env, undefined, undefined)).toEqual({ status: "ok", platform: "ios" });
    expect(await resolveAuthPlatform(env, undefined, "android")).toEqual({ status: "unauthorized" });
  });

  it("allows Android installation creation only through the installation-proof path", async () => {
    expect(await resolveAuthPlatform(env, undefined, "android", undefined, {
      deviceId: "test-installation", requestNonce: "isolated-test-request-nonce",
    })).toEqual({ status: "ok", platform: "android" });
    expect(authenticate).not.toHaveBeenCalled();
  });

  it.each(["", "web", "windows", "unknown", "google", 1])(
    "rejects an explicit unsupported platform %s instead of silently choosing iOS", async (platform) => {
      expect(await resolveAuthPlatform(env, undefined, platform)).toEqual({ status: "invalid" });
    },
  );

  it.each(["ios", "android"] as const)("inherits %s from a live server-side session when input omits the platform", async (platform) => {
    authenticate.mockResolvedValue({ status: "ok", owner: { platform } });
    expect(await resolveAuthPlatform(env, "Bearer fixture", undefined)).toEqual({ status: "ok", platform });
  });

  it.each([["ios", "android"], ["android", "ios"]] as const)("rejects a client attempt to change %s to %s", async (actual, requested) => {
    authenticate.mockResolvedValue({ status: "ok", owner: { platform: actual } });
    expect(await resolveAuthPlatform(env, "Bearer fixture", requested)).toEqual({ status: "unauthorized" });
  });

  it("never treats an invalid existing Android credential as a legacy iOS request", async () => {
    authenticate.mockResolvedValue({ status: "unauthorized" });
    expect(await resolveAuthPlatform(env, "Bearer revoked", undefined)).toEqual({ status: "unauthorized" });
  });
});
