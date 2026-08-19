import type { AuthenticatedOwner } from "../owner-auth";
import { mutationLockKey, runWithMutationLock } from "../db/mutation-lock";

export const FREE_SCAN_LIMIT = 10;
const PROCESSING_LEASE_MS = 60_000;

export type ScanQuotaSnapshot = {
  limit: number;
  reserved: number;
  consumed: number;
  remaining: number;
};

export type ScanQuotaReservation =
  | {
      status: "reserved" | "existing";
      accessMode: "free" | "premium";
      requestStatus: "reserved" | "consumed" | "released";
      response: { body: unknown; status: number } | null;
      quota: ScanQuotaSnapshot;
    }
  | { status: "exhausted"; quota: ScanQuotaSnapshot }
  | { status: "conflict" };

type RequestRow = {
  owner_type: string;
  owner_id: string;
  session_id: string;
  access_mode: "free" | "premium";
  status: "reserved" | "consumed" | "released";
  processing_expires_at: string | null;
  response_json: string | null;
  http_status: number | null;
};

export async function loadScanQuota(
  db: D1Database,
  owner: Pick<AuthenticatedOwner, "owner_type" | "owner_id">,
): Promise<ScanQuotaSnapshot> {
  return readQuota(db, owner);
}

export async function reserveScanQuota(
  db: D1Database,
  owner: AuthenticatedOwner,
  requestId: string,
  accessMode: "free" | "premium",
  now = new Date(),
): Promise<ScanQuotaReservation> {
  const existing = await findRequest(db, requestId);
  if (existing) {
    if (
      existing.owner_type === owner.owner_type &&
      existing.owner_id === owner.owner_id &&
      existing.session_id === owner.session_id &&
      existing.status === "reserved" &&
      Date.parse(existing.processing_expires_at ?? "") <= now.getTime()
    ) {
      const leaseExpiresAt = new Date(
        now.getTime() + PROCESSING_LEASE_MS,
      ).toISOString();
      const taken = await db
        .prepare(`
          UPDATE scan_quota_request
          SET processing_expires_at = ?, attempts = attempts + 1, updated_at = ?
          WHERE request_id = ? AND session_id = ? AND status = 'reserved'
            AND processing_expires_at <= ?
        `)
        .bind(
          leaseExpiresAt,
          now.toISOString(),
          requestId,
          owner.session_id,
          now.toISOString(),
        )
        .run();
      if (taken.meta.changes === 1) {
        return {
          status: "reserved",
          accessMode: existing.access_mode,
          requestStatus: "reserved",
          response: null,
          quota: await readQuota(db, owner),
        };
      }
    }
    return existingReservation(existing, owner, db);
  }

  const timestamp = now.toISOString();
  const leaseExpiresAt = new Date(
    now.getTime() + PROCESSING_LEASE_MS,
  ).toISOString();
  try {
    const insertStatement = db.prepare(`
        INSERT INTO scan_quota_request
          (request_id, owner_type, owner_id, session_id, access_mode, status,
           processing_expires_at, attempts, created_at, updated_at)
        SELECT ?, ?, ?, ?, ?, 'reserved', ?, 1, ?, ?
        WHERE ? = 'premium' OR (
          SELECT COUNT(*) FROM scan_quota_request
          WHERE owner_type = ? AND owner_id = ? AND access_mode = 'free'
            AND status IN ('reserved', 'consumed')
        ) < ?
      `)
      .bind(
        requestId,
        owner.owner_type,
        owner.owner_id,
        owner.session_id,
        accessMode,
        leaseExpiresAt,
        timestamp,
        timestamp,
        accessMode,
        owner.owner_type,
          owner.owner_id,
          FREE_SCAN_LIMIT,
      );
    const inserted = accessMode === "free"
      ? await runWithMutationLock(
          db,
          await mutationLockKey(
            "scan-quota",
            `${owner.owner_type}:${owner.owner_id}`,
          ),
          insertStatement,
        )
      : await insertStatement.run();
    if (inserted.meta.changes === 1) {
      return {
        status: "reserved",
        accessMode,
        requestStatus: "reserved",
        response: null,
        quota: await readQuota(db, owner),
      };
    }
  } catch (error) {
    if (!isUniqueConstraintError(error)) throw error;
  }

  const raced = await findRequest(db, requestId);
  if (raced) return existingReservation(raced, owner, db);
  return { status: "exhausted", quota: await readQuota(db, owner) };
}

export async function settleScanQuota(
  db: D1Database,
  owner: AuthenticatedOwner,
  requestId: string,
  outcome: "consumed" | "released",
  scanId: string | null,
  response: { body: unknown; status: number } | null = null,
  now = new Date(),
): Promise<ScanQuotaSnapshot | null> {
  const request = await findRequest(db, requestId);
  if (
    !request ||
    request.owner_type !== owner.owner_type ||
    request.owner_id !== owner.owner_id ||
    request.session_id !== owner.session_id
  ) {
    return null;
  }
  if (request.status !== "reserved") return readQuota(db, owner);

  const timestamp = now.toISOString();
  await db
    .prepare(`
      UPDATE scan_quota_request
      SET status = ?, scan_id = COALESCE(?, scan_id), response_json = ?,
        http_status = ?, settled_at = ?, updated_at = ?
      WHERE request_id = ? AND owner_type = ? AND owner_id = ? AND session_id = ?
        AND status = 'reserved'
    `)
    .bind(
      outcome,
      scanId,
      response === null ? null : JSON.stringify(response.body),
      response?.status ?? null,
      timestamp,
      timestamp,
      requestId,
      owner.owner_type,
      owner.owner_id,
      owner.session_id,
    )
    .run();
  return readQuota(db, owner);
}

async function findRequest(
  db: D1Database,
  requestId: string,
): Promise<RequestRow | null> {
  return db
    .prepare(`
      SELECT owner_type, owner_id, session_id, access_mode, status,
        processing_expires_at, response_json, http_status
      FROM scan_quota_request WHERE request_id = ? LIMIT 1
    `)
    .bind(requestId)
    .first<RequestRow>();
}

async function readQuota(
  db: D1Database,
  owner: Pick<AuthenticatedOwner, "owner_type" | "owner_id">,
): Promise<ScanQuotaSnapshot> {
  const row = await db
    .prepare(`
      SELECT
        SUM(CASE WHEN access_mode = 'free' AND status = 'reserved' THEN 1 ELSE 0 END)
          AS reserved_count,
        SUM(CASE WHEN access_mode = 'free' AND status = 'consumed' THEN 1 ELSE 0 END)
          AS consumed_count
      FROM scan_quota_request WHERE owner_type = ? AND owner_id = ?
    `)
    .bind(owner.owner_type, owner.owner_id)
    .first<{ reserved_count: number | null; consumed_count: number | null }>();
  const reserved = row?.reserved_count ?? 0;
  const consumed = row?.consumed_count ?? 0;
  return {
    limit: FREE_SCAN_LIMIT,
    reserved,
    consumed,
    remaining: Math.max(0, FREE_SCAN_LIMIT - reserved - consumed),
  };
}

async function existingReservation(
  row: RequestRow,
  owner: AuthenticatedOwner,
  db: D1Database,
): Promise<ScanQuotaReservation> {
  if (
    row.owner_type !== owner.owner_type ||
    row.owner_id !== owner.owner_id ||
    row.session_id !== owner.session_id
  ) {
    return { status: "conflict" };
  }
  return {
    status: "existing",
    accessMode: row.access_mode,
    requestStatus: row.status,
    response: parseResponse(row),
    quota: await readQuota(db, owner),
  };
}

function parseResponse(row: RequestRow): { body: unknown; status: number } | null {
  if (row.response_json === null || row.http_status === null) return null;
  try {
    return { body: JSON.parse(row.response_json), status: row.http_status };
  } catch {
    return null;
  }
}

function isUniqueConstraintError(error: unknown): boolean {
  return (
    error instanceof Error &&
    error.message.toLowerCase().includes("unique constraint")
  );
}
