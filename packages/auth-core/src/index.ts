export type OwnerType = "user" | "anonymous";

export interface AccessTokenPayload {
  owner_type: OwnerType;
  owner_id: string;
  session_id: string;
}

export const PACKAGE_NAME = "@kando/auth-core";
export const ACCESS_TOKEN_EXPIRES_IN_SECONDS = 900;
export const REFRESH_TOKEN_EXPIRES_IN_DAYS = 30;

type TextEncoderLike = {
  encode(input?: string): Uint8Array;
};

type WebCryptoLike = {
  getRandomValues<T extends Uint8Array>(array: T): T;
  subtle: {
    digest(algorithm: "SHA-256", data: Uint8Array): Promise<ArrayBuffer>;
    importKey(
      format: "raw",
      keyData: Uint8Array,
      algorithm: { name: "HMAC"; hash: "SHA-256" },
      extractable: false,
      keyUsages: readonly ["sign"],
    ): Promise<unknown>;
    sign(
      algorithm: "HMAC",
      key: unknown,
      data: Uint8Array,
    ): Promise<ArrayBuffer>;
  };
};

const BASE64URL_ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

export async function signAccessToken(
  payload: AccessTokenPayload,
  secret: string,
  now = new Date(),
): Promise<string> {
  if (secret.trim().length === 0) {
    throw new Error("JWT secret is required.");
  }

  const crypto = getCrypto();
  const iat = Math.floor(now.getTime() / 1000);
  const encodedHeader = encodeJson({ alg: "HS256", typ: "JWT" });
  const encodedPayload = encodeJson({
    ...payload,
    iat,
    exp: iat + ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  });
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    encodeText(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encodeText(signingInput),
  );

  return `${signingInput}.${encodeBase64Url(new Uint8Array(signature))}`;
}

export function createRefreshToken(): string {
  const tokenBytes = new Uint8Array(32);
  getCrypto().getRandomValues(tokenBytes);
  return encodeBase64Url(tokenBytes);
}

export async function hashRefreshToken(
  refreshToken: string,
): Promise<string> {
  const hash = await getCrypto().subtle.digest(
    "SHA-256",
    encodeText(refreshToken),
  );

  return Array.from(new Uint8Array(hash), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function refreshTokenExpiresAt(now = new Date()): string {
  const expiresAt = new Date(
    now.getTime() + REFRESH_TOKEN_EXPIRES_IN_DAYS * 24 * 60 * 60 * 1000,
  );
  return expiresAt.toISOString();
}

function encodeJson(value: unknown): string {
  return encodeBase64Url(encodeText(JSON.stringify(value)));
}

function encodeText(value: string): Uint8Array {
  const TextEncoderCtor = (
    globalThis as unknown as {
      TextEncoder: new () => TextEncoderLike;
    }
  ).TextEncoder;

  return new TextEncoderCtor().encode(value);
}

function getCrypto(): WebCryptoLike {
  return (globalThis as unknown as { crypto: WebCryptoLike }).crypto;
}

function encodeBase64Url(bytes: Uint8Array): string {
  let output = "";

  for (let index = 0; index < bytes.length; index += 3) {
    const firstByte = bytes[index] ?? 0;
    const hasSecondByte = index + 1 < bytes.length;
    const hasThirdByte = index + 2 < bytes.length;
    const secondByte = hasSecondByte ? bytes[index + 1] : 0;
    const thirdByte = hasThirdByte ? bytes[index + 2] : 0;
    const triplet = (firstByte << 16) | (secondByte << 8) | thirdByte;

    output += BASE64URL_ALPHABET[(triplet >> 18) & 0x3f];
    output += BASE64URL_ALPHABET[(triplet >> 12) & 0x3f];

    if (hasSecondByte) {
      output += BASE64URL_ALPHABET[(triplet >> 6) & 0x3f];
    }

    if (hasThirdByte) {
      output += BASE64URL_ALPHABET[triplet & 0x3f];
    }
  }

  return output;
}
