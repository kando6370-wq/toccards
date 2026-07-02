export interface Env {
  DB: D1Database;
  CACHE_KV: KVNamespace;
  JWT_SECRET: string;
}
