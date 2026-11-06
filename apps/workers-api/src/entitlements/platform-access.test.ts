import { describe, expect, it } from "vitest";
import {
  platformCommercialAccess,
  usesAndroidFreeLaunch,
} from "./platform-commercial-access";

describe("platform-scoped free access", () => {
  it("opens Android capabilities without treating legacy or iOS owners as Android", () => {
    expect(platformCommercialAccess({ platform: "android" })).toBe("android_free_launch");
    expect(platformCommercialAccess({ platform: "ios" })).toBe("ios_apple_entitlement");
    expect(platformCommercialAccess({})).toBe("ios_apple_entitlement");
    expect(usesAndroidFreeLaunch({ platform: "android" })).toBe(true);
  });
});
