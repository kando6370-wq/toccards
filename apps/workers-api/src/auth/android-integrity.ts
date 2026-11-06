import type { Env } from "../env";

export type AndroidIntegrityBinding = {
  deviceId: string;
  requestNonce: string;
};

export type AndroidIntegrityResult = "verified" | "invalid" | "unavailable";

const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const PLAY_INTEGRITY_SCOPE = "https://www.googleapis.com/auth/playintegrity";
const MAX_TOKEN_AGE_MS = 120_000;
const MAX_CLOCK_SKEW_MS = 30_000;
const REQUEST_TIMEOUT_MS = 8_000;
const accessTokens = new Map<string, Promise<{ value: string; expiresAt: number }>>();

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
  ) return "verified";

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
    const googleToken = await getAccessToken(serviceAccount, privateKey, now);
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
      new TextEncoder().encode(`${binding.deviceId}\nandroid\n${binding.requestNonce}`),
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
    return "verified";
  } catch {
    return "unavailable";
  }
}

async function getAccessToken(email: string, privateKey: string, now: Date): Promise<string> {
  const fingerprint = base64Url(new Uint8Array(await crypto.subtle.digest(
    "SHA-256", new TextEncoder().encode(privateKey),
  )));
  const cacheKey = `${email}:${fingerprint}`;
  const cached = accessTokens.get(cacheKey);
  if (cached) {
    const value = await cached;
    if (value.expiresAt > now.getTime() + 60_000) return value.value;
    accessTokens.delete(cacheKey);
  }
  const pending = requestAccessToken(email, privateKey, now);
  if (accessTokens.size >= 8) accessTokens.delete(accessTokens.keys().next().value!);
  accessTokens.set(cacheKey, pending);
  try {
    return (await pending).value;
  } catch (error) {
    if (accessTokens.get(cacheKey) === pending) accessTokens.delete(cacheKey);
    throw error;
  }
}

async function requestAccessToken(email: string, pem: string, now: Date) {
  const issuedAt = Math.floor(now.getTime() / 1000);
  const header = encodeJson({ alg: "RS256", typ: "JWT" });
  const claims = encodeJson({
    iss: email, scope: PLAY_INTEGRITY_SCOPE, aud: GOOGLE_TOKEN_URL,
    iat: issuedAt, exp: issuedAt + 3600,
  });
  const signingInput = `${header}.${claims}`;
  const encoded = pem.replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const keyBytes = Uint8Array.from(atob(encoded), (value) => value.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", keyBytes, {
    name: "RSASSA-PKCS1-v1_5", hash: "SHA-256",
  }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput),
  ));
  const response = await fetchWithDeadline(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${signingInput}.${base64Url(signature)}`,
    }),
  });
  if (!response.ok) throw new Error("Android installation verification is unavailable.");
  const data = record(response.body);
  if (typeof data?.access_token !== "string" || !data.access_token ||
    typeof data.expires_in !== "number" || data.expires_in <= 0) {
    throw new Error("Invalid Android verification service credentials.");
  }
  return { value: data.access_token, expiresAt: now.getTime() + data.expires_in * 1000 };
}

async function fetchWithDeadline(url: string, init: RequestInit): Promise<{
  ok: boolean; status: number; body: unknown;
}> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    return { ok: response.ok, status: response.status, body: response.ok ? await response.json() : null };
  } finally {
    clearTimeout(timeout);
  }
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}

function encodeJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
