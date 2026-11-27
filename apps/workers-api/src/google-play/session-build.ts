import type { AndroidPlayBuild } from "../auth/android-integrity";
import type { Database, DatabaseStatement } from "../db/database";

// Keep the original conditional session INSERT and its affected-row count in the same transaction.
export function insertPlatformSession(
  db: Database, build: AndroidPlayBuild | undefined, insertSql: string, ...values: unknown[]
): DatabaseStatement {
  if (!build) return db.prepare(insertSql).bind(...values);
  return db.prepare(`WITH issued AS (${insertSql} RETURNING id, platform)
    INSERT INTO google_play_session_build (session_id, package_name, certificate_digest, version_code, verified_at)
    SELECT id, ?, ?, ?, ? FROM issued WHERE platform = 'android'`)
    .bind(...values, build.package_name, build.certificate_digest, build.version_code, build.verified_at);
}
