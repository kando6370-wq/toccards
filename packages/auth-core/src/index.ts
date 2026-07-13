export type OwnerType = "user" | "anonymous";

export interface AccessTokenPayload {
  owner_type: OwnerType;
  owner_id: string;
  session_id: string;
}

export interface VerifiedAccessTokenPayload extends AccessTokenPayload {
  iat: number;
  exp: number;
}

export type VerifyAccessTokenResult =
  | { valid: true; payload: VerifiedAccessTokenPayload }
  | { valid: false; reason: "malformed" | "invalid_signature" | "expired" };

export const PACKAGE_NAME = "@kando/auth-core";
export const ACCESS_TOKEN_EXPIRES_IN_SECONDS = 900;
export const REFRESH_TOKEN_EXPIRES_IN_DAYS = 30;
export const PASSWORD_HASH_ALGORITHM = "pbkdf2-sha256";
export const PASSWORD_HASH_VERSION = "v1";
export const PASSWORD_HASH_ITERATIONS = 100_000;

const PASSWORD_HASH_SALT_BYTES = 16;
const PASSWORD_HASH_BYTES = 32;

type TextEncoderLike = {
  encode(input?: string): Uint8Array;
};

type TextDecoderLike = {
  decode(input?: Uint8Array): string;
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
    importKey(
      format: "raw",
      keyData: Uint8Array,
      algorithm: "PBKDF2",
      extractable: false,
      keyUsages: readonly ["deriveBits"],
    ): Promise<unknown>;
    sign(
      algorithm: "HMAC",
      key: unknown,
      data: Uint8Array,
    ): Promise<ArrayBuffer>;
    deriveBits(
      algorithm: {
        name: "PBKDF2";
        salt: Uint8Array;
        iterations: number;
        hash: "SHA-256";
      },
      baseKey: unknown,
      length: number,
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

export async function verifyAccessToken(
  token: string,
  secret: string,
  now = new Date(),
): Promise<VerifyAccessTokenResult> {
  if (secret.trim().length === 0) {
    throw new Error("JWT secret is required.");
  }

  const parts = token.split(".");
  if (parts.length !== 3) {
    return { valid: false, reason: "malformed" };
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts as [
    string,
    string,
    string,
  ];
  let header: unknown;
  let signature: Uint8Array;

  try {
    header = decodeJson(encodedHeader);
    signature = decodeBase64Url(encodedSignature);
  } catch {
    return { valid: false, reason: "malformed" };
  }

  if (!isRecord(header) || header.alg !== "HS256" || header.typ !== "JWT") {
    return { valid: false, reason: "malformed" };
  }

  const expectedSignature = await signHs256(
    `${encodedHeader}.${encodedPayload}`,
    secret,
  );

  if (!signatureMatches(signature, expectedSignature)) {
    return { valid: false, reason: "invalid_signature" };
  }

  let payload: unknown;
  try {
    payload = decodeJson(encodedPayload);
  } catch {
    return { valid: false, reason: "malformed" };
  }

  if (!isVerifiedAccessTokenPayload(payload)) {
    return { valid: false, reason: "malformed" };
  }

  const nowSeconds = Math.floor(now.getTime() / 1000);
  if (payload.exp <= nowSeconds) {
    return { valid: false, reason: "expired" };
  }

  return { valid: true, payload };
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

export async function hashPassword(password: string): Promise<string> {
  const salt = new Uint8Array(PASSWORD_HASH_SALT_BYTES);
  getCrypto().getRandomValues(salt);
  const hash = await derivePasswordHash(
    password,
    salt,
    PASSWORD_HASH_ITERATIONS,
  );

  return [
    PASSWORD_HASH_ALGORITHM,
    PASSWORD_HASH_VERSION,
    String(PASSWORD_HASH_ITERATIONS),
    encodeBase64Url(salt),
    encodeBase64Url(hash),
  ].join("$");
}

export async function verifyPassword(
  password: string,
  storedHash: string,
): Promise<boolean> {
  try {
    const parts = storedHash.split("$");
    if (parts.length !== 5) {
      return false;
    }

    const [algorithm, version, iterationsValue, encodedSalt, encodedHash] =
      parts as [string, string, string, string, string];
    if (
      algorithm !== PASSWORD_HASH_ALGORITHM ||
      version !== PASSWORD_HASH_VERSION
    ) {
      return false;
    }

    if (
      !/^\d+$/.test(iterationsValue) ||
      iterationsValue !== String(PASSWORD_HASH_ITERATIONS)
    ) {
      return false;
    }

    const salt = decodeBase64Url(encodedSalt);
    const expectedHash = decodeBase64Url(encodedHash);
    if (
      salt.length !== PASSWORD_HASH_SALT_BYTES ||
      expectedHash.length !== PASSWORD_HASH_BYTES
    ) {
      return false;
    }

    const actualHash = await derivePasswordHash(
      password,
      salt,
      PASSWORD_HASH_ITERATIONS,
    );

    return signatureMatches(actualHash, expectedHash);
  } catch {
    return false;
  }
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

function decodeJson(value: string): unknown {
  return JSON.parse(decodeText(decodeBase64Url(value)));
}

function encodeText(value: string): Uint8Array {
  const TextEncoderCtor = (
    globalThis as unknown as {
      TextEncoder: new () => TextEncoderLike;
    }
  ).TextEncoder;

  return new TextEncoderCtor().encode(value);
}

function decodeText(value: Uint8Array): string {
  const TextDecoderCtor = (
    globalThis as unknown as {
      TextDecoder: new () => TextDecoderLike;
    }
  ).TextDecoder;

  return new TextDecoderCtor().decode(value);
}

function getCrypto(): WebCryptoLike {
  return (globalThis as unknown as { crypto: WebCryptoLike }).crypto;
}

async function signHs256(
  signingInput: string,
  secret: string,
): Promise<Uint8Array> {
  const crypto = getCrypto();
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

  return new Uint8Array(signature);
}

async function derivePasswordHash(
  password: string,
  salt: Uint8Array,
  iterations: number,
): Promise<Uint8Array> {
  const crypto = getCrypto();
  const key = await crypto.subtle.importKey(
    "raw",
    encodeText(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const hash = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      salt,
      iterations,
      hash: "SHA-256",
    },
    key,
    PASSWORD_HASH_BYTES * 8,
  );

  return new Uint8Array(hash);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isVerifiedAccessTokenPayload(
  value: unknown,
): value is VerifiedAccessTokenPayload {
  if (!isRecord(value)) {
    return false;
  }

  return (
    (value.owner_type === "user" || value.owner_type === "anonymous") &&
    typeof value.owner_id === "string" &&
    typeof value.session_id === "string" &&
    typeof value.iat === "number" &&
    Number.isFinite(value.iat) &&
    typeof value.exp === "number" &&
    Number.isFinite(value.exp)
  );
}

function signatureMatches(actual: Uint8Array, expected: Uint8Array): boolean {
  if (actual.length !== expected.length) {
    return false;
  }

  let difference = 0;
  for (let index = 0; index < actual.length; index += 1) {
    difference |= actual[index] ^ expected[index];
  }

  return difference === 0;
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

function decodeBase64Url(value: string): Uint8Array {
  if (value.length % 4 === 1) {
    throw new Error("Invalid base64url value.");
  }

  let bits = 0;
  let bitLength = 0;
  const bytes: number[] = [];

  for (const char of value) {
    const index = BASE64URL_ALPHABET.indexOf(char);
    if (index === -1) {
      throw new Error("Invalid base64url value.");
    }

    bits = (bits << 6) | index;
    bitLength += 6;

    if (bitLength >= 8) {
      bitLength -= 8;
      bytes.push((bits >> bitLength) & 0xff);
      bits &= (1 << bitLength) - 1;
    }
  }

  return new Uint8Array(bytes);
}
