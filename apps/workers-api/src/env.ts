import type { Database } from "./db/database";

export interface Env {
  DB: Database;
  HYPERDRIVE?: Hyperdrive;
  CACHE_KV: KVNamespace;
  SCAN_IMAGES?: R2Bucket;
  JWT_SECRET: string;
  GOOGLE_CLIENT_ID?: string;
  APPLE_CLIENT_ID?: string;
  APPLE_IAP_BUNDLE_ID?: string;
  APPLE_IAP_APP_ID?: string;
  APPLE_APP_ATTEST_APP_ID?: string;
  APPLE_APP_ATTEST_DEVELOPMENT?: string;
  APPLE_IAP_PRODUCT_IDS?: string;
  APPLE_ROOT_CERTIFICATES_BASE64?: string;
  APPLE_IAP_ISSUER_ID?: string;
  APPLE_IAP_KEY_ID?: string;
  APPLE_IAP_PRIVATE_KEY?: string;
  APP_STORE_CONNECT_APP_ID?: string;
  APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID?: string;
  APP_STORE_CONNECT_ISSUER_ID?: string;
  APP_STORE_CONNECT_KEY_ID?: string;
  APP_STORE_CONNECT_PRIVATE_KEY?: string;
  SUBSCRIPTION_LIFETIME_PRODUCT_IDS?: string;
  SUBSCRIPTION_DISPLAY_PRODUCT_IDS?: string;
  ZEPTOMAIL_TOKEN?: string;
  ZEPTOMAIL_API_URL?: string;
  MAIL_FROM_ADDRESS?: string;
  MAIL_FROM_NAME?: string;
  MIXPANEL_PROJECT_TOKEN?: string;
  MIXPANEL_API_SECRET?: string;
  SINGULAR_API_KEY?: string;
  SINGULAR_SECRET_KEY?: string;
  ALLOWED_ORIGINS?: string;
  VECTOR_RECOGNITION?: Fetcher;
  PHASH_RECOGNITION_BASE_URL?: string;
  EXTENSION_RECOGNITION_KEY?: string;
  EXTENSION_RECOGNITION_RATE_LIMITER?: RateLimit;
  EXTENSION_CLIENT_IP?: string;
  APP_ENVIRONMENT?: "production" | "development";
}

export type RuntimeEnv = Omit<Env, "DB"> & {
  DB?: Database;
  HYPERDRIVE?: Hyperdrive;
};
