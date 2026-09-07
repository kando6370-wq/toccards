import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

import {
  MAX_BATCH_BYTES,
  canonicalRow,
  canonicalMigrationSql,
  encodedRowBytes,
  sha256Hex,
  takeBoundedRows,
} from "./batch";
import {
  EXPECTED_TARGET_TABLES,
  EXCLUDED_SOURCE_TABLES,
  MIGRATION_TABLES,
  OPTIONAL_SOURCE_TABLES,
  type MigrationTable,
} from "./tables";

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
const dropTrendingPinSql = readFileSync(
  new URL("../../src/db/postgres/migrations/0005_drop_trending_pin.sql", import.meta.url),
  "utf8",
);
const billingRefundStatusSql = readFileSync(
  new URL("../../src/db/postgres/migrations/0007_billing_refund_status.sql", import.meta.url),
  "utf8",
);
const scanRecordEnvironmentSql = readFileSync(
  new URL("../../src/db/postgres/migrations/0010_scan_record_environment.sql", import.meta.url),
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

    expect(inbox?.targetValues).toEqual({
      environment: "Sandbox",
      app_bundle_id: "com.kando.kandoApp.beta",
    });
    expect(appleInboxEnvironmentSql).toContain("UNIQUE (environment, payload_sha256)");
    expect(appleInboxEnvironmentSql).toContain("WHERE environment IS NULL");
  });

  it("guards monthly history writes at commit because unvalidated batches must never replace visible history", () => {
    expect(priceHistoryVisibilityGuardSql).toContain("batch.status = 'published'");
    expect(priceHistoryVisibilityGuardSql).toContain("DEFERRABLE INITIALLY DEFERRED");
    expect(priceHistoryVisibilityGuardSql).toContain("batch.source_id = series.source_id");
    expect(priceHistoryVisibilityGuardSql).toContain("pointer.batch_id = batch.batch_id");
    expect(priceHistoryVisibilityGuardSql).toContain("pointer.scope_code LIKE 'current:%'");
    expect(priceHistoryVisibilityGuardSql).toMatch(
      /AFTER INSERT OR UPDATE\r?\nON price_history_month/,
    );
    expect(priceHistoryVisibilityGuardSql).not.toContain("UPDATE OF series_id, last_batch_id");
    expect(priceHistoryVisibilityGuardSql).toContain("content changes require a new batch lineage");
    expect(priceHistoryVisibilityGuardSql).toMatch(
      /BEFORE INSERT OR UPDATE\r?\nON price_history_month/,
    );
    expect(priceHistoryVisibilityGuardSql).toContain("batch.status = 'validated'");
    expect(priceHistoryVisibilityGuardSql).toContain("must be written by a validated current batch");
  });

  it("fails schema verification when shared-database isolation guards are missing", () => {
    expect(migrationRunnerSource).toContain("trg_price_history_month_staged");
    expect(migrationRunnerSource).toContain("trg_price_history_month_published");
    expect(migrationRunnerSource).toContain(
      "uq_apple_notification_inbox_app_environment_payload",
    );
    expect(migrationRunnerSource).toContain("idx_apple_notification_inbox_processing");
    expect(migrationRunnerSource).toContain("ck_scan_record_environment");
    expect(migrationRunnerSource).toContain("idx_scan_record_environment_created_at");
    expect(migrationRunnerSource).toContain("ck_price_history_month_payload_bytes");
    expect(migrationRunnerSource).toContain("manifest.postgresMigrations");
    expect(migrationRunnerSource).not.toContain("inventory.migrations.length === 6");
    expect(migrationRunnerSource).toContain("--verify-cutover-state");
    expect(migrationRunnerSource).toContain("/cutover-state");
    expect(migrationWorkerSource).toContain("priceTableCounts");
    expect(migrationWorkerSource).toContain("appleInboxByEnvironment");
  });

  it("labels dev scan records and guards the persisted environment because Admin shares PostgreSQL", () => {
    const scans = MIGRATION_TABLES.find((candidate) => candidate.name === "scan_record");

    expect(scans?.targetValues).toEqual({ environment: "development" });
    expect(scanRecordEnvironmentSql).toContain("SET environment = 'development'");
    expect(scanRecordEnvironmentSql).toContain(
      "ALTER COLUMN environment SET DEFAULT 'development'",
    );
    expect(scanRecordEnvironmentSql).toContain(
      "CHECK (environment IN ('development', 'production'))",
    );
    expect(scanRecordEnvironmentSql).toContain("idx_scan_record_environment_created_at");
    expect(migrationWorkerSource).toContain('name: "0010_scan_record_environment"');
    expect(migrationWorkerSource).toContain("scanRecordsByEnvironment");
    expect(migrationRunnerSource).toContain("scan_record 行数与 dev D1 不一致");
  });

  it("classifies mutation locks as optional source infrastructure and required target schema", () => {
    expect(MIGRATION_TABLES.some((candidate) => candidate.name === "mutation_lock")).toBe(false);
    expect(OPTIONAL_SOURCE_TABLES).toContain("mutation_lock");
    expect(EXPECTED_TARGET_TABLES).toContain("mutation_lock");
    expect(migrationWorkerSource).toContain('name: "0006_mutation_lock"');
    expect(migrationWorkerSource).toContain("postgresMigrations: MIGRATIONS.map");
    expect(migrationRunnerSource).toContain("...manifest.optionalSourceTables");
  });

  it("appends refund provenance to PostgreSQL so REFUND_REVERSED can restore the prior order status", () => {
    expect(billingRefundStatusSql).toContain("ADD COLUMN business_status_before_refund text");
    expect(migrationWorkerSource).toContain('name: "0007_billing_refund_status"');
  });

  it("normalizes every newline style before checksum and execution because checkout platform is not migration identity", async () => {
    const lf = "CREATE TABLE example (\n  id text\n);\n";
    const crlf = lf.replaceAll("\n", "\r\n");
    const cr = lf.replaceAll("\n", "\r");

    expect(canonicalMigrationSql(crlf)).toBe(lf);
    expect(canonicalMigrationSql(cr)).toBe(lf);
    await expect(Promise.all([
      sha256Hex(canonicalMigrationSql(lf)),
      sha256Hex(canonicalMigrationSql(crlf)),
      sha256Hex(canonicalMigrationSql(cr)),
    ])).resolves.toEqual([
      await sha256Hex(lf),
      await sha256Hex(lf),
      await sha256Hex(lf),
    ]);
    expect(migrationWorkerSource).toContain(
      "const migrationSql = canonicalMigrationSql(migration.sql)",
    );
    expect(migrationWorkerSource).toContain("sha256Hex(migrationSql)");
    expect(migrationWorkerSource).toContain("transaction.unsafe(migrationSql)");
  });

  it("keeps the retired Trending Pin table out of PostgreSQL because obsolete D1 data must not recreate it", () => {
    expect(MIGRATION_TABLES.some((candidate) => candidate.name === "trending_pin")).toBe(false);
    expect(EXPECTED_TARGET_TABLES).not.toContain("trending_pin");
    expect(EXCLUDED_SOURCE_TABLES).toContain("trending_pin");
    expect(dropTrendingPinSql.trim()).toBe("DROP TABLE trending_pin;");
    expect(dropTrendingPinSql).not.toContain("CASCADE");
    expect(migrationWorkerSource).toContain('name: "0005_drop_trending_pin"');
  });

  it("rejects cutover-state checks in schema-only mode because cutover proof requires all business digests", () => {
    expect(migrationRunnerSource).toContain(
      'verifyCutoverStateRequested && mode === "schema-only"',
    );
    expect(migrationRunnerSource).toContain(
      "--verify-cutover-state 必须与完整 --verify-only 或正式迁移一起执行。",
    );
    expect(migrationRunnerSource).toContain(
      "verifyCutoverStateRequested && !sourceWriteFrozenConfirmed",
    );
    expect(migrationRunnerSource).toContain(
      "--verify-cutover-state 前必须确认 dev D1 写入已冻结。",
    );
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
