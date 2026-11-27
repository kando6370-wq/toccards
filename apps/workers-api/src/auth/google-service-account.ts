const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const REQUEST_TIMEOUT_MS = 8_000;
const accessTokens = new Map<string, Promise<{ value: string; expiresAt: number }>>();

export async function googleAccessToken(email: string, privateKey: string, scope: string, now: Date): Promise<string> {
  const fingerprint = base64Url(new Uint8Array(await crypto.subtle.digest(
    "SHA-256", new TextEncoder().encode(privateKey),
  )));
  const cacheKey = `${scope}:${email}:${fingerprint}`;
  const cached = accessTokens.get(cacheKey);
  if (cached) {
    const value = await cached;
    if (value.expiresAt > now.getTime() + 60_000) return value.value;
    accessTokens.delete(cacheKey);
  }
  const pending = requestAccessToken(email, privateKey, scope, now);
  if (accessTokens.size >= 8) accessTokens.delete(accessTokens.keys().next().value!);
  accessTokens.set(cacheKey, pending);
  try {
    return (await pending).value;
  } catch (error) {
    if (accessTokens.get(cacheKey) === pending) accessTokens.delete(cacheKey);
    throw error;
  }
}

async function requestAccessToken(email: string, pem: string, scope: string, now: Date) {
  const issuedAt = Math.floor(now.getTime() / 1000);
  const header = encodeJson({ alg: "RS256", typ: "JWT" });
  const claims = encodeJson({
    iss: email, scope, aud: GOOGLE_TOKEN_URL,
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
  if (!response.ok) throw new Error("Google service authorization is unavailable.");
  const data = record(response.body);
  if (typeof data?.access_token !== "string" || !data.access_token ||
    typeof data.expires_in !== "number" || data.expires_in <= 0) {
    throw new Error("Invalid Android verification service credentials.");
  }
  return { value: data.access_token, expiresAt: now.getTime() + data.expires_in * 1000 };
}

export async function fetchWithDeadline(url: string, init: RequestInit): Promise<{
  ok: boolean; status: number; body: unknown;
}> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    return { ok: response.ok, status: response.status, body: response.ok ? await readGoogleBody(response) : null };
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

export function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function readGoogleBody(response: Response): Promise<unknown> {
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}
