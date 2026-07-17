export interface Env {
  DB: D1Database;
  CACHE_KV: KVNamespace;
  SCAN_IMAGES?: R2Bucket;
  JWT_SECRET: string;
  GOOGLE_CLIENT_ID?: string;
  APPLE_CLIENT_ID?: string;
  ZEPTOMAIL_TOKEN?: string;
  ZEPTOMAIL_API_URL?: string;
  MAIL_FROM_ADDRESS?: string;
  MAIL_FROM_NAME?: string;
  OCR_SERVICE_BASE_URL?: string;
}
