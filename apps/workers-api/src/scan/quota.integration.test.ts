import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { AuthenticatedOwner } from "../owner-auth";
import {
  loadScanQuota,
  releaseQueuedScanQuota,
  reserveScanQuota,
  settleScanQuota,
} from "./quota";

const OWNER: AuthenticatedOwner = {
  owner_type: "user",
  owner_id: "100001",
  session_id: "session-1",
};

describe("server-authoritative scan quota", () => {
  let mf: Miniflare;
  let db: D1Database;

  beforeEach(async () => {
    mf = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    db = await mf.getD1Database("DB");
    for (const statement of SCHEMA) await db.prepare(statement).run();
  });

  afterEach(async () => mf.dispose());

  it("atomically reserves the last shared scan because two devices must not consume one slot", async () => {
    for (let index = 0; index < 9; index += 1) {
      await db
        .prepare(
          "INSERT INTO scan_quota_request VALUES (?, ?, ?, ?, 'free', 'consumed', NULL, NULL, 1, NULL, NULL, ?, ?, ?)",
        )
        .bind(
          `used-${index}`,
          OWNER.owner_type,
          OWNER.owner_id,
          OWNER.session_id,
          NOW,
          NOW,
          NOW,
        )
        .run();
    }
    const otherSession = { ...OWNER, session_id: "session-2" };

    const results = await Promise.all([
      reserveScanQuota(db, OWNER, crypto.randomUUID(), "free"),
      reserveScanQuota(db, otherSession, crypto.randomUUID(), "free"),
    ]);

    expect(results.filter((result) => result.status === "reserved")).toHaveLength(1);
    expect(results.filter((result) => result.status === "exhausted")).toHaveLength(1);
    expect(await loadScanQuota(db, OWNER)).toEqual({ limit: 10, reserved: 1, consumed: 9, remaining: 0 });
  });

  it("keeps reservation and settlement idempotent because retries must not double charge", async () => {
    const requestId = crypto.randomUUID();
    expect((await reserveScanQuota(db, OWNER, requestId, "free")).status).toBe("reserved");
    expect((await reserveScanQuota(db, OWNER, requestId, "free")).status).toBe("existing");

    await settleScanQuota(db, OWNER, requestId, "consumed", "scan-1");
    await settleScanQuota(db, OWNER, requestId, "consumed", "scan-1");

    expect(await loadScanQuota(db, OWNER)).toEqual({ limit: 10, reserved: 0, consumed: 1, remaining: 9 });
  });

  it("releases technical failures and never spends Free quota for Premium", async () => {
    const failedRequest = crypto.randomUUID();
    await reserveScanQuota(db, OWNER, failedRequest, "free");
    await settleScanQuota(db, OWNER, failedRequest, "released", null);
    const premiumRequest = crypto.randomUUID();
    await reserveScanQuota(db, OWNER, premiumRequest, "premium");
    await settleScanQuota(db, OWNER, premiumRequest, "consumed", "scan-pro");

    expect(await loadScanQuota(db, OWNER)).toEqual({ limit: 10, reserved: 0, consumed: 0, remaining: 10 });
  });

  it("locks only Free reservations because Premium does not consume the shared limit", async () => {
    await reserveScanQuota(db, OWNER, crypto.randomUUID(), "premium");
    await expect(db.prepare("SELECT COUNT(*) FROM mutation_lock").first<number>("COUNT(*)"))
      .resolves.toBe(0);

    await reserveScanQuota(db, OWNER, crypto.randomUUID(), "free");
    const lock = await db.prepare("SELECT lock_key FROM mutation_lock").first<{ lock_key: string }>();

    expect(lock?.lock_key).toMatch(/^scan-quota:[0-9a-f]{64}$/);
    expect(lock?.lock_key).not.toContain(OWNER.owner_id);
  });

  it("only takes over an expired lease because concurrent retries must not duplicate OCR", async () => {
    const requestId = crypto.randomUUID();
    await reserveScanQuota(db, OWNER, requestId, "free", new Date(NOW));

    expect(
      (await reserveScanQuota(db, OWNER, requestId, "free", new Date("2026-08-12T12:00:30.000Z"))).status,
    ).toBe("existing");
    const takeoverTime = new Date("2026-08-12T12:01:01.000Z");
    const results = await Promise.all([
      reserveScanQuota(db, OWNER, requestId, "free", takeoverTime),
      reserveScanQuota(db, OWNER, requestId, "free", takeoverTime),
    ]);
    expect(results.map((result) => result.status).sort()).toEqual(["existing", "reserved"]);
    await expect(
      db.prepare("SELECT attempts FROM scan_quota_request WHERE request_id = ?")
        .bind(requestId)
        .first<number>("attempts"),
    ).resolves.toBe(2);
  });

  it("stops counting an expired lease and rejects its late settlement because an interrupted Worker must not permanently consume quota", async () => {
    const requestId = crypto.randomUUID();
    await reserveScanQuota(db, OWNER, requestId, "free", new Date(NOW));
    const afterLease = new Date("2026-08-12T12:01:01.000Z");

    expect(await loadScanQuota(db, OWNER, afterLease)).toEqual({
      limit: 10,
      reserved: 0,
      consumed: 0,
      remaining: 10,
    });

    await settleScanQuota(
      db,
      OWNER,
      requestId,
      "consumed",
      "late-scan",
      null,
      afterLease,
    );
    expect(await loadScanQuota(db, OWNER, afterLease)).toEqual({
      limit: 10,
      reserved: 0,
      consumed: 0,
      remaining: 10,
    });
  });

  it("releases an unstarted reservation because preflight failures must restore the slot immediately", async () => {
    const requestId = crypto.randomUUID();
    await reserveScanQuota(
      db,
      OWNER,
      requestId,
      "free",
      new Date(NOW),
      { startProcessing: false },
    );

    await releaseQueuedScanQuota(
      db,
      OWNER,
      requestId,
      { body: { success: false }, status: 503 },
      new Date(NOW),
    );

    expect(await loadScanQuota(db, OWNER, new Date(NOW))).toEqual({
      limit: 10,
      reserved: 0,
      consumed: 0,
      remaining: 10,
    });
  });
});

const NOW = "2026-08-12T12:00:00.000Z";
const SCHEMA = [
  "CREATE TABLE mutation_lock (lock_key TEXT PRIMARY KEY)",
  "CREATE TABLE session (id TEXT PRIMARY KEY)",
  "INSERT INTO session (id) VALUES ('session-1')",
  "INSERT INTO session (id) VALUES ('session-2')",
  "CREATE TABLE scan_quota_request (request_id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, session_id TEXT NOT NULL REFERENCES session(id), access_mode TEXT NOT NULL, status TEXT NOT NULL, scan_id TEXT, processing_expires_at TEXT, attempts INTEGER NOT NULL, response_json TEXT, http_status INTEGER, created_at TEXT NOT NULL, settled_at TEXT, updated_at TEXT NOT NULL)",
];
