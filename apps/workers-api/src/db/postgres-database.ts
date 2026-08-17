import postgres from "postgres";

import type {
  Database,
  DatabaseMeta,
  DatabaseResult,
  DatabaseStatement,
} from "./database";

type SqlExecutor = Pick<postgres.Sql, "unsafe">;

type QueryExecution<T> = {
  rows: T[];
  columns: string[];
  meta: DatabaseMeta;
};

const POSTGRES_BIGINT_OID = 20;
const POSTGRES_DATE_OID = 1082;
const POSTGRES_NUMERIC_OID = 1700;

export function createPostgresDatabase(connectionString: string): PostgresDatabase {
  const sql = postgres(connectionString, {
    max: 5,
    fetch_types: false,
    idle_timeout: 10,
    connect_timeout: 10,
    transform: {
      value: {
        from: normalizePostgresValue,
      },
    },
  });
  return new PostgresDatabase(sql);
}

export class PostgresDatabase implements Database {
  constructor(private readonly sql: postgres.Sql) {}

  prepare(query: string): DatabaseStatement {
    return new PostgresStatement(this, query, []);
  }

  async batch<T = unknown>(statements: D1PreparedStatement[]): Promise<DatabaseResult<T>[]> {
    return this.sql.begin(async (transaction) => {
      const results: DatabaseResult<T>[] = [];
      for (const statement of statements) {
        if (!(statement instanceof PostgresStatement) || statement.database !== this) {
          throw new Error("PostgreSQL batch received a statement from another database");
        }
        results.push(await statement.execute<T>(transaction));
      }
      return results;
    });
  }

  async close(): Promise<void> {
    await this.sql.end({ timeout: 5 });
  }

  async exec(query: string): Promise<D1ExecResult> {
    const result = await this.prepare(query).run();
    return { count: result.meta.changes, duration: result.meta.duration };
  }

  withSession(): D1DatabaseSession {
    throw new Error("PostgreSQL databases do not support D1 withSession(); use batch() transactions");
  }

  async dump(): Promise<ArrayBuffer> {
    throw new Error("PostgreSQL databases do not support D1 dump()");
  }

  executor(): SqlExecutor {
    return this.sql;
  }
}

class PostgresStatement implements DatabaseStatement {
  constructor(
    readonly database: PostgresDatabase,
    private readonly query: string,
    private readonly values: readonly unknown[],
  ) {}

  bind(...values: unknown[]): DatabaseStatement {
    return new PostgresStatement(this.database, this.query, values);
  }

  async first<T = unknown>(columnName: string): Promise<T | null>;
  async first<T = Record<string, unknown>>(): Promise<T | null>;
  async first<T = Record<string, unknown>>(columnName?: string): Promise<T | null> {
    const execution = await this.executeQuery<T>();
    const row = execution.rows[0];
    if (row === undefined) return null;
    if (columnName === undefined) return row;
    if (row === null || typeof row !== "object" || !(columnName in row)) return null;
    return (row as Record<string, unknown>)[columnName] as T;
  }

  async run<T = Record<string, unknown>>(): Promise<DatabaseResult<T>> {
    return this.execute<T>();
  }

  async all<T = Record<string, unknown>>(): Promise<DatabaseResult<T>> {
    return this.execute<T>();
  }

  async raw<T = unknown[]>(options: { columnNames: true }): Promise<[string[], ...T[]]>;
  async raw<T = unknown[]>(options?: { columnNames?: false }): Promise<T[]>;
  async raw<T = unknown[]>(options?: { columnNames?: boolean }): Promise<T[] | [string[], ...T[]]> {
    const execution = await this.executeQuery<Record<string, unknown>>();
    const values = execution.rows.map((row) => execution.columns.map((column) => row[column]) as T);
    return options?.columnNames
      ? [execution.columns, ...values]
      : values;
  }

  async execute<T>(executor?: SqlExecutor): Promise<DatabaseResult<T>> {
    const execution = await this.executeQuery<T>(executor);
    return {
      success: true,
      results: execution.rows,
      meta: execution.meta,
    };
  }

  private async executeQuery<T>(executor?: SqlExecutor): Promise<QueryExecution<T>> {
    const converted = convertQuestionMarkPlaceholders(this.query);
    if (converted.count !== this.values.length) {
      throw new Error(
        `SQL binding count mismatch: expected ${converted.count}, received ${this.values.length}`,
      );
    }
    const startedAt = performance.now();
    const result = await (executor ?? this.database.executor()).unsafe<Record<string, unknown>[]>(
      converted.sql,
      this.values.map(normalizeBinding) as never[],
    );
    const duration = performance.now() - startedAt;
    const rows = Array.from(result) as T[];
    const command = result.command?.toUpperCase() ?? "";
    const changedDb = !["SELECT", "SHOW", "EXPLAIN"].includes(command);
    const changes = changedDb ? result.count ?? rows.length : 0;
    return {
      rows,
      columns: result.columns.map((column) => column.name),
      meta: {
        duration,
        size_after: 0,
        rows_read: changedDb ? 0 : rows.length,
        rows_written: changedDb ? changes : 0,
        last_row_id: 0,
        changed_db: changedDb,
        changes,
      },
    };
  }

}

export function normalizePostgresValue(value: unknown, column?: { type: number }): unknown {
  if (value instanceof Date) {
    const iso = value.toISOString();
    return column?.type === POSTGRES_DATE_OID ? iso.slice(0, 10) : iso;
  }
  if (column?.type === POSTGRES_BIGINT_OID) {
    const parsed = typeof value === "bigint" ? Number(value) : Number(String(value));
    if (!Number.isSafeInteger(parsed)) {
      throw new Error(`PostgreSQL bigint exceeds JavaScript safe integer range: ${String(value)}`);
    }
    return parsed;
  }
  if (column?.type === POSTGRES_NUMERIC_OID) {
    const parsed = Number(String(value));
    if (!Number.isFinite(parsed)) {
      throw new Error(`PostgreSQL numeric value is not finite: ${String(value)}`);
    }
    return parsed;
  }
  return value;
}

export function convertQuestionMarkPlaceholders(query: string): { sql: string; count: number } {
  let result = "";
  let count = 0;
  let index = 0;
  let state: "normal" | "single" | "double" | "line-comment" | "block-comment" = "normal";

  while (index < query.length) {
    const current = query[index]!;
    const next = query[index + 1];

    if (state === "normal") {
      if (current === "'") state = "single";
      else if (current === '"') state = "double";
      else if (current === "-" && next === "-") state = "line-comment";
      else if (current === "/" && next === "*") state = "block-comment";
      else if (current === "?") {
        count += 1;
        result += `$${count}`;
        index += 1;
        continue;
      }
    } else if (state === "single" && current === "'") {
      if (next === "'") {
        result += current + next;
        index += 2;
        continue;
      }
      state = "normal";
    } else if (state === "double" && current === '"') {
      if (next === '"') {
        result += current + next;
        index += 2;
        continue;
      }
      state = "normal";
    } else if (state === "line-comment" && (current === "\n" || current === "\r")) {
      state = "normal";
    } else if (state === "block-comment" && current === "*" && next === "/") {
      result += current + next;
      index += 2;
      state = "normal";
      continue;
    }

    result += current;
    index += 1;
  }

  if (state === "single" || state === "double" || state === "block-comment") {
    throw new Error("SQL contains an unterminated quote or block comment");
  }
  return { sql: result, count };
}

function normalizeBinding(value: unknown): unknown {
  if (value === undefined) throw new Error("SQL bindings cannot contain undefined");
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (typeof value === "bigint") return value.toString();
  return value;
}

export async function runWithDatabaseLifecycle<T>(
  database: Pick<PostgresDatabase, "close">,
  context: ExecutionContext,
  handler: (context: ExecutionContext) => Promise<T>,
): Promise<T> {
  let handlerSettled = false;
  let activeTasks = 0;
  let closePromise: Promise<void> | null = null;

  const closeWhenIdle = () => {
    if (!handlerSettled || activeTasks !== 0 || closePromise) return;
    closePromise = database.close();
    context.waitUntil(closePromise);
  };

  const trackedContext = new Proxy(context, {
    get(target, property, receiver) {
      if (property !== "waitUntil") {
        const value = Reflect.get(target, property, receiver);
        return typeof value === "function" ? value.bind(target) : value;
      }
      return (promise: Promise<unknown>) => {
        let registered = false;
        const tracked = Promise.resolve(promise).finally(() => {
          if (!registered) return;
          activeTasks -= 1;
          closeWhenIdle();
        });
        target.waitUntil(tracked);
        registered = true;
        activeTasks += 1;
      };
    },
  });

  try {
    return await handler(trackedContext);
  } finally {
    handlerSettled = true;
    closeWhenIdle();
  }
}
