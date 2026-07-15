export type OAuthProviderName = "google" | "apple";

export type OAuthIdentity = {
  provider: OAuthProviderName;
  providerUid: string;
  email: string;
};

export type GoogleOAuthInput = {
  code: string | null;
  redirectUri: string | null;
};

export type AppleOAuthInput = {
  code: string | null;
  idToken: string | null;
};

const EMAIL_MAX_LENGTH = 254;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PROVIDER_UID_MAX_LENGTH = 128;
const PROVIDER_UID_PATTERN = /^[A-Za-z0-9._-]+$/;
const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";

export async function resolveGoogleIdentity(
  input: GoogleOAuthInput,
  clientId: string | undefined,
): Promise<OAuthIdentity | null> {
  if (!input.code || !clientId) return null;

  const url = new URL("https://oauth2.googleapis.com/tokeninfo");
  url.searchParams.set("id_token", input.code);
  try {
    const response = await fetch(url);
    if (!response.ok) return null;
    const payload = (await response.json()) as Record<string, unknown>;
    const issuer = payload.iss;
    const emailVerified = payload.email_verified;
    const providerUid = normalizeProviderUid(asString(payload.sub));
    const email = normalizeEmail(asString(payload.email));
    if (
      payload.aud !== clientId ||
      (issuer !== "accounts.google.com" && issuer !== "https://accounts.google.com") ||
      (emailVerified !== true && emailVerified !== "true") ||
      !providerUid ||
      !email
    ) {
      return null;
    }
    return { provider: "google", providerUid, email };
  } catch {
    return null;
  }
}

export async function resolveAppleIdentity(
  input: AppleOAuthInput,
  clientId: string | undefined,
): Promise<OAuthIdentity | null> {
  if (!input.idToken || !clientId) return null;

  try {
    const tokenParts = input.idToken.split(".");
    if (tokenParts.length !== 3) return null;

    const header = decodeJwtPart(tokenParts[0]);
    const payload = decodeJwtPart(tokenParts[1]);
    const kid = asString(header.kid);
    if (header.alg !== "RS256" || !kid) return null;

    const response = await fetch(APPLE_JWKS_URL);
    if (!response.ok) return null;
    const jwks = (await response.json()) as { keys?: unknown };
    if (!Array.isArray(jwks.keys)) return null;
    const jwk = jwks.keys.find(
      (candidate): candidate is JsonWebKey & { kid: string } =>
        isRecord(candidate) &&
        candidate.kid === kid &&
        candidate.kty === "RSA" &&
        candidate.alg === "RS256",
    );
    if (!jwk) return null;

    const key = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const verified = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      decodeBase64Url(tokenParts[2]),
      new TextEncoder().encode(`${tokenParts[0]}.${tokenParts[1]}`),
    );
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = asNumber(payload.exp);
    const issuedAt = asNumber(payload.iat);
    const providerUid = normalizeProviderUid(asString(payload.sub));
    const email = normalizeEmail(asString(payload.email));
    if (
      !verified ||
      payload.iss !== APPLE_ISSUER ||
      !hasAudience(payload.aud, clientId) ||
      expiresAt === undefined ||
      expiresAt <= now ||
      issuedAt === undefined ||
      issuedAt > now + 300 ||
      (payload.email_verified !== true && payload.email_verified !== "true") ||
      !providerUid ||
      !email
    ) {
      return null;
    }
    return { provider: "apple", providerUid, email };
  } catch {
    return null;
  }
}

function normalizeProviderUid(
  rawProviderUid: string | undefined,
): string | null {
  if (!rawProviderUid) return null;
  const providerUid = rawProviderUid.trim();
  return providerUid.length <= PROVIDER_UID_MAX_LENGTH &&
    PROVIDER_UID_PATTERN.test(providerUid)
    ? providerUid
    : null;
}

function normalizeEmail(rawEmail: string | undefined): string | null {
  if (!rawEmail) return null;
  const email = rawEmail.trim().toLowerCase();
  return email.length <= EMAIL_MAX_LENGTH && EMAIL_PATTERN.test(email)
    ? email
    : null;
}

function asString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function asNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function hasAudience(value: unknown, clientId: string): boolean {
  return value === clientId ||
    (Array.isArray(value) && value.some((audience) => audience === clientId));
}

function decodeJwtPart(value: string): Record<string, unknown> {
  const parsed = JSON.parse(new TextDecoder().decode(decodeBase64Url(value)));
  if (!isRecord(parsed)) throw new Error("Invalid JWT payload.");
  return parsed;
}

function decodeBase64Url(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
