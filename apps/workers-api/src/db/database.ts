export type DatabaseMeta = D1Meta & Record<string, unknown>;
export type DatabaseResult<T = unknown> = D1Result<T>;

export interface DatabaseStatement extends D1PreparedStatement {
  bind(...values: unknown[]): DatabaseStatement;
  run<T = Record<string, unknown>>(): Promise<DatabaseResult<T>>;
  all<T = Record<string, unknown>>(): Promise<DatabaseResult<T>>;
}

export interface Database extends D1Database {
  prepare(query: string): DatabaseStatement;
}
