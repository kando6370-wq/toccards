import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { hashRefreshToken, signAccessToken } from "@kando/auth-core";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { authRoutes } from "./anonymous";

const migrations = new URL("../db/postgres/migrations/", import.meta.url);
const JWT_SECRET = "session-lifecycle-postgres-secret";

describe("PostgreSQL auth session lifecycle", () => {
  let db: PGliteDatabase;
  let env: Env;

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    await db.exec(readFileSync(new URL("0000_business_schema.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0006_mutation_lock.sql", migrations), "utf8"));
    await db.exec(readFileSync(new URL("0018_platform_account_isolation.sql", migrations), "utf8"));
    env = { DB: db, CACHE_KV: {} as KVNamespace, JWT_SECRET };
  });

  afterEach(async () => { await db.close(); });

  it("creates and reuses an iOS guest while each session keeps a distinct hashed refresh token", async () => {
    const first = await anonymous("same-device");
    const second = await anonymous("same-device");
    expect(first.response.status).toBe(200);
    expect(second.response.status).toBe(200);
    expect(second.body.anonymous_id).toBe(first.body.anonymous_id);
    expect(second.body.refresh_token).not.toBe(first.body.refresh_token);
    const rows = await db.query<{ refresh_token: string }>(
      "SELECT refresh_token FROM session WHERE owner_id = $1 ORDER BY created_at, id",
      [first.body.anonymous_id],
    );
    expect(rows.rows).toHaveLength(2);
    expect(rows.rows.map((row) => row.refresh_token)).not.toContain(first.body.refresh_token);
    const defaults = await db.query<{ folders: number; preferences: number }>(`
      SELECT (SELECT COUNT(*) FROM portfolio_folder WHERE owner_id = $1 AND is_default = 1)::int AS folders,
        (SELECT COUNT(*) FROM user_preference WHERE owner_id = $1)::int AS preferences`,
      [first.body.anonymous_id],
    );
    expect(defaults.rows[0]).toEqual({ folders: 1, preferences: 1 });
  });

  it("records trusted installation platform and Cloudflare country without accepting a blank device", async () => {
    const request = new Request("https://example.test/anonymous", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: "country-device", platform: "ios" }),
    });
    Object.defineProperty(request, "cf", { value: { country: "US" } });
    const response = await authRoutes.request(request, undefined, env);
    expect(response.status).toBe(200);
    const installation = await db.query<{ platform: string; country_code: string }>(
      "SELECT platform, country_code FROM app_installation WHERE installation_id = 'country-device'",
    );
    expect(installation.rows[0]).toEqual({ platform: "iOS", country_code: "US" });
    expect((await authRoutes.request("/anonymous", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: "", platform: "ios" }),
    }, env)).status).toBe(422);
  });

  it("does not create partial anonymous state when signing is unavailable", async () => {
    env.JWT_SECRET = "";
    expect((await authRoutes.request("/anonymous", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: "no-secret", platform: "ios" }),
    }, env)).status).toBe(500);
    const counts = await db.query<{ accounts: number; sessions: number }>(`
      SELECT (SELECT COUNT(*) FROM anonymous_account)::int AS accounts,
             (SELECT COUNT(*) FROM session)::int AS sessions`);
    expect(counts.rows[0]).toEqual({ accounts: 0, sessions: 0 });
  });

  it("refreshes, reports the server-confirmed platform owner, then logout blocks renewal", async () => {
    const created = await anonymous("device-1");
    const me = await authRoutes.request("/me", {
      headers: { Authorization: `Bearer ${created.body.access_token}` },
    }, env);
    expect(me.status).toBe(200);
    await expect(me.json()).resolves.toMatchObject({ data: {
      owner_type: "anonymous", anonymous_id: created.body.anonymous_id,
      platform: "ios", data_space_id: created.body.anonymous_id,
    } });

    const storedBefore = await db.query<{ refresh_token: string }>(
      "SELECT refresh_token FROM session WHERE owner_id = $1 ORDER BY created_at DESC LIMIT 1",
      [created.body.anonymous_id],
    );
    const refreshed = await refresh(created.body.refresh_token);
    expect(refreshed.status).toBe(200);
    const refreshedBody = await refreshed.json() as { data: {
      access_token: string; refresh_token?: string;
    } };
    expect(refreshedBody.data.refresh_token).toBeUndefined();
    expect((await authRoutes.request("/me", {
      headers: { Authorization: `Bearer ${refreshedBody.data.access_token}` },
    }, env)).status).toBe(200);
    const storedAfter = await db.query<{ refresh_token: string }>(
      "SELECT refresh_token FROM session WHERE owner_id = $1 ORDER BY created_at DESC LIMIT 1",
      [created.body.anonymous_id],
    );
    expect(storedAfter.rows[0]?.refresh_token).toBe(storedBefore.rows[0]?.refresh_token);
    const logout = await authRoutes.request("/logout", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${created.body.access_token}`,
      },
      body: JSON.stringify({ refresh_token: created.body.refresh_token }),
    }, env);
    expect(logout.status).toBe(200);
    expect((await refresh(created.body.refresh_token)).status).toBe(401);
  });

  it.each([
    [undefined, 422],
    ["unknown-refresh-token", 401],
  ])("rejects unusable refresh proof %#", async (token, status) => {
    expect((await refresh(token)).status).toBe(status);
  });

  it("does not reuse an expired or upgraded anonymous owner", async () => {
    const created = await anonymous("device-1");
    await db.prepare("UPDATE session SET expires_at = '2000-01-01' WHERE owner_id = ?")
      .bind(created.body.anonymous_id).run();
    expect((await refresh(created.body.refresh_token)).status).toBe(401);
    const replacement = await anonymous("device-1");
    await db.prepare("UPDATE anonymous_account SET upgraded_user_id = 'claimed' WHERE id = ?")
      .bind(replacement.body.anonymous_id).run();
    const next = await anonymous("device-1");
    expect(next.body.anonymous_id).not.toBe(replacement.body.anonymous_id);
  });

  it("reuses the stable lowest id when historical live guests share device and creation time", async () => {
    await db.exec(`INSERT INTO anonymous_account
      (id, device_id, created_at, upgraded_user_id, platform, status) VALUES
      ('guest-b', 'migrated-device', '2026-01-01', NULL, 'ios', 'active'),
      ('guest-a', 'migrated-device', '2026-01-01', NULL, 'ios', 'active')`);
    const created = await anonymous("migrated-device");
    expect(created.body.anonymous_id).toBe("guest-a");
  });

  it.each([
    [undefined, 401],
    ["Basic invalid", 401],
    ["Bearer tampered", 401],
  ])("rejects untrusted /me authorization %#", async (authorization, status) => {
    const headers = authorization ? { Authorization: authorization } : undefined;
    expect((await authRoutes.request("/me", { headers }, env)).status).toBe(status);
  });

  it("rejects /me when its persisted session is revoked, expired, missing, or its owner is gone", async () => {
    for (const mode of ["revoked", "expired", "missing-session", "missing-owner"] as const) {
      const created = await anonymous(`device-${mode}`);
      if (mode === "revoked") {
        await db.prepare("UPDATE session SET revoked_at = '2026-11-05' WHERE owner_id = ?")
          .bind(created.body.anonymous_id).run();
      } else if (mode === "expired") {
        await db.prepare("UPDATE session SET expires_at = '2000-01-01' WHERE owner_id = ?")
          .bind(created.body.anonymous_id).run();
      } else if (mode === "missing-session") {
        await db.prepare("DELETE FROM session WHERE owner_id = ?")
          .bind(created.body.anonymous_id).run();
      } else {
        await db.prepare("UPDATE anonymous_account SET status = 'deleted' WHERE id = ?")
          .bind(created.body.anonymous_id).run();
      }
      expect((await authRoutes.request("/me", {
        headers: { Authorization: `Bearer ${created.body.access_token}` },
      }, env)).status).toBe(401);
    }
  });

  it("fails /me loudly when token verification is not configured", async () => {
    env.JWT_SECRET = "";
    expect((await authRoutes.request("/me", {
      headers: { Authorization: "Bearer any-token" },
    }, env)).status).toBe(500);
  });

  it("rejects an expired access token even while its persisted session remains live", async () => {
    const created = await anonymous("device-expired-token");
    const row = await db.query<{ id: string }>(
      "SELECT id FROM session WHERE owner_id = $1 ORDER BY created_at DESC LIMIT 1",
      [created.body.anonymous_id],
    );
    const expired = await signAccessToken({
      owner_type: "anonymous", owner_id: created.body.anonymous_id,
      session_id: row.rows[0]!.id,
    }, JWT_SECRET, new Date("2000-01-01T00:00:00Z"));
    expect((await authRoutes.request("/me", {
      headers: { Authorization: `Bearer ${expired}` },
    }, env)).status).toBe(401);
  });

  it("logout requires matching bearer and refresh proofs and cannot revoke another session", async () => {
    const first = await anonymous("device-logout-1");
    const second = await anonymous("device-logout-2");
    const request = (authorization: string | undefined, refreshToken: string | undefined) =>
      authRoutes.request("/logout", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(authorization ? { Authorization: authorization } : {}),
        },
        body: JSON.stringify(refreshToken ? { refresh_token: refreshToken } : {}),
      }, env);
    expect((await request(undefined, first.body.refresh_token)).status).toBe(401);
    expect((await request("Basic invalid", first.body.refresh_token)).status).toBe(401);
    expect((await request("Bearer tampered", first.body.refresh_token)).status).toBe(401);
    expect((await request(`Bearer ${first.body.access_token}`, undefined)).status).toBe(422);
    expect((await request(
      `Bearer ${first.body.access_token}`, second.body.refresh_token,
    )).status).toBe(401);
    expect((await refresh(first.body.refresh_token)).status).toBe(200);
    env.JWT_SECRET = "";
    expect((await request(
      `Bearer ${first.body.access_token}`, first.body.refresh_token,
    )).status).toBe(500);
  });

  it("rejects malformed owner state and missing signing configuration during refresh", async () => {
    const malformed = await anonymous("device-malformed");
    await db.prepare("UPDATE session SET expires_at = 'not-a-date' WHERE owner_id = ?")
      .bind(malformed.body.anonymous_id).run();
    expect((await refresh(malformed.body.refresh_token)).status).toBe(401);

    const untrusted = await anonymous("device-untrusted");
    await db.prepare("UPDATE session SET owner_type = 'admin' WHERE owner_id = ?")
      .bind(untrusted.body.anonymous_id).run();
    expect((await refresh(untrusted.body.refresh_token)).status).toBe(401);

    const configured = await anonymous("device-config");
    env.JWT_SECRET = "";
    expect((await refresh(configured.body.refresh_token)).status).toBe(500);
  });

  it("refreshes a live user space but never revives a deleted platform owner", async () => {
    await db.exec(`
      INSERT INTO "user" (id, email, created_at, updated_at, status)
      VALUES ('user-1', 'user@example.com', '2026-11-05', '2026-11-05', 'active');
      INSERT INTO platform_account (id, user_id, platform, status, created_at, updated_at)
      VALUES ('user-1', 'user-1', 'ios', 'active', '2026-11-05', '2026-11-05');
    `);
    const refreshToken = "user-refresh";
    await db.prepare(`INSERT INTO session
      (id, owner_type, owner_id, refresh_token, expires_at, created_at, platform, user_id)
      VALUES ('user-session', 'user', 'user-1', ?, '2099-01-01', '2026-11-05', 'ios', 'user-1')`)
      .bind(await hashRefreshToken(refreshToken)).run();
    expect((await refresh(refreshToken)).status).toBe(200);
    await db.exec(`
      UPDATE platform_account SET status = 'deleted', deleted_at = '2026-11-05' WHERE id = 'user-1';
      UPDATE "user" SET status = 'deleted', deleted_at = '2026-11-05' WHERE id = 'user-1';
    `);
    expect((await refresh(refreshToken)).status).toBe(401);
  });

  async function anonymous(deviceId: string): Promise<{
    response: Response;
    body: { anonymous_id: string; access_token: string; refresh_token: string };
  }> {
    const response = await authRoutes.request("/anonymous", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: deviceId, platform: "ios" }),
    }, env);
    return {
      response,
      body: (await response.json() as { data: {
        anonymous_id: string; access_token: string; refresh_token: string;
      } }).data,
    };
  }

  async function refresh(refreshToken: string | undefined): Promise<Response> {
    return await authRoutes.request("/token/refresh", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(refreshToken ? { refresh_token: refreshToken } : {}),
    }, env);
  }
});
