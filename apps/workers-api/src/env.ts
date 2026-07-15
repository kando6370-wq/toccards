export interface Env {
  DB: D1Database;
  CACHE_KV: KVNamespace;
  JWT_SECRET: string;
  GOOGLE_CLIENT_ID?: string;
  APPLE_CLIENT_ID?: string;
  ZOHO_CLIENT_ID?: string;
  ZOHO_CLIENT_SECRET?: string;
  ZOHO_REFRESH_TOKEN?: string;
  ZOHO_ACCOUNT_ID?: string;
  ZOHO_FROM_ADDRESS?: string;
  OCR_SERVICE_BASE_URL?: string;
}
