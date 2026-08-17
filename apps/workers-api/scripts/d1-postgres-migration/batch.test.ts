import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

import {
  MAX_BATCH_BYTES,
  canonicalRow,
  encodedRowBytes,
  takeBoundedRows,
} from "./batch";
import { MIGRATION_TABLES, type MigrationTable } from "./tables";

const appleInboxEnvironmentSql = readFileSync(
  new URL("../../src/db/postgres/migrations/0002_apple_inbox_environment.sql", import.meta.url),
  "utf8",
);
const priceHistoryVisibilityGuardSql = readFileSync(
  new URL("../../src/db/postgres/migrations/0003_price_history_visibility_guard.sql", import.meta.url),
  "utf8",
);
const priceHistoryPayloadLimitSql = readFileSync(
  new URL("../../src/db/postgres/migrations/0004_price_history_month_payload_limit.sql", import.meta.url),
  "utf8",
);
const migrationRunnerSource = readFileSync(new URL("./run.mjs", import.meta.url), "utf8");
const migrationWorkerSource = readFileSync(new URL("./worker.ts", import.meta.url), "utf8");

const table: MigrationTable = {
  name: "example",
  cursor: "id",
  cursorType: "text",
  columns: ["id", "amount_micros", "payload"],
  bigintColumns: ["amount_micros"],
};

describe("D1 to PostgreSQL migration batches", () => {
  it("normalizes bigint fields before source and target digests are compared", () => {
    expect(canonicalRow({ id: "1", amount_micros: 42, payload: null }, table))
      .toBe('["1","42",null]');
  });

  it("keeps only the largest prefix below the Hyperdrive payload cap", () => {
    const first = { id: "1", amount_micros: 1, payload: "a".repeat(300_000) };
    const second = { id: "2", amount_micros: 2, payload: "b".repeat(300_000) };

    const result = takeBoundedRows([first, second], table);

    expect(result.rows).toEqual([first]);
    expect(result.payloadBytes).toBe(encodedRowBytes(first, table));
    expect(result.payloadBytes).toBeLessThanOrEqual(MAX_BATCH_BYTES);
  });

  it("fails loudly instead of sending one oversized row", () => {
    const oversized = {
      id: "1",
      amount_micros: 1,
      payload: "x".repeat(MAX_BATCH_BYTES),
    };

    expect(() => takeBoundedRows([oversized], table))
      .toThrow(`Source row exceeds ${MAX_BATCH_BYTES} byte limit in example`);
  });

  it("labels migrated dev inbox rows as Sandbox because the shared PostgreSQL queue requires durable ownership", () => {
    const inbox = MIGRATION_TABLES.find((candidate) =>
      candidate.name === "apple_notification_inbox"
    );

    expect(inbox?.targetValues).toEqual({ environment: "Sandbox" });
    expect(appleInboxEnvironmentSql).toContain("UNIQUE (environment, payload_sha256)");
    expect(appleInboxEnvironmentSql).toContain("WHERE environment IS NULL");
  });

  it("guards monthly history writes at commit because unvalidated batches must never replace visible history", () => {
    expect(priceHistoryVisibilityGuardSql).toContain("batch.status = 'published'");
    expect(priceHistoryVisibilityGuardSql).toContain("DEFERRABLE INITIALLY DEFERRED");
    expect(priceHistoryVisibilityGuardSql).toContain("batch.source_id = series.source_id");
    expect(priceHistoryVisibilityGuardSql).toContain("pointer.batch_id = batch.batch_id");
    expect(priceHistoryVisibilityGuardSql).toContain("pointer.scope_code LIKE 'current:%'");
    expect(priceHistoryVisibilityGuardSql).toContain("AFTER INSERT OR UPDATE\nON price_history_month");
    expect(priceHistoryVisibilityGuardSql).not.toContain("UPDATE OF series_id, last_batch_id");
    expect(priceHistoryVisibilityGuardSql).toContain("content changes require a new batch lineage");
    expect(priceHistoryVisibilityGuardSql).toContain("BEFORE INSERT OR UPDATE\nON price_history_month");
    expect(priceHistoryVisibilityGuardSql).toContain("batch.status = 'validated'");
    expect(priceHistoryVisibilityGuardSql).toContain("must be written by a validated current batch");
  });

  it("fails schema verification when shared-database isolation guards are missing", () => {
    expect(migrationRunnerSource).toContain("trg_price_history_month_staged");
    expect(migrationRunnerSource).toContain("trg_price_history_month_published");
    expect(migrationRunnerSource).toContain("uq_apple_notification_inbox_environment_payload");
    expect(migrationRunnerSource).toContain("idx_apple_notification_inbox_processing");
    expect(migrationRunnerSource).toContain("ck_price_history_month_payload_bytes");
    expect(migrationRunnerSource).toContain("inventory.migrations.length === 5");
  });

  it("caps monthly JSON so 1600 history rows leave headroom below Hyperdrive's 50 MB response limit", () => {
    const bytes = Number(priceHistoryPayloadLimitSql.match(/<= (\d+)/)?.[1]);

    expect(bytes).toBe(24 * 1024);
    expect(bytes * 1600).toBeLessThan(40 * 1024 * 1024);
  });

  it("probes PostgreSQL guard behavior in rollback-only transactions before migration", () => {
    expect(migrationRunnerSource).toContain("/schema-guards");
    expect(migrationWorkerSource).toContain("SCHEMA_GUARD_PROBE_ROLLBACK");
    expect(migrationWorkerSource).toContain("published-write-rejected");
    expect(migrationWorkerSource).toContain("same-lineage-rewrite-rejected");
    expect(migrationWorkerSource).toContain("oversized-history-rejected");
    expect(migrationWorkerSource).toContain("loadPublishedPriceRows(database");
    expect(migrationWorkerSource).toContain("loadPriceHistoryBySeries(database");
  });
});
