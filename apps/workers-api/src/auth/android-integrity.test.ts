import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { verifyAndroidInstallation } from "./android-integrity";

const now = new Date("2026-11-05T10:00:00.000Z");
const binding = { deviceId: "isolated-test-installation", requestNonce: "test-request-nonce-123456" };
const packageName = "dev.kando.integrity.fixture";
const certificate = "A".repeat(43);
let privateKey: string;
let requestHash: string;

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({
    name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256",
  }, true, ["sign", "verify"]) as CryptoKeyPair;
  const bytes = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  privateKey = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...bytes))}\n-----END PRIVATE KEY-----`;
  const digest = new Uint8Array(await crypto.subtle.digest(
    "SHA-256", new TextEncoder().encode(`${binding.deviceId}\nandroid\n${binding.requestNonce}`),
  ));
  requestHash = btoa(String.fromCharCode(...digest)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
});

afterEach(() => vi.unstubAllGlobals());

function environment(overrides: Partial<Env> = {}): Env {
  return {
    APP_ENVIRONMENT: "production",
    ANDROID_PLAY_PACKAGE_NAME: packageName,
    ANDROID_PLAY_CERTIFICATE_SHA256_DIGESTS: certificate,
    ANDROID_PLAY_SERVICE_ACCOUNT_EMAIL: `${crypto.randomUUID()}@verification.invalid`,
    ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY: privateKey,
    ...overrides,
  } as Env;
}

function payload() {
  return {
    requestDetails: { requestPackageName: packageName, requestHash, timestampMillis: String(now.getTime()) },
    appIntegrity: {
      appRecognitionVerdict: "PLAY_RECOGNIZED", packageName,
      certificateSha256Digest: [certificate],
    },
    deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
    accountDetails: { appLicensingVerdict: "LICENSED" },
  };
}

function mockGoogle(decoded: unknown) {
  const fetcher = vi.fn(async (url: string, init?: RequestInit) => {
    if (url === "https://oauth2.googleapis.com/token") {
      const values = new URLSearchParams(String(init?.body));
      expect(values.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
      expect(values.get("assertion")?.split(".")).toHaveLength(3);
      return Response.json({ access_token: "ephemeral-google-test-token", expires_in: 3600 });
    }
    expect(url).toBe(`https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`);
    expect(JSON.parse(String(init?.body))).toEqual({ integrity_token: "installation-proof" });
    return Response.json({ tokenPayloadExternal: decoded });
  });
  vi.stubGlobal("fetch", fetcher);
  return fetcher;
}

describe("Android session installation proof", () => {
  it("accepts only a recognized Play installation whose proof is bound to this installation request", async () => {
    const fetcher = mockGoogle(payload());
    expect(await verifyAndroidInstallation(environment(), "installation-proof", binding, now)).toBe("verified");
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it.each(["production", undefined] as const)("never enables the development bypass in %s", async (appEnvironment) => {
    const fetcher = vi.fn();
    vi.stubGlobal("fetch", fetcher);
    expect(await verifyAndroidInstallation(environment({
      APP_ENVIRONMENT: appEnvironment,
      ANDROID_INTEGRITY_ALLOW_DEVELOPMENT: "true",
      ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY: undefined,
    }), undefined, binding, now)).toBe("unavailable");
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("allows an explicitly enabled independent development environment without production credentials", async () => {
    const fetcher = vi.fn();
    vi.stubGlobal("fetch", fetcher);
    expect(await verifyAndroidInstallation(environment({
      APP_ENVIRONMENT: "development", ANDROID_INTEGRITY_ALLOW_DEVELOPMENT: "true",
      ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY: undefined,
    }), undefined, binding, now)).toBe("verified");
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("requires proof in development unless the bypass is explicitly enabled", async () => {
    expect(await verifyAndroidInstallation(environment({ APP_ENVIRONMENT: "development" }), undefined, binding, now))
      .toBe("invalid");
  });

  it("rejects malformed request binding even when development bypass is enabled", async () => {
    expect(await verifyAndroidInstallation(environment({
      APP_ENVIRONMENT: "development", ANDROID_INTEGRITY_ALLOW_DEVELOPMENT: "true",
    }), undefined, { ...binding, requestNonce: "short" }, now)).toBe("invalid");
  });

  it.each([
    ["another request", (value: ReturnType<typeof payload>) => { value.requestDetails.requestHash = "another-request"; }],
    ["another package", (value: ReturnType<typeof payload>) => { value.appIntegrity.packageName = "another.package"; }],
    ["another signature", (value: ReturnType<typeof payload>) => { value.appIntegrity.certificateSha256Digest = ["B".repeat(43)]; }],
    ["an unrecognized build", (value: ReturnType<typeof payload>) => { value.appIntegrity.appRecognitionVerdict = "UNRECOGNIZED_VERSION"; }],
    ["an unlicensed installation", (value: ReturnType<typeof payload>) => { value.accountDetails.appLicensingVerdict = "UNLICENSED"; }],
    ["an unverified device", (value: ReturnType<typeof payload>) => { value.deviceIntegrity.deviceRecognitionVerdict = ["MEETS_BASIC_INTEGRITY"]; }],
    ["an expired proof", (value: ReturnType<typeof payload>) => { value.requestDetails.timestampMillis = String(now.getTime() - 120_001); }],
    ["a future proof", (value: ReturnType<typeof payload>) => { value.requestDetails.timestampMillis = String(now.getTime() + 30_001); }],
  ] as const)("rejects %s so a self-reported Android platform cannot grant free access", async (_, mutate) => {
    const decoded = payload();
    mutate(decoded);
    mockGoogle(decoded);
    expect(await verifyAndroidInstallation(environment(), "installation-proof", binding, now)).toBe("invalid");
  });

  it("rejects an empty verdict, including the empty verdict returned for replayed standard tokens", async () => {
    mockGoogle({});
    expect(await verifyAndroidInstallation(environment(), "installation-proof", binding, now)).toBe("invalid");
  });

  it("reports verification outages without falling back to an iOS session", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 503 })));
    expect(await verifyAndroidInstallation(environment(), "installation-proof", binding, now)).toBe("unavailable");
  });
});
