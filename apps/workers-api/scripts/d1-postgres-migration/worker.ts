import postgres from "postgres";

import {
  loadPriceHistoryBySeries,
  loadPublishedPriceRows,
} from "../../src/data-source/postgres-price-store";
import { createPostgresDatabase } from "../../src/db/postgres-database";
import businessSchemaSql from "../../src/db/postgres/migrations/0000_business_schema.sql";
import priceDomainSql from "../../src/db/postgres/migrations/0001_price_domain.sql";
import appleInboxEnvironmentSql from "../../src/db/postgres/migrations/0002_apple_inbox_environment.sql";
import priceHistoryVisibilityGuardSql from "../../src/db/postgres/migrations/0003_price_history_visibility_guard.sql";
import priceHistoryPayloadLimitSql from "../../src/db/postgres/migrations/0004_price_history_month_payload_limit.sql";
import dropTrendingPinSql from "../../src/db/postgres/migrations/0005_drop_trending_pin.sql";
import mutationLockSql from "../../src/db/postgres/migrations/0006_mutation_lock.sql";
import billingRefundStatusSql from "../../src/db/postgres/migrations/0007_billing_refund_status.sql";
import {
  MAX_BATCH_BYTES,
  MAX_BATCH_ROWS,
  canonicalMigrationSql,
  digestRows,
  sha256Hex,
  takeBoundedRows,
  type MigrationRow,
} from "./batch";
import {
  EXPECTED_TARGET_TABLES,
  EXCLUDED_SOURCE_TABLES,
  MIGRATION_TABLES,
  OPTIONAL_SOURCE_TABLES,
  findMigrationTable,
  type MigrationTable,
} from "./tables";

type MigrationEnv = {
  SOURCE_DB: D1Database;
  HYPERDRIVE: { connectionString: string };
  MIGRATION_TOKEN?: string;
};

type CursorValue = string | number | null;
type Row = MigrationRow;
const MIGRATIONS = [
  { name: "0000_business_schema", sql: businessSchemaSql },
  { name: "0001_price_domain", sql: priceDomainSql },
  { name: "0002_apple_inbox_environment", sql: appleInboxEnvironmentSql },
  { name: "0003_price_history_visibility_guard", sql: priceHistoryVisibilityGuardSql },
  { name: "0004_price_history_month_payload_limit", sql: priceHistoryPayloadLimitSql },
  { name: "0005_drop_trending_pin", sql: dropTrendingPinSql },
  { name: "0006_mutation_lock", sql: mutationLockSql },
  { name: "0007_billing_refund_status", sql: billingRefundStatusSql },
] as const;

export default {
  async fetch(request: Request, env: MigrationEnv): Promise<Response> {
    if (!env.MIGRATION_TOKEN) {
      return json({ ok: false, code: "MIGRATION_TOKEN_MISSING" }, 503);
    }
    if (!hasValidToken(request, env.MIGRATION_TOKEN)) {
      return json({ ok: false, code: "UNAUTHORIZED" }, 401);
    }

    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }
    if (request.method === "GET" && url.pathname === "/manifest") {
      return json({
        ok: true,
        migrationTables: MIGRATION_TABLES,
        postgresMigrations: MIGRATIONS.map((migration) => migration.name),
        expectedTargetTables: EXPECTED_TARGET_TABLES,
        excludedSourceTables: EXCLUDED_SOURCE_TABLES,
        optionalSourceTables: OPTIONAL_SOURCE_TABLES,
      });
    }
    if (request.method === "GET" && url.pathname === "/source-inventory") {
      const result = await env.SOURCE_DB.prepare(
        "SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY name",
      ).all<{ name: string }>();
      return json({
        ok: true,
        tables: (result.results ?? []).map((row) => row.name),
      });
    }
    if (request.method === "POST" && url.pathname === "/source-schema") {
      return sourceSchema(request, env);
    }

    const sql = postgres(env.HYPERDRIVE.connectionString, {
      max: 1,
      fetch_types: false,
      idle_timeout: 10,
      connect_timeout: 10,
    });

    try {
      if (request.method === "POST" && url.pathname === "/schema") {
        return json(await applySchema(sql));
      }
      if (request.method === "GET" && url.pathname === "/schema") {
        return json(await inspectSchema(sql));
      }
      if (request.method === "GET" && url.pathname === "/cutover-state") {
        return json(await inspectCutoverState(sql));
      }
      if (request.method === "POST" && url.pathname === "/schema-guards") {
        return json(await verifySchemaGuards(sql, env.HYPERDRIVE.connectionString));
      }
      if (request.method === "POST" && url.pathname === "/migrate-batch") {
        return json(await migrateBatch(request, env, sql));
      }
      if (request.method === "POST" && url.pathname === "/verify-batch") {
        return json(await verifyBatch(request, env, sql));
      }
      return json({ ok: false, code: "NOT_FOUND" }, 404);
    } catch (error) {
      return json(
        {
          ok: false,
          code: "MIGRATION_FAILED",
          message: error instanceof Error ? error.message : "Unknown migration failure",
        },
        500,
      );
    } finally {
      await sql.end({ timeout: 5 });
    }
  },
};

async function applySchema(sql: ReturnType<typeof postgres>) {
  await sql.unsafe(`
    CREATE TABLE IF NOT EXISTS postgres_migration (
      name text PRIMARY KEY,
      checksum_sha256 text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);

  const applied: string[] = [];
  const alreadyApplied: string[] = [];

  for (const migration of MIGRATIONS) {
    const migrationSql = canonicalMigrationSql(migration.sql);
    const checksum = await sha256Hex(migrationSql);
    await sql.begin(async (transaction) => {
      await transaction`SELECT pg_advisory_xact_lock(hashtext('kando-postgres-schema'))`;
      const existing = await transaction`
        SELECT checksum_sha256
        FROM postgres_migration
        WHERE name = ${migration.name}
      `;
      if (existing.length > 0) {
        if (existing[0].checksum_sha256 !== checksum) {
          throw new Error(`Migration checksum mismatch: ${migration.name}`);
        }
        alreadyApplied.push(migration.name);
        return;
      }

      await transaction.unsafe(migrationSql);
      await transaction`
        INSERT INTO postgres_migration (name, checksum_sha256)
        VALUES (${migration.name}, ${checksum})
      `;
      applied.push(migration.name);
    });
  }

  return { ok: true, applied, alreadyApplied };
}

async function inspectSchema(sql: ReturnType<typeof postgres>) {
  const database = await sql`
    SELECT current_database() AS database_name,
           current_schema() AS schema_name,
           current_setting('server_version') AS server_version
  `;
  const tables = await sql`
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = current_schema()
      AND table_type = 'BASE TABLE'
    ORDER BY table_name
  `;
  const columns = await sql`
    SELECT table_name, column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_schema = current_schema()
    ORDER BY table_name, ordinal_position
  `;
  const indexes = await sql`
    SELECT tablename AS table_name, indexname AS index_name
    FROM pg_indexes
    WHERE schemaname = current_schema()
    ORDER BY tablename, indexname
  `;
  const constraints = await sql`
    SELECT relation.relname AS table_name, constraint_row.conname AS constraint_name,
           constraint_row.contype AS constraint_type,
           constraint_row.convalidated AS validated
    FROM pg_constraint AS constraint_row
    JOIN pg_class AS relation ON relation.oid = constraint_row.conrelid
    JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
    WHERE namespace.nspname = current_schema()
    ORDER BY relation.relname, constraint_row.conname
  `;
  const triggers = await sql`
    SELECT relation.relname AS table_name, trigger_row.tgname AS trigger_name
    FROM pg_trigger AS trigger_row
    JOIN pg_class AS relation ON relation.oid = trigger_row.tgrelid
    JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
    WHERE namespace.nspname = current_schema()
      AND NOT trigger_row.tgisinternal
    ORDER BY relation.relname, trigger_row.tgname
  `;
  const migrations = await sql`
    SELECT name, checksum_sha256, applied_at
    FROM postgres_migration
    ORDER BY name
  `;

  return {
    ok: true,
    database: database[0],
    tables,
    columns,
    indexes,
    constraints,
    triggers,
    migrations,
    expectedTables: EXPECTED_TARGET_TABLES,
    excludedTables: EXCLUDED_SOURCE_TABLES,
  };
}

async function inspectCutoverState(sql: ReturnType<typeof postgres>) {
  const priceTableCounts = await sql`
    SELECT 'price_source' AS table_name, COUNT(*)::bigint AS row_count FROM price_source
    UNION ALL
    SELECT 'price_series', COUNT(*)::bigint FROM price_series
    UNION ALL
    SELECT 'price_ingest_batch', COUNT(*)::bigint FROM price_ingest_batch
    UNION ALL
    SELECT 'price_current_snapshot', COUNT(*)::bigint FROM price_current_snapshot
    UNION ALL
    SELECT 'current_price_pointer', COUNT(*)::bigint FROM current_price_pointer
    UNION ALL
    SELECT 'price_history_month', COUNT(*)::bigint FROM price_history_month
    UNION ALL
    SELECT 'card_trending_snapshot', COUNT(*)::bigint FROM card_trending_snapshot
    ORDER BY table_name
  `;
  const appleInboxByEnvironment = await sql`
    SELECT environment, COUNT(*)::bigint AS row_count
    FROM apple_notification_inbox
    GROUP BY environment
    ORDER BY environment
  `;
  return { ok: true, priceTableCounts, appleInboxByEnvironment };
}

async function verifySchemaGuards(
  sql: ReturnType<typeof postgres>,
  connectionString: string,
) {
  await runRollbackProbe(sql, async (transaction) => {
    const probe = await createHistoryGuardProbe(transaction);
    await insertProbeHistory(transaction, probe.seriesId, probe.batchId, "2".repeat(64));
    await publishProbeBatch(transaction, probe.batchId, probe.scopeCode);
    await transaction.unsafe("SET CONSTRAINTS ALL IMMEDIATE");
  });

  await expectRollbackError(sql, "must be written by a validated current batch", async (transaction) => {
    const probe = await createHistoryGuardProbe(transaction);
    await insertProbeHistory(transaction, probe.seriesId, probe.batchId, "2".repeat(64));
    await publishProbeBatch(transaction, probe.batchId, probe.scopeCode);
    await transaction.unsafe("SET CONSTRAINTS ALL IMMEDIATE");
    await transaction`
      INSERT INTO price_history_month (
        series_id, month_start, points, point_count,
        first_observed_on, last_observed_on, content_checksum_sha256, last_batch_id
      ) VALUES (
        ${probe.seriesId}, DATE '2099-02-01',
        '[{"d":"2099-02-01","a":1000000}]'::jsonb, 1,
        DATE '2099-02-01', DATE '2099-02-01', ${"3".repeat(64)}, ${probe.batchId}
      )
    `;
  });

  await expectRollbackError(sql, "content changes require a new batch lineage", async (transaction) => {
    const probe = await createHistoryGuardProbe(transaction);
    await insertProbeHistory(transaction, probe.seriesId, probe.batchId, "2".repeat(64));
    await transaction`
      UPDATE price_history_month
      SET points = '[{"d":"2099-01-01","a":2000000}]'::jsonb,
          content_checksum_sha256 = ${"3".repeat(64)}
      WHERE series_id = ${probe.seriesId}
        AND month_start = DATE '2099-01-01'
    `;
    await publishProbeBatch(transaction, probe.batchId, probe.scopeCode);
    await transaction.unsafe("SET CONSTRAINTS ALL IMMEDIATE");
  });

  await expectRollbackError(sql, "ck_price_history_month_payload_bytes", async (transaction) => {
    const probe = await createHistoryGuardProbe(transaction);
    const oversizedPoints = JSON.stringify([{
      d: "2099-01-01",
      a: 1_000_000,
      padding: "x".repeat(24_576),
    }]);
    await transaction`
      INSERT INTO price_history_month (
        series_id, month_start, points, point_count,
        first_observed_on, last_observed_on, content_checksum_sha256, last_batch_id
      ) VALUES (
        ${probe.seriesId}, DATE '2099-01-01', ${oversizedPoints}::jsonb, 1,
        DATE '2099-01-01', DATE '2099-01-01', ${"4".repeat(64)}, ${probe.batchId}
      )
    `;
  });

  const database = createPostgresDatabase(connectionString);
  try {
    await loadPublishedPriceRows(database, ["schema-guard-missing-card"]);
    await loadPriceHistoryBySeries(database, [0], "2099-01-01", "2099-01-01");
  } finally {
    await database.close();
  }

  return {
    ok: true,
    checks: [
      "atomic-publish-accepted",
      "published-write-rejected",
      "same-lineage-rewrite-rejected",
      "oversized-history-rejected",
      "published-price-query-executed",
      "price-history-query-executed",
    ],
  };
}

async function createHistoryGuardProbe(transaction: postgres.TransactionSql) {
  await transaction.unsafe(`
    CREATE TABLE price_history_month_guard_probe
    PARTITION OF price_history_month
    FOR VALUES FROM (DATE '2099-01-01') TO (DATE '2100-01-01')
  `);
  await transaction`
    INSERT INTO cards_all (product_id, game_id, name)
    VALUES ('guard-probe-card', 0, 'Guard Probe')
  `;
  const [source] = await transaction<{ source_id: string }[]>`
    INSERT INTO price_source (source_code, display_name, source_kind)
    VALUES ('guard_probe', 'Guard Probe', 'derived')
    RETURNING source_id
  `;
  const [series] = await transaction<{ series_id: string }[]>`
    INSERT INTO price_series (
      source_id, source_record_id, metric_code, card_ref, currency_code, grader_code
    ) VALUES (${source.source_id}, 'guard-probe-record', 'market', 'guard-probe-card', 'USD', 'RAW')
    RETURNING series_id
  `;
  const scopeCode = "current:guard_probe";
  const [batch] = await transaction<{ batch_id: string }[]>`
    INSERT INTO price_ingest_batch (
      scope_code, source_id, business_date, idempotency_key,
      input_object_key, input_checksum_sha256, content_checksum_sha256,
      expected_series_count, loaded_series_count, distinct_series_count,
      rejected_record_count, min_observed_on, max_observed_on,
      status, validated_at
    ) VALUES (
      ${scopeCode}, ${source.source_id}, DATE '2099-01-01', 'guard-probe',
      'guard-probe.json', ${"0".repeat(64)}, ${"1".repeat(64)},
      1, 1, 1, 0, DATE '2099-01-01', DATE '2099-01-01',
      'validated', now()
    )
    RETURNING batch_id
  `;
  return {
    seriesId: series.series_id,
    batchId: batch.batch_id,
    scopeCode,
  };
}

async function insertProbeHistory(
  transaction: postgres.TransactionSql,
  seriesId: string,
  batchId: string,
  checksum: string,
) {
  await transaction`
    INSERT INTO price_history_month (
      series_id, month_start, points, point_count,
      first_observed_on, last_observed_on, content_checksum_sha256, last_batch_id
    ) VALUES (
      ${seriesId}, DATE '2099-01-01',
      '[{"d":"2099-01-01","a":1000000}]'::jsonb, 1,
      DATE '2099-01-01', DATE '2099-01-01', ${checksum}, ${batchId}
    )
  `;
}

async function publishProbeBatch(
  transaction: postgres.TransactionSql,
  batchId: string,
  scopeCode: string,
) {
  await transaction`
    UPDATE price_ingest_batch
    SET status = 'published', published_at = now(), updated_at = now()
    WHERE batch_id = ${batchId} AND status = 'validated'
  `;
  await transaction`
    INSERT INTO current_price_pointer (scope_code, batch_id, updated_by)
    VALUES (${scopeCode}, ${batchId}, 'schema-guard-probe')
  `;
}

async function runRollbackProbe(
  sql: ReturnType<typeof postgres>,
  probe: (transaction: postgres.TransactionSql) => Promise<void>,
) {
  let completed = false;
  try {
    await sql.begin(async (transaction) => {
      await probe(transaction);
      completed = true;
      throw new Error("SCHEMA_GUARD_PROBE_ROLLBACK");
    });
  } catch (error) {
    if (completed && error instanceof Error && error.message === "SCHEMA_GUARD_PROBE_ROLLBACK") {
      return;
    }
    throw error;
  }
}

async function expectRollbackError(
  sql: ReturnType<typeof postgres>,
  expectedMessage: string,
  probe: (transaction: postgres.TransactionSql) => Promise<void>,
) {
  try {
    await sql.begin(probe);
  } catch (error) {
    if (error instanceof Error && error.message.includes(expectedMessage)) return;
    throw error;
  }
  throw new Error(`Schema guard probe did not reject: ${expectedMessage}`);
}

async function sourceSchema(request: Request, env: MigrationEnv) {
  const input = await readTableInput(request);
  const table = findMigrationTable(input.table);
  if (!table) {
    return json({ ok: false, code: "UNKNOWN_TABLE" }, 400);
  }

  const identifier = quoteSqliteIdentifier(table.name);
  const cursor = quoteSqliteIdentifier(table.cursor);
  const [columns, nullCursor, count] = await Promise.all([
    env.SOURCE_DB.prepare(`PRAGMA table_info(${identifier})`).all<{ name: string }>(),
    env.SOURCE_DB.prepare(
      `SELECT COUNT(*) AS count FROM ${identifier} WHERE ${cursor} IS NULL`,
    ).first<{ count: number }>(),
    env.SOURCE_DB.prepare(`SELECT COUNT(*) AS count FROM ${identifier}`).first<{ count: number }>(),
  ]);

  return json({
    ok: true,
    table: table.name,
    expectedColumns: table.columns,
    actualColumns: (columns.results ?? []).map((column) => column.name),
    nullCursorCount: Number(nullCursor?.count ?? 0),
    rowCount: Number(count?.count ?? 0),
  });
}

async function migrateBatch(
  request: Request,
  env: MigrationEnv,
  sql: ReturnType<typeof postgres>,
) {
  const input = await readTableInput(request);
  const table = requireTable(input.table);
  const cursor = readCursor(input.cursor, table);
  const sourceRows = await selectSourceRows(env.SOURCE_DB, table, cursor);
  const bounded = takeBoundedRows(sourceRows, table);

  if (bounded.rows.length === 0) {
    return {
      ok: true,
      table: table.name,
      done: true,
      rowsRead: 0,
      rowsWritten: 0,
      nextCursor: cursor,
      payloadBytes: 0,
    };
  }

  const targetValueEntries = Object.entries(table.targetValues ?? {});
  const targetColumns = [...table.columns, ...targetValueEntries.map(([column]) => column)];
  const targetRows = bounded.rows.map((row) => Object.fromEntries([
    ...Object.entries(row),
    ...targetValueEntries,
  ]));
  const updates = targetColumns
    .filter((column) => column !== table.cursor)
    .map((column) => {
      const identifier = quotePostgresIdentifier(column);
      return `${identifier} = EXCLUDED.${identifier}`;
    })
    .join(", ");
  const conflictClause = sql.unsafe(
    `ON CONFLICT (${quotePostgresIdentifier(table.cursor)}) DO UPDATE SET ${updates}`,
  );
  const result = await sql`
    INSERT INTO ${sql(table.name)} ${sql(targetRows, targetColumns)}
    ${conflictClause}
  `;
  const nextCursor = bounded.rows.at(-1)?.[table.cursor];
  assertCursorValue(nextCursor, table);

  return {
    ok: true,
    table: table.name,
    done: false,
    rowsRead: bounded.rows.length,
    rowsWritten: result.count,
    nextCursor,
    payloadBytes: bounded.payloadBytes,
  };
}

async function verifyBatch(
  request: Request,
  env: MigrationEnv,
  sql: ReturnType<typeof postgres>,
) {
  const input = await readTableInput(request);
  const table = requireTable(input.table);
  const cursor = readCursor(input.cursor, table);
  const sourceRows = takeBoundedRows(
    await selectSourceRows(env.SOURCE_DB, table, cursor),
    table,
  ).rows;
  const targetRows = await selectTargetRows(sql, table, cursor, Math.max(sourceRows.length, 1));

  if (sourceRows.length === 0) {
    return {
      ok: targetRows.length === 0,
      table: table.name,
      done: true,
      sourceRows: 0,
      targetRows: targetRows.length,
      sourceDigest: await digestRows([], table),
      targetDigest: await digestRows(targetRows, table),
      nextCursor: cursor,
    };
  }

  const comparableTargetRows = targetRows.slice(0, sourceRows.length);
  const sourceDigest = await digestRows(sourceRows, table);
  const targetDigest = await digestRows(comparableTargetRows, table);
  const nextCursor = sourceRows.at(-1)?.[table.cursor];
  assertCursorValue(nextCursor, table);

  return {
    ok: sourceRows.length === targetRows.length && sourceDigest === targetDigest,
    table: table.name,
    done: false,
    sourceRows: sourceRows.length,
    targetRows: targetRows.length,
    sourceDigest,
    targetDigest,
    nextCursor,
  };
}

async function selectSourceRows(
  db: D1Database,
  table: MigrationTable,
  cursor: CursorValue,
): Promise<Row[]> {
  const tableIdentifier = quoteSqliteIdentifier(table.name);
  const columns = table.columns.map(quoteSqliteIdentifier).join(", ");
  const cursorIdentifier = quoteSqliteIdentifier(table.cursor);
  const collate = table.cursorType === "text" ? " COLLATE BINARY" : "";
  const where = cursor === null ? "" : `WHERE ${cursorIdentifier}${collate} > ?`;
  const rowOverhead = table.columns.reduce(
    (total, column) => total + new TextEncoder().encode(column).byteLength + 8,
    32,
  );
  const encodedBytes = `length(CAST(json_array(${columns}) AS BLOB)) + ${rowOverhead}`;
  const statement = db.prepare(
    `WITH candidate_rows AS (
       SELECT ${columns}, ${encodedBytes} AS __row_bytes
       FROM ${tableIdentifier} ${where}
       ORDER BY ${cursorIdentifier}${collate}
       LIMIT ?
     ), bounded_rows AS (
       SELECT *, SUM(__row_bytes) OVER (
         ORDER BY ${cursorIdentifier}${collate}
       ) AS __cumulative_bytes
       FROM candidate_rows
     )
     SELECT ${columns}
     FROM bounded_rows
     WHERE __cumulative_bytes <= ?
     ORDER BY ${cursorIdentifier}${collate}`,
  );
  const result = cursor === null
    ? await statement.bind(MAX_BATCH_ROWS, MAX_BATCH_BYTES).all<Row>()
    : await statement.bind(cursor, MAX_BATCH_ROWS, MAX_BATCH_BYTES).all<Row>();
  const rows = result.results ?? [];
  if (rows.length > 0) return rows;

  const nextRowStatement = db.prepare(
    `SELECT ${cursorIdentifier} AS cursor_value, ${encodedBytes} AS encoded_bytes
     FROM ${tableIdentifier} ${where}
     ORDER BY ${cursorIdentifier}${collate}
     LIMIT 1`,
  );
  const nextRow = cursor === null
    ? await nextRowStatement.first<{ cursor_value: string | number; encoded_bytes: number }>()
    : await nextRowStatement.bind(cursor).first<{
        cursor_value: string | number;
        encoded_bytes: number;
      }>();
  if (nextRow && Number(nextRow.encoded_bytes) > MAX_BATCH_BYTES) {
    throw new Error(`Source row exceeds ${MAX_BATCH_BYTES} byte limit in ${table.name}`);
  }
  return [];
}

async function selectTargetRows(
  sql: ReturnType<typeof postgres>,
  table: MigrationTable,
  cursor: CursorValue,
  limit: number,
): Promise<Row[]> {
  const columns = sql([...table.columns]);
  const tableIdentifier = sql(table.name);
  const cursorIdentifier = sql(table.cursor);
  const rows = cursor === null
    ? table.cursorType === "text"
      ? await sql`
          SELECT ${columns} FROM ${tableIdentifier}
          ORDER BY ${cursorIdentifier} COLLATE "C" LIMIT ${limit}
        `
      : await sql`
          SELECT ${columns} FROM ${tableIdentifier}
          ORDER BY ${cursorIdentifier} LIMIT ${limit}
        `
    : table.cursorType === "text"
      ? await sql`
          SELECT ${columns} FROM ${tableIdentifier}
          WHERE ${cursorIdentifier} COLLATE "C" > ${cursor}
          ORDER BY ${cursorIdentifier} COLLATE "C" LIMIT ${limit}
        `
      : await sql`
          SELECT ${columns} FROM ${tableIdentifier}
          WHERE ${cursorIdentifier} > ${cursor}
          ORDER BY ${cursorIdentifier} LIMIT ${limit}
        `;
  return Array.from(rows) as Row[];
}

async function readTableInput(request: Request): Promise<{ table?: unknown; cursor?: unknown }> {
  const value: unknown = await request.json();
  return value !== null && typeof value === "object"
    ? value as { table?: unknown; cursor?: unknown }
    : {};
}

function requireTable(name: unknown) {
  const table = findMigrationTable(name);
  if (!table) {
    throw new Error("Unknown migration table");
  }
  return table;
}

function readCursor(value: unknown, table: MigrationTable): CursorValue {
  if (value === null || value === undefined) {
    return null;
  }
  assertCursorValue(value, table);
  return value;
}

function assertCursorValue(value: unknown, table: MigrationTable): asserts value is string | number {
  const expectedType = table.cursorType === "text" ? "string" : "number";
  if (typeof value !== expectedType || (typeof value === "number" && !Number.isFinite(value))) {
    throw new Error(`Invalid cursor for ${table.name}`);
  }
}

function quoteSqliteIdentifier(value: string) {
  return `"${value.replaceAll('"', '""')}"`;
}

function quotePostgresIdentifier(value: string) {
  return `"${value.replaceAll('"', '""')}"`;
}

function hasValidToken(request: Request, expected: string) {
  const actual = request.headers.get("authorization") ?? "";
  return actual === `Bearer ${expected}`;
}

function json(value: unknown, status = 200) {
  return Response.json(value, {
    status,
    headers: { "cache-control": "no-store" },
  });
}
