import { describe, expect, it } from "vitest";
import {
  createRefreshToken,
  hashPassword,
  hashRefreshToken,
  PASSWORD_HASH_ALGORITHM,
  PASSWORD_HASH_ITERATIONS,
  PASSWORD_HASH_VERSION,
  refreshTokenExpiresAt,
  signAccessToken,
  verifyPassword,
  verifyAccessToken,
} from "./index";

type JwtHeader = {
  alg: string;
  typ: string;
};

type JwtPayload = {
  owner_type: string;
  owner_id: string;
  session_id: string;
  iat: number;
  exp: number;
};

const BASE64URL_ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

function decodeBase64Url(value: string): string {
  let bits = 0;
  let bitLength = 0;
  const bytes: number[] = [];

  for (const char of value) {
    const index = BASE64URL_ALPHABET.indexOf(char);
    if (index === -1) {
      throw new Error(`Invalid base64url character: ${char}`);
    }

    bits = (bits << 6) | index;
    bitLength += 6;

    if (bitLength >= 8) {
      bitLength -= 8;
      bytes.push((bits >> bitLength) & 0xff);
    }
  }

  return String.fromCharCode(...bytes);
}

function decodeJwtPart<T>(value: string): T {
  return JSON.parse(decodeBase64Url(value)) as T;
}

function encodeJwtPart(value: unknown): string {
  return encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function encodeTextPart(value: string): string {
  return encodeBase64Url(new TextEncoder().encode(value));
}

async function signExpectedSignature(
  signingInput: string,
  secret: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(signingInput),
  );

  return encodeBase64Url(new Uint8Array(signature));
}

async function signJwtParts(
  encodedHeader: string,
  encodedPayload: string,
  secret: string,
): Promise<string> {
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await signExpectedSignature(signingInput, secret);

  return `${signingInput}.${signature}`;
}

async function signJwt(
  header: unknown,
  payload: unknown,
  secret: string,
): Promise<string> {
  return signJwtParts(encodeJwtPart(header), encodeJwtPart(payload), secret);
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

async function createStoredPasswordHash(
  password: string,
  options: {
    algorithm?: string;
    version?: string;
    iterations?: number;
    iterationsValue?: string;
    salt?: Uint8Array;
    hash?: Uint8Array;
  } = {},
): Promise<string> {
  const salt =
    options.salt ??
    new Uint8Array([
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]);
  const iterations = options.iterations ?? PASSWORD_HASH_ITERATIONS;
  const hash =
    options.hash ??
    (await deriveExpectedPasswordHash(password, salt, iterations));

  return [
    options.algorithm ?? PASSWORD_HASH_ALGORITHM,
    options.version ?? PASSWORD_HASH_VERSION,
    options.iterationsValue ?? String(iterations),
    encodeBase64Url(salt),
    encodeBase64Url(hash),
  ].join("$");
}

async function deriveExpectedPasswordHash(
  password: string,
  salt: Uint8Array,
  iterations: number,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
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
    256,
  );

  return new Uint8Array(hash);
}

function replacePasswordHashPart(
  storedHash: string,
  partIndex: number,
  value: string,
): string {
  const parts = storedHash.split("$");
  parts[partIndex] = value;
  return parts.join("$");
}

describe("auth-core token helpers", () => {
  it("signs an HS256 access token carrying the owner and session identity for authorization boundaries", async () => {
    const token = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "anonymous-id",
        session_id: "session-id",
      },
      "test-secret",
      new Date("2026-07-02T00:00:00.000Z"),
    );

    const parts = token.split(".");
    expect(parts).toHaveLength(3);

    const [encodedHeader, encodedPayload, signature] = parts as [
      string,
      string,
      string,
    ];
    const header = decodeJwtPart<JwtHeader>(encodedHeader);
    const payload = decodeJwtPart<JwtPayload>(encodedPayload);
    const expectedSignature = await signExpectedSignature(
      `${encodedHeader}.${encodedPayload}`,
      "test-secret",
    );

    expect(signature).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(signature).toBe(expectedSignature);
    expect(header).toEqual({ alg: "HS256", typ: "JWT" });
    expect(payload).toMatchObject({
      owner_type: "anonymous",
      owner_id: "anonymous-id",
      session_id: "session-id",
    });
    expect(payload.exp - payload.iat).toBe(900);
  });

  it("rejects blank JWT secrets so access tokens are never signed with an empty key", async () => {
    await expect(
      signAccessToken(
        {
          owner_type: "anonymous",
          owner_id: "anonymous-id",
          session_id: "session-id",
        },
        "   ",
      ),
    ).rejects.toThrow("JWT secret is required.");
  });

  it("verifies signed access tokens so authorization can trust the owner and session identity", async () => {
    const issuedAt = new Date("2026-07-02T00:00:00.000Z");
    const issuedAtSeconds = Math.floor(issuedAt.getTime() / 1000);
    const token = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "anonymous-id",
        session_id: "session-id",
      },
      "test-secret",
      issuedAt,
    );

    const result = await verifyAccessToken(
      token,
      "test-secret",
      new Date("2026-07-02T00:14:59.000Z"),
    );

    expect(result).toEqual({
      valid: true,
      payload: {
        owner_type: "anonymous",
        owner_id: "anonymous-id",
        session_id: "session-id",
        iat: issuedAtSeconds,
        exp: issuedAtSeconds + 900,
      },
    });
  });

  it("rejects access tokens signed with another secret so bearer credentials cannot be forged", async () => {
    const token = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "anonymous-id",
        session_id: "session-id",
      },
      "test-secret",
      new Date("2026-07-02T00:00:00.000Z"),
    );

    await expect(
      verifyAccessToken(
        token,
        "wrong-secret",
        new Date("2026-07-02T00:00:00.000Z"),
      ),
    ).resolves.toEqual({
      valid: false,
      reason: "invalid_signature",
    });
  });

  it("checks signatures before payload fields so unauthenticated claims cannot choose the failure reason", async () => {
    const token = await signJwt(
      { alg: "HS256", typ: "JWT" },
      {
        owner_type: "anonymous",
        owner_id: "anonymous-id",
        iat: 1782950400,
        exp: 1782951300,
      },
      "wrong-secret",
    );

    await expect(
      verifyAccessToken(
        token,
        "test-secret",
        new Date("2026-07-02T00:00:00.000Z"),
      ),
    ).resolves.toEqual({
      valid: false,
      reason: "invalid_signature",
    });
  });

  it("rejects blank JWT secrets during verification so bearer tokens are never trusted with an empty key", async () => {
    const token = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "anonymous-id",
        session_id: "session-id",
      },
      "test-secret",
      new Date("2026-07-02T00:00:00.000Z"),
    );

    await expect(verifyAccessToken(token, "   ")).rejects.toThrow(
      "JWT secret is required.",
    );
  });

  it("rejects access tokens with a signature length mismatch before trusting bearer claims", async () => {
    const token = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "anonymous-id",
        session_id: "session-id",
      },
      "test-secret",
      new Date("2026-07-02T00:00:00.000Z"),
    );
    const [encodedHeader, encodedPayload] = token.split(".") as [
      string,
      string,
      string,
    ];

    await expect(
      verifyAccessToken(
        `${encodedHeader}.${encodedPayload}.AA`,
        "test-secret",
        new Date("2026-07-02T00:00:00.000Z"),
      ),
    ).resolves.toEqual({
      valid: false,
      reason: "invalid_signature",
    });
  });

  it("rejects expired access tokens at the exp boundary to cap authorization lifetime", async () => {
    const token = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: "anonymous-id",
        session_id: "session-id",
      },
      "test-secret",
      new Date("2026-07-02T00:00:00.000Z"),
    );

    await expect(
      verifyAccessToken(
        token,
        "test-secret",
        new Date("2026-07-02T00:15:00.000Z"),
      ),
    ).resolves.toEqual({
      valid: false,
      reason: "expired",
    });
  });

  it.each<[string, () => string | Promise<string>]>([
    ["non-three-segment token", () => "not-a-jwt"],
    [
      "non-JSON header",
      () => signJwtParts(
        encodeTextPart("not-json"),
        encodeJwtPart({
          owner_type: "anonymous",
          owner_id: "anonymous-id",
          session_id: "session-id",
          iat: 1782950400,
          exp: 1782951300,
        }),
        "test-secret",
      ),
    ],
    [
      "non-JSON payload",
      () => signJwtParts(
        encodeJwtPart({ alg: "HS256", typ: "JWT" }),
        encodeTextPart("not-json"),
        "test-secret",
      ),
    ],
    [
      "non-HS256 alg",
      () => signJwt(
        { alg: "none", typ: "JWT" },
        {
          owner_type: "anonymous",
          owner_id: "anonymous-id",
          session_id: "session-id",
          iat: 1782950400,
          exp: 1782951300,
        },
        "test-secret",
      ),
    ],
    [
      "non-JWT typ",
      () => signJwt(
        { alg: "HS256", typ: "JWS" },
        {
          owner_type: "anonymous",
          owner_id: "anonymous-id",
          session_id: "session-id",
          iat: 1782950400,
          exp: 1782951300,
        },
        "test-secret",
      ),
    ],
    [
      "missing typ",
      () => signJwt(
        { alg: "HS256" },
        {
          owner_type: "anonymous",
          owner_id: "anonymous-id",
          session_id: "session-id",
          iat: 1782950400,
          exp: 1782951300,
        },
        "test-secret",
      ),
    ],
    [
      "missing payload field",
      () => signJwt(
        { alg: "HS256", typ: "JWT" },
        {
          owner_type: "anonymous",
          owner_id: "anonymous-id",
          iat: 1782950400,
          exp: 1782951300,
        },
        "test-secret",
      ),
    ],
    [
      "invalid owner type",
      () => signJwt(
        { alg: "HS256", typ: "JWT" },
        {
          owner_type: "service",
          owner_id: "anonymous-id",
          session_id: "session-id",
          iat: 1782950400,
          exp: 1782951300,
        },
        "test-secret",
      ),
    ],
    [
      "non-string owner id",
      () => signJwt(
        { alg: "HS256", typ: "JWT" },
        {
          owner_type: "anonymous",
          owner_id: 42,
          session_id: "session-id",
          iat: 1782950400,
          exp: 1782951300,
        },
        "test-secret",
      ),
    ],
    [
      "non-number issued-at time",
      () => signJwt(
        { alg: "HS256", typ: "JWT" },
        {
          owner_type: "anonymous",
          owner_id: "anonymous-id",
          session_id: "session-id",
          iat: "1782950400",
          exp: 1782951300,
        },
        "test-secret",
      ),
    ],
  ])(
    "rejects %s as malformed so ambiguous bearer credentials are never authorized",
    async (_, createToken) => {
      const token = await createToken();

      await expect(
        verifyAccessToken(
          token,
          "test-secret",
          new Date("2026-07-02T00:00:00.000Z"),
        ),
      ).resolves.toEqual({
        valid: false,
        reason: "malformed",
      });
    },
  );

  it("creates unique base64url refresh tokens so plaintext bearer secrets can be returned once", () => {
    const firstToken = createRefreshToken();
    const secondToken = createRefreshToken();

    expect(firstToken).not.toBe(secondToken);
    expect(firstToken).toHaveLength(43);
    expect(secondToken).toHaveLength(43);
    expect(firstToken).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(secondToken).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  it("hashes refresh tokens to stable lowercase hex so sessions do not store plaintext secrets", async () => {
    const token = "refresh-token";
    const firstHash = await hashRefreshToken(token);
    const secondHash = await hashRefreshToken(token);

    expect(firstHash).toMatch(/^[a-f0-9]{64}$/);
    expect(firstHash).toBe(
      "0eb17643d4e9261163783a420859c92c7d212fa9624106a12b510afbec266120",
    );
    expect(firstHash).not.toBe(token);
    expect(secondHash).toBe(firstHash);
  });

  it("hashes passwords with versioned PBKDF2 metadata so registrations never store plaintext credentials", async () => {
    const password = "correct horse battery staple";

    const storedHash = await hashPassword(password);

    const parts = storedHash.split("$");
    expect(parts).toHaveLength(5);
    expect(parts).toEqual([
      PASSWORD_HASH_ALGORITHM,
      PASSWORD_HASH_VERSION,
      String(PASSWORD_HASH_ITERATIONS),
      expect.stringMatching(/^[A-Za-z0-9_-]+$/),
      expect.stringMatching(/^[A-Za-z0-9_-]+$/),
    ]);
    expect(storedHash).not.toContain(password);
  });

  it("keeps password hashing within the Cloudflare Workers PBKDF2 limit so edge login can verify credentials", () => {
    expect(PASSWORD_HASH_ITERATIONS).toBeLessThanOrEqual(100_000);
  });

  it("uses a random salt for each password hash while keeping both hashes verifiable", async () => {
    const password = "correct password";

    const firstHash = await hashPassword(password);
    const secondHash = await hashPassword(password);

    expect(firstHash).not.toBe(secondHash);
    await expect(verifyPassword(password, firstHash)).resolves.toBe(true);
    await expect(verifyPassword(password, secondHash)).resolves.toBe(true);
  });

  it("verifies the matching password so login can authenticate stored credentials", async () => {
    const storedHash = await hashPassword("correct password");

    await expect(verifyPassword("correct password", storedHash)).resolves.toBe(
      true,
    );
  });

  it("rejects the wrong password so a stored hash cannot authenticate another credential", async () => {
    const storedHash = await hashPassword("correct password");

    await expect(verifyPassword("wrong password", storedHash)).resolves.toBe(
      false,
    );
  });

  it.each<[string, () => string | Promise<string>]>([
    [
      "unsupported algorithm",
      () => createStoredPasswordHash("password", { algorithm: "argon2id" }),
    ],
    [
      "unknown version",
      () => createStoredPasswordHash("password", { version: "v2" }),
    ],
    ["unsupported format", () => "not-a-password-hash"],
    [
      "non-decimal iterations",
      async () =>
        replacePasswordHashPart(
          await createStoredPasswordHash("password"),
          2,
          `${PASSWORD_HASH_ITERATIONS}.0`,
        ),
    ],
    [
      "non-current iterations",
      () =>
        createStoredPasswordHash("password", {
          iterations: PASSWORD_HASH_ITERATIONS - 1,
        }),
    ],
    [
      "invalid base64url salt",
      async () =>
        replacePasswordHashPart(
          await createStoredPasswordHash("password"),
          3,
          "not+base64url",
        ),
    ],
    [
      "short salt",
      () =>
        createStoredPasswordHash("password", {
          salt: new Uint8Array([1]),
        }),
    ],
    [
      "short hash",
      () =>
        createStoredPasswordHash("password", {
          hash: new Uint8Array([1]),
        }),
    ],
  ])("fails closed for %s password hashes", async (_, createStoredHash) => {
    await expect(
      verifyPassword("password", await createStoredHash()),
    ).resolves.toBe(false);
  });

  it("expires refresh token sessions after 30 days to bound anonymous session lifetime", () => {
    expect(refreshTokenExpiresAt(new Date("2026-07-02T00:00:00.000Z"))).toBe(
      "2026-08-01T00:00:00.000Z",
    );
  });
});
