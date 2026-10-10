import { describe, expect, it } from "vitest";

import { extensionClientIp } from "./extension-client-ip";

function request(forwarded = "192.0.2.99") {
  return new Request("http://localhost/api/v1/extension/recognize", {
    headers: { "X-Forwarded-For": forwarded, "CF-Connecting-IP": "192.0.2.98" },
  });
}

describe("Linux plugin client IP", () => {
  it("ignores client-supplied proxy headers by default so changing headers cannot bypass rate limiting", () => {
    expect(extensionClientIp(request(), "192.0.2.1", false)).toBe("192.0.2.1");
  });
  it("uses the last trusted-proxy hop rather than a forged prefix", () => {
    expect(extensionClientIp(request("192.0.2.99, 192.0.2.2"), "172.18.0.2", true)).toBe("192.0.2.2");
  });
  it("falls back to the transport peer for invalid forwarded input instead of creating arbitrary limiter keys", () => {
    expect(extensionClientIp(request("not-an-ip"), "192.0.2.1", true)).toBe("192.0.2.1");
  });
  it("does not trust the Cloudflare header on a Linux Node listener", () => {
    expect(extensionClientIp(request(""), "192.0.2.1", true)).toBe("192.0.2.1");
  });
  it("normalizes mapped IPv4 so the same transport source shares a counter", () => {
    expect(extensionClientIp(request(), "::ffff:192.0.2.1", false)).toBe("192.0.2.1");
  });
  it("supports IPv6 transport clients", () => {
    expect(extensionClientIp(request(), "2001:db8::1", false)).toBe("2001:db8::1");
  });
  it("fails closed without an identifiable transport peer", () => {
    expect(extensionClientIp(request(), undefined, false)).toBeUndefined();
  });
});
