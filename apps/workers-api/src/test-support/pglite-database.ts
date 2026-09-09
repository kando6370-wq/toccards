import { PGlite, type PGliteInterface, type Results } from "@electric-sql/pglite";
import type {
  Database,
  DatabaseMeta,
  DatabaseResult,
  DatabaseStatement,
} from "../db/database";
import {
  convertQuestionMarkPlaceholders,
  normalizePostgresValue,
} from "../db/postgres-database";

type QueryExecutor = Pick<PGliteInterface, "query">;

export class PGliteDatabase implements Database {
  private constructor(private readonly client: PGlite) {}

  static async create(): Promise<PGliteDatabase> {
    return new PGliteDatabase(await PGlite.create({ dataDir: "memory://" }));
  }

  prepare(query: string): DatabaseStatement {
    return new PGliteStatement(this, query, []);
  }

  async batch<T = unknown>(
    statements: D1PreparedStatement[],
  ): Promise<DatabaseResult<T>[]> {
    return this.client.transaction(async (transaction) => {
      const results: DatabaseResult<T>[] = [];
      for (const statement of statements) {
        if (!(statement instanceof PGliteStatement) || statement.database !== this) {
          throw new Error("PGlite batch received a statement from another database");
        }
        results.push(await statement.execute<T>(transaction));
      }
      return results;
    });
  }

  async exec(query: string): Promise<D1ExecResult> {
    const startedAt = performance.now();
    const results = await this.client.exec(query);
    return { count: results.length, duration: performance.now() - startedAt };
  }

  withSession(): D1DatabaseSession {
    throw new Error("PGlite tests do not support D1 sessions");
  }

  async dump(): Promise<ArrayBuffer> {
    throw new Error("PGlite tests do not support D1 dumps");
  }

  query<T>(query: string, values: unknown[] = []): Promise<Results<T>> {
    return this.client.query<T>(query, values);
  }

  close(): Promise<void> {
    return this.client.close();
  }
}

class PGliteStatement implements DatabaseStatement {
  constructor(
    readonly database: PGliteDatabase,
    private readonly query: string,
    private readonly values: readonly unknown[],
  ) {}

  bind(...values: unknown[]): DatabaseStatement {
    return new PGliteStatement(this.database, this.query, values);
  }

  async first<T = unknown>(columnName: string): Promise<T | null>;
  async first<T = Record<string, unknown>>(): Promise<T | null>;
  async first<T = Record<string, unknown>>(
    columnName?: string,
  ): Promise<T | null> {
    const result = await this.executeQuery<T>();
    const row = result.rows[0];
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
  async raw<T = unknown[]>(
    options?: { columnNames?: boolean },
  ): Promise<T[] | [string[], ...T[]]> {
    const result = await this.executeQuery<Record<string, unknown>>();
    const columns = result.columns;
    const values = result.rows.map(
      (row) => columns.map((column) => row[column]) as T,
    );
    return options?.columnNames ? [columns, ...values] : values;
  }

  async execute<T>(executor?: QueryExecutor): Promise<DatabaseResult<T>> {
    const result = await this.executeQuery<T>(executor);
    return {
      success: true,
      results: result.rows,
      meta: result.meta,
    };
  }

  private async executeQuery<T>(executor?: QueryExecutor): Promise<{
    rows: T[];
    columns: string[];
    meta: DatabaseMeta;
  }> {
    const converted = convertQuestionMarkPlaceholders(this.query);
    if (converted.count !== this.values.length) {
      throw new Error(
        `SQL binding count mismatch: expected ${converted.count}, received ${this.values.length}`,
      );
    }
    const startedAt = performance.now();
    const result = await (executor ?? this.database).query<Record<string, unknown>>(
      converted.sql,
      [...this.values],
    );
    const duration = performance.now() - startedAt;
    const rows = normalizeRows(result) as T[];
    const command = result.command?.toUpperCase() ?? "";
    const changedDb = !["SELECT", "SHOW", "EXPLAIN"].includes(command);
    const changes = changedDb
      ? result.affectedRows ?? result.rowCount ?? rows.length
      : 0;
    return {
      rows,
      columns: result.fields.map((field) => field.name),
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

function normalizeRows(result: Results<Record<string, unknown>>): Record<string, unknown>[] {
  return result.rows.map((row) => Object.fromEntries(
    result.fields.map((field) => [
      field.name,
      normalizePostgresValue(row[field.name], { type: field.dataTypeID }),
    ]),
  ));
}
