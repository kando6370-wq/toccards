import postgres from "postgres";

import businessSchemaSql from "../../src/db/postgres/migrations/0000_business_schema.sql";
import priceDomainSql from "../../src/db/postgres/migrations/0001_price_domain.sql";
import {
  MAX_BATCH_BYTES,
  MAX_BATCH_ROWS,
  digestRows,
  sha256Hex,
  takeBoundedRows,
  type MigrationRow,
} from "./batch";
import {
  EXPECTED_TARGET_TABLES,
  EXCLUDED_SOURCE_TABLES,
  MIGRATION_TABLES,
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
        expectedTargetTables: EXPECTED_TARGET_TABLES,
        excludedSourceTables: EXCLUDED_SOURCE_TABLES,
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
    const checksum = await sha256Hex(migration.sql);
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

      await transaction.unsafe(migration.sql);
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

  const updates = table.columns
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
    INSERT INTO ${sql(table.name)} ${sql(bounded.rows, [...table.columns])}
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
