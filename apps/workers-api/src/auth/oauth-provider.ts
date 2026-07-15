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

export function resolveMockGoogleIdentity(
  input: GoogleOAuthInput,
): OAuthIdentity | null {
  if (!input.code || !input.redirectUri) return null;
  const parts = input.code.split(":");
  if (parts.length !== 3 || parts[0] !== "mock-google") return null;
  const providerUid = normalizeProviderUid(parts[1]);
  const email = normalizeEmail(parts[2]);
  if (!providerUid || !email) return null;
  return { provider: "google", providerUid, email };
}

export async function resolveGoogleIdentity(
  input: GoogleOAuthInput,
  clientId: string | undefined,
): Promise<OAuthIdentity | null> {
  const mockIdentity = resolveMockGoogleIdentity(input);
  if (mockIdentity) return mockIdentity;
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

export function resolveMockAppleIdentity(
  input: AppleOAuthInput,
): OAuthIdentity | null {
  if (!input.code || !input.idToken) return null;
  const parts = input.idToken.split(":");
  if (parts.length !== 3 || parts[0] !== "mock-apple") return null;
  const providerUid = normalizeProviderUid(parts[1]);
  const email = normalizeEmail(parts[2]);
  if (!providerUid || !email) return null;
  return { provider: "apple", providerUid, email };
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
