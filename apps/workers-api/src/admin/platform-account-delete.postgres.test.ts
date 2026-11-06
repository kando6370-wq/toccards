import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { hashPassword } from "@kando/auth-core";
import { Hono } from "hono";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { adminRoutes } from "./routes";

const NOW = "2026-11-05T00:00:00.000Z";

describe("Admin platform account deletion on PostgreSQL", () => {
  let db: PGliteDatabase;
  let env: Env;
  let superToken: string;
  let operatorToken: string;
  let failImageDelete: boolean;
  const deletedImages: string[] = [];
  const app = new Hono<{ Bindings: Env }>().route("/admin", adminRoutes);

  beforeEach(async () => {
    db = await PGliteDatabase.create();
    const migrations = new URL("../db/postgres/migrations/", import.meta.url);
    for (const name of ["0000_business_schema.sql", "0006_mutation_lock.sql", "0018_platform_account_isolation.sql"]) {
      await db.exec(readFileSync(new URL(name, migrations), "utf8"));
    }
    const password = await hashPassword("admin-delete-password");
    await db.prepare(`INSERT INTO admin_user
      (id,email,password_hash,role,status,created_at) VALUES
      ('super','super@example.com',?,'super_admin','active',?),
      ('operator','operator@example.com',?,'operator','active',?)`)
      .bind(password, NOW, password, NOW).run();
    await db.exec(`
      INSERT INTO "user" (id,email,created_at,updated_at,status)
      VALUES ('base-user','user@example.com','${NOW}','${NOW}','active');
      INSERT INTO platform_account (id,user_id,platform,status,created_at,updated_at) VALUES
      ('ios-space','base-user','ios','active','${NOW}','${NOW}'),
      ('android-space','base-user','android','active','${NOW}','${NOW}');
      INSERT INTO session
        (id,owner_type,owner_id,refresh_token,expires_at,created_at,platform,user_id) VALUES
      ('ios-session-1','user','ios-space','ios-refresh-1','2099-01-01','${NOW}','ios','base-user'),
      ('ios-session-2','user','ios-space','ios-refresh-2','2099-01-01','${NOW}','ios','base-user'),
      ('android-session','user','android-space','android-refresh','2099-01-01','${NOW}','android','base-user');
      INSERT INTO portfolio_folder
        (id,owner_type,owner_id,name,is_default,sort_order,created_at,updated_at) VALUES
      ('ios-folder','user','ios-space','Main',1,0,'${NOW}','${NOW}'),
      ('android-folder','user','android-space','Main',1,0,'${NOW}','${NOW}');
      INSERT INTO scan_record
        (id,owner_type,owner_id,image_url,filename,platform,app_version,
         recognition_status,user_confirmation_status,system_result,user_result,
         candidates,raw_response,created_at)
      VALUES ('ios-scan','user','ios-space','ios-image','scan.jpg','iOS','1.0',
        'success','pending','{}','{}','[]','{}','${NOW}');
    `);
    failImageDelete = false;
    deletedImages.length = 0;
    env = {
      DB: db,
      CACHE_KV: {} as KVNamespace,
      JWT_SECRET: "admin-delete-secret",
      APP_ENVIRONMENT: "development",
      SCAN_IMAGES: {
        delete: async (keys: string | string[]) => {
          if (failImageDelete) throw new Error("R2 unavailable");
          deletedImages.push(...(Array.isArray(keys) ? keys : [keys]));
        },
      } as unknown as R2Bucket,
    };
    superToken = await login("super@example.com");
    operatorToken = await login("operator@example.com");
  });

  afterEach(async () => { vi.restoreAllMocks(); await db.close(); });

  it("allows only super_admin and requires explicit platform confirmation", async () => {
    expect((await remove(operatorToken, "ios-space", "ios")).status).toBe(403);
    expect((await request(superToken, "ios-space", {})).status).toBe(422);
    expect((await request(superToken, "ios-space", {
      platform: "ios", confirmation: "wrong",
    })).status).toBe(422);
    expect((await remove(superToken, "ios-space", "android")).status).toBe(422);
    expect((await remove(superToken, "missing-space", "ios")).status).toBe(404);
    expect((await remove(superToken, "base-user", "ios")).status).toBe(404);
  });

  it("deletes one platform across devices while preserving the other platform", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});
    const response = await remove(superToken, "ios-space", "ios", "request-delete-ios");
    expect(response.status).toBe(200);
    expect(await status("ios-space")).toBe("deleted");
    expect(await status("android-space")).toBe("active");
    expect(await userStatus()).toBe("active");
    expect(await sessionRevoked("ios-session-1")).not.toBeNull();
    expect(await sessionRevoked("ios-session-2")).not.toBeNull();
    expect(await sessionRevoked("android-session")).toBeNull();
    expect(await folderCount("ios-space")).toBe(0);
    expect(await folderCount("android-space")).toBe(1);
    expect(deletedImages).toEqual(["ios-image"]);
    const audit = logs.mock.calls.map(([, payload]) => JSON.parse(String(payload)));
    expect(audit).toEqual([
      expect.objectContaining({ actor_admin_id: "super", target_owner_id: "ios-space", platform: "ios", request_id: "request-delete-ios", outcome: "started" }),
      expect.objectContaining({ actor_admin_id: "super", target_owner_id: "ios-space", platform: "ios", request_id: "request-delete-ios", outcome: "succeeded" }),
    ]);
    expect(JSON.stringify(audit)).not.toContain("user@example.com");
  });

  it("returns success idempotently for an already deleted platform account", async () => {
    expect((await remove(superToken, "ios-space", "ios")).status).toBe(200);
    const second = await remove(superToken, "ios-space", "ios");
    expect(second.status).toBe(200);
    expect(await second.json()).toMatchObject({
      data: { account_type: "user", id: "ios-space", platform: "ios", status: "deleted" },
    });
  });

  it("deletes a disabled platform account without affecting the other platform", async () => {
    await db.prepare("UPDATE platform_account SET status='disabled' WHERE id='ios-space'").run();
    const response = await remove(superToken, "ios-space", "ios");
    expect(response.status).toBe(200);
    expect(await status("ios-space")).toBe("deleted");
    expect(await status("android-space")).toBe("active");
  });

  it("deletes an anonymous platform space through the same explicit contract", async () => {
    await db.exec(`
      INSERT INTO anonymous_account
        (id,device_id,created_at,upgraded_user_id,platform,status)
      VALUES ('anonymous-space','anonymous-device','${NOW}',NULL,'ios','active');
      INSERT INTO session
        (id,owner_type,owner_id,refresh_token,expires_at,created_at,platform,user_id)
      VALUES ('anonymous-session','anonymous','anonymous-space','anonymous-refresh',
        '2099-01-01','${NOW}','ios',NULL);
      INSERT INTO portfolio_folder
        (id,owner_type,owner_id,name,is_default,sort_order,created_at,updated_at)
      VALUES ('anonymous-folder','anonymous','anonymous-space','Main',1,0,'${NOW}','${NOW}');
    `);
    const response = await request(superToken, "anonymous-space", {
      platform: "ios", confirmation: "DELETE_PLATFORM_ACCOUNT",
    }, undefined, "anonymous");
    expect(response.status).toBe(200);
    expect(await db.prepare("SELECT status FROM anonymous_account WHERE id='anonymous-space'").first("status"))
      .toBe("deleted");
    expect(await folderCount("anonymous-space")).toBe(0);
  });

  it("does not report success when private image deletion fails", async () => {
    failImageDelete = true;
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    const response = await remove(superToken, "ios-space", "ios", "request-r2-failure");
    expect(response.status).toBe(500);
    expect(await status("ios-space")).toBe("deleting");
    expect(await status("android-space")).toBe("active");
    expect(await folderCount("ios-space")).toBe(1);
    expect(await db.prepare("SELECT COUNT(*) AS total FROM scan_record WHERE owner_id='ios-space'").first("total")).toBe(1);
    expect(JSON.parse(String(errors.mock.calls[0]?.[1]))).toMatchObject({
      actor_admin_id: "super", target_owner_id: "ios-space", platform: "ios",
      request_id: "request-r2-failure", outcome: "failed",
    });
  });

  async function login(email: string): Promise<string> {
    const response = await app.request("/admin/auth/login", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: "admin-delete-password" }),
    }, env);
    return ((await response.json()) as { data: { access_token: string } }).data.access_token;
  }
  function request(
    token: string,
    id: string,
    body: object,
    requestId?: string,
    accountType: "user" | "anonymous" = "user",
  ) {
    return app.request(`/admin/users/${accountType}/${id}/account`, {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${token}`, "Content-Type": "application/json",
        ...(requestId ? { "X-Request-ID": requestId } : {}),
      },
      body: JSON.stringify(body),
    }, env);
  }
  function remove(token: string, id: string, platform: string, requestId?: string) {
    return request(token, id, { platform, confirmation: "DELETE_PLATFORM_ACCOUNT" }, requestId);
  }
  async function status(id: string) { return await db.prepare("SELECT status FROM platform_account WHERE id=?").bind(id).first("status"); }
  async function userStatus() { return await db.prepare("SELECT status FROM \"user\" WHERE id='base-user'").first("status"); }
  async function sessionRevoked(id: string) { return await db.prepare("SELECT revoked_at FROM session WHERE id=?").bind(id).first("revoked_at"); }
  async function folderCount(ownerId: string) { return Number(await db.prepare("SELECT COUNT(*) AS total FROM portfolio_folder WHERE owner_id=?").bind(ownerId).first("total") ?? 0); }
});
