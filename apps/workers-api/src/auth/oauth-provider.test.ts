import { afterEach, describe, expect, it, vi } from "vitest";
import {
  resolveAppleIdentity,
  resolveGoogleIdentity,
} from "./oauth-provider";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("resolveGoogleIdentity", () => {
  it("rejects mock tokens because production login requires Google proof", async () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);

    const identity = await resolveGoogleIdentity(
      {
        idToken: "mock-google:user-1:user@example.com",
      },
      "google-client-id",
    );

    expect(identity).toBeNull();
    expect(fetchSpy).toHaveBeenCalledOnce();
  });

  it("accepts only verified Google identity claims for the configured app", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json({
          iss: "https://accounts.google.com",
          aud: "google-client-id",
          sub: "google-user-1",
          email: "User@Example.com",
          email_verified: "true",
        }),
      ),
    );

    await expect(
      resolveGoogleIdentity(
        { idToken: "real-google-id-token" },
        "google-client-id",
      ),
    ).resolves.toEqual({
      provider: "google",
      providerUid: "google-user-1",
      email: "user@example.com",
    });
  });
});

describe("resolveAppleIdentity", () => {
  it("accepts only a signed, current Apple identity token for the configured app", async () => {
    const keys = await createRsaKeyPair();
    const publicJwk = await crypto.subtle.exportKey("jwk", keys.publicKey);
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json({ keys: [{ ...publicJwk, kid: "apple-key-1", alg: "RS256" }] }),
      ),
    );
    const now = Math.floor(Date.now() / 1000);
    const token = await signJwt(
      keys.privateKey,
      { alg: "RS256", kid: "apple-key-1" },
      {
        iss: "https://appleid.apple.com",
        aud: "com.kando.kandoApp",
        sub: "apple.user-1",
        email: "APPLE.USER@example.com",
        email_verified: "true",
        iat: now,
        exp: now + 300,
      },
    );

    await expect(
      resolveAppleIdentity(
        { code: "authorization-code", idToken: token },
        "com.kando.kandoApp",
      ),
    ).resolves.toEqual({
      provider: "apple",
      providerUid: "apple.user-1",
      email: "apple.user@example.com",
    });
  });

  it("rejects a signed Apple token issued for another app", async () => {
    const keys = await createRsaKeyPair();
    const publicJwk = await crypto.subtle.exportKey("jwk", keys.publicKey);
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json({ keys: [{ ...publicJwk, kid: "apple-key-1", alg: "RS256" }] }),
      ),
    );
    const now = Math.floor(Date.now() / 1000);
    const token = await signJwt(
      keys.privateKey,
      { alg: "RS256", kid: "apple-key-1" },
      {
        iss: "https://appleid.apple.com",
        aud: "another-app",
        sub: "apple.user-1",
        email: "apple.user@example.com",
        email_verified: "true",
        iat: now,
        exp: now + 300,
      },
    );

    await expect(
      resolveAppleIdentity(
        { code: "authorization-code", idToken: token },
        "com.kando.kandoApp",
      ),
    ).resolves.toBeNull();
  });
});

async function createRsaKeyPair(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  ) as Promise<CryptoKeyPair>;
}

async function signJwt(
  privateKey: CryptoKey,
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
): Promise<string> {
  const unsigned = createUnsignedJwt(header, payload).slice(0, -1);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${encodeBase64Url(new Uint8Array(signature))}`;
}

function createUnsignedJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
): string {
  return `${encodeJson(header)}.${encodeJson(payload)}.`;
}

function encodeJson(value: Record<string, unknown>): string {
  return encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function encodeBase64Url(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
