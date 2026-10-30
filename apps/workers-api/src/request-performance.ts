import { AsyncLocalStorage } from "node:async_hooks";
import { createHash } from "node:crypto";

type SqlMetrics = {
  count: number;
  duration_ms: number;
  max_duration_ms: number;
  returned_rows: number;
  errors: number;
};
type CacheLayer = "kv" | "cache_api";
type CacheResult = "hit" | "miss" | "error";

const activeRequest = new AsyncLocalStorage<RequestPerformance>();
const MAX_SQL_FINGERPRINTS = 20;

export class RequestPerformance {
  private completed = false;
  private readonly statements = new Map<string, SqlMetrics>();
  private readonly sql = emptySqlMetrics();
  private overflowCount = 0;
  private readonly cache = {
    kv: { hit: 0, miss: 0, error: 0 },
    cache_api: { hit: 0, miss: 0, error: 0 },
  };

  async run<T>(handler: () => Promise<T>): Promise<T> {
    try {
      return await activeRequest.run(this, handler);
    } finally {
      this.completed = true;
    }
  }

  recordSql(query: string, durationMs: number, returnedRows: number, failed: boolean): void {
    if (this.completed) return;
    addSqlMetrics(this.sql, durationMs, returnedRows, failed);
    const fingerprint = createHash("sha256")
      .update(query.trim().replace(/\s+/g, " "))
      .digest("hex").slice(0, 16);
    let statement = this.statements.get(fingerprint);
    if (!statement) {
      if (this.statements.size >= MAX_SQL_FINGERPRINTS) {
        this.overflowCount += 1;
        return;
      }
      statement = emptySqlMetrics();
      this.statements.set(fingerprint, statement);
    }
    addSqlMetrics(statement, durationMs, returnedRows, failed);
  }

  recordCache(layer: CacheLayer, result: CacheResult): void {
    if (!this.completed) this.cache[layer][result] += 1;
  }

  snapshot() {
    if (this.sql.count === 0 && Object.values(this.cache).every((layer) =>
      layer.hit + layer.miss + layer.error === 0)) return undefined;
    return {
      sql: {
        ...roundedSqlMetrics(this.sql),
        statements: [...this.statements].map(([fingerprint, metrics]) => ({
          fingerprint, ...roundedSqlMetrics(metrics),
        })),
        overflow_count: this.overflowCount,
      },
      cache: { kv: { ...this.cache.kv }, cache_api: { ...this.cache.cache_api } },
    };
  }
}

export function recordSqlQuery(
  query: string, durationMs: number, returnedRows: number, failed: boolean,
): void {
  activeRequest.getStore()?.recordSql(query, durationMs, returnedRows, failed);
}

export function recordCacheRead(layer: CacheLayer, result: CacheResult): void {
  activeRequest.getStore()?.recordCache(layer, result);
}

function emptySqlMetrics(): SqlMetrics {
  return { count: 0, duration_ms: 0, max_duration_ms: 0, returned_rows: 0, errors: 0 };
}

function addSqlMetrics(metrics: SqlMetrics, duration: number, rows: number, failed: boolean): void {
  metrics.count += 1;
  metrics.duration_ms += duration;
  metrics.max_duration_ms = Math.max(metrics.max_duration_ms, duration);
  metrics.returned_rows += rows;
  if (failed) metrics.errors += 1;
}

function roundedSqlMetrics(metrics: SqlMetrics): SqlMetrics {
  return {
    ...metrics,
    duration_ms: Math.round(metrics.duration_ms * 100) / 100,
    max_duration_ms: Math.round(metrics.max_duration_ms * 100) / 100,
  };
}
