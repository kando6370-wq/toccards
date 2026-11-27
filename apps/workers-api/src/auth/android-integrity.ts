import { base64Url, fetchWithDeadline, googleAccessToken } from "./google-service-account";
import type { Env } from "../env";

export type AndroidIntegrityBinding = {
  deviceId: string;
  requestNonce: string;
  sessionId?: string;
};

export type AndroidPlayBuild = {
  package_name: string;
  certificate_digest: string;
  version_code: number;
  verified_at: string;
};

export type AndroidIntegrityResult = { status: "verified"; build?: AndroidPlayBuild } | "invalid" | "unavailable";

const PLAY_INTEGRITY_SCOPE = "https://www.googleapis.com/auth/playintegrity";
const MAX_TOKEN_AGE_MS = 120_000;
const MAX_CLOCK_SKEW_MS = 30_000;

export async function verifyAndroidInstallation(
  env: Env,
  token: unknown,
  binding: AndroidIntegrityBinding,
  now = new Date(),
): Promise<AndroidIntegrityResult> {
  if (
    !binding.deviceId || binding.deviceId.length > 256 ||
    !/^[A-Za-z0-9_-]{16,128}$/.test(binding.requestNonce)
  ) return "invalid";

  if (
    env.APP_ENVIRONMENT === "development" &&
    env.ANDROID_INTEGRITY_ALLOW_DEVELOPMENT === "true"
  ) return { status: "verified" };

  const packageName = env.ANDROID_PLAY_PACKAGE_NAME?.trim();
  const certificates = env.ANDROID_PLAY_CERTIFICATE_SHA256_DIGESTS
    ?.split(",").map((value) => value.trim()).filter(Boolean) ?? [];
  const serviceAccount = env.ANDROID_PLAY_SERVICE_ACCOUNT_EMAIL?.trim();
  const privateKey = env.ANDROID_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY?.trim();
  if (
    !packageName || !/^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+$/.test(packageName) ||
    certificates.length === 0 || certificates.some((value) => !/^[A-Za-z0-9_-]{43}$/.test(value)) ||
    !serviceAccount || !privateKey
  ) return "unavailable";
  if (typeof token !== "string" || token.length === 0 || token.length > 32_768) return "invalid";

  try {
    const googleToken = await googleAccessToken(serviceAccount, privateKey, PLAY_INTEGRITY_SCOPE, now);
    const response = await fetchWithDeadline(
      `https://playintegrity.googleapis.com/v1/${encodeURIComponent(packageName)}:decodeIntegrityToken`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${googleToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ integrity_token: token }),
      },
    );
    if (!response.ok) return response.status === 400 ? "invalid" : "unavailable";
    const payload = record(record(response.body)?.tokenPayloadExternal);
    const request = record(payload?.requestDetails);
    const app = record(payload?.appIntegrity);
    const device = record(payload?.deviceIntegrity);
    const account = record(payload?.accountDetails);
    const timestamp = Number(request?.timestampMillis);
    const expectedHash = base64Url(new Uint8Array(await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode([binding.deviceId, "android", binding.requestNonce, ...(binding.sessionId ? [binding.sessionId] : [])].join("\n")),
    )));
    const age = now.getTime() - timestamp;
    if (
      request?.requestPackageName !== packageName || request.requestHash !== expectedHash ||
      !Number.isSafeInteger(timestamp) || age > MAX_TOKEN_AGE_MS || age < -MAX_CLOCK_SKEW_MS ||
      app?.appRecognitionVerdict !== "PLAY_RECOGNIZED" || app.packageName !== packageName ||
      !Array.isArray(app.certificateSha256Digest) ||
      !app.certificateSha256Digest.some((value) => typeof value === "string" && certificates.includes(value)) ||
      !Array.isArray(device?.deviceRecognitionVerdict) ||
      !device.deviceRecognitionVerdict.includes("MEETS_DEVICE_INTEGRITY") ||
      account?.appLicensingVerdict !== "LICENSED"
    ) return "invalid";
    const version = typeof app.versionCode === "string" && /^[1-9]\d{0,9}$/.test(app.versionCode)
      ? Number(app.versionCode) : 0;
    if (version < 1 || version > 2_100_000_000) return { status: "verified" };
    return { status: "verified", build: {
      package_name: packageName,
      certificate_digest: app.certificateSha256Digest.find((value) => certificates.includes(value)),
      version_code: version,
      verified_at: new Date(timestamp).toISOString(),
    } };
  } catch {
    return "unavailable";
  }
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}
