import { base64Url, fetchWithDeadline, googleAccessToken } from "../auth/google-service-account";
import type { Env } from "../env";

export class PlayError extends Error {
  constructor(readonly code: string, readonly status: 403 | 404 | 409 | 422 | 503 = 503) { super(code); }
}

export function tokenValid(value: unknown): value is string {
  return typeof value === "string" && /^[\x21-\x7e]{1,4096}$/.test(value);
}

export async function publisher(env: Env, path: string, method = "GET"): Promise<unknown> {
  const email = env.GOOGLE_PLAY_PUBLISHER_EMAIL?.trim();
  const key = env.GOOGLE_PLAY_PUBLISHER_PRIVATE_KEY?.trim();
  const pkg = env.GOOGLE_PLAY_PACKAGE_NAME?.trim();
  if (!email || !key || !pkg) throw new PlayError("GOOGLE_PLAY_UNAVAILABLE");
  try {
    const auth = await googleAccessToken(email, key, "https://www.googleapis.com/auth/androidpublisher", new Date());
    const response = await fetchWithDeadline(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(pkg)}/${path}`,
      { method, headers: { Authorization: `Bearer ${auth}`, ...(method === "POST" ? { "Content-Type": "application/json" } : {}) },
        ...(method === "POST" ? { body: "{}" } : {}) });
    if (response.ok) return response.body;
    if ([400, 404, 410].includes(response.status)) throw new PlayError("GOOGLE_PLAY_RECORD_NOT_FOUND", 404);
    throw new PlayError([401, 403].includes(response.status) ? "GOOGLE_PLAY_PUBLISHER_PERMISSION" : "GOOGLE_PLAY_UPSTREAM_UNAVAILABLE");
  } catch (error) {
    if (error instanceof PlayError) throw error;
    throw new PlayError("GOOGLE_PLAY_UPSTREAM_UNAVAILABLE");
  }
}

const utf8 = new TextEncoder();
function decode(text: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
}
function secretKey(value?: string) {
  if (!value || !/^[A-Za-z0-9_-]{43}$/.test(value)) throw new PlayError("GOOGLE_PLAY_KEY_UNAVAILABLE");
  return decode(value);
}

export async function playDigest(env: Env, scope: string, usage: "account" | "token", text: string) {
  const key = await crypto.subtle.importKey("raw", secretKey(env.GOOGLE_PLAY_TOKEN_HASH_KEY), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return base64Url(new Uint8Array(await crypto.subtle.sign("HMAC", key, utf8.encode(`${scope}\n${usage}\n${text}`))));
}

// The first key encrypts new records. Retain previous key IDs until their ciphertexts are re-encrypted.
async function encryptionKey(env: Env, id?: string) {
  const keys = (env.GOOGLE_PLAY_ENCRYPTION_KEYS ?? "").split(",").map(item => item.trim().split(":"));
  const entry = id ? keys.find(([name]) => name === id) : keys[0];
  if (!entry || entry.length !== 2 || !/^[a-zA-Z0-9_-]{1,32}$/.test(entry[0]!)) throw new PlayError("GOOGLE_PLAY_KEY_UNAVAILABLE");
  return { id: entry[0]!, key: await crypto.subtle.importKey("raw", secretKey(entry[1]), "AES-GCM", false, ["encrypt", "decrypt"]) };
}
export async function sealToken(env: Env, scope: string, token: string) {
  const { id, key } = await encryptionKey(env);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const bytes = await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: utf8.encode(scope) }, key, utf8.encode(token));
  return `${id}.${base64Url(iv)}.${base64Url(new Uint8Array(bytes))}`;
}
export async function openToken(env: Env, scope: string, sealed: string) {
  const [id, iv, body] = sealed.split(".");
  if (!id || !iv || !body) throw new PlayError("GOOGLE_PLAY_KEY_UNAVAILABLE");
  const { key } = await encryptionKey(env, id);
  return new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv: decode(iv), additionalData: utf8.encode(scope) }, key, decode(body)));
}
