import type { Env } from "../env";
import { createPostgresDatabase, type PostgresDatabase } from "../db/postgres-database";
import { createFilesystemR2Bucket } from "./filesystem-r2";
import { createInMemoryKv } from "./in-memory-kv";

export type LinuxRuntime = {
  env: Env;
  database: PostgresDatabase;
  hostname: string;
  port: number;
  scheduledTaskIntervalMs: number;
};

export function loadLinuxRuntime(source: NodeJS.ProcessEnv = process.env): LinuxRuntime {
  const appEnvironment = optional(source, "APP_ENVIRONMENT") ?? "development";
  if (appEnvironment !== "development") {
    throw new Error("Linux test runtime requires APP_ENVIRONMENT=development");
  }

  const database = createPostgresDatabase(required(source, "DATABASE_URL"));
  const objectStoragePath = required(source, "OBJECT_STORAGE_PATH");
  const env: Env = {
    DB: database,
    CACHE_KV: createInMemoryKv(),
    SCAN_IMAGES: createFilesystemR2Bucket(objectStoragePath),
    JWT_SECRET: required(source, "JWT_SECRET"),
    OCR_SERVICE_BASE_URL: required(source, "OCR_SERVICE_BASE_URL"),
    ALLOWED_ORIGINS: required(source, "ALLOWED_ORIGINS"),
    APP_ENVIRONMENT: "development",
    GOOGLE_CLIENT_ID: optional(source, "GOOGLE_CLIENT_ID"),
    APPLE_CLIENT_ID: optional(source, "APPLE_CLIENT_ID"),
    APPLE_IAP_BUNDLE_ID: optional(source, "APPLE_IAP_BUNDLE_ID"),
    APPLE_IAP_APP_ID: optional(source, "APPLE_IAP_APP_ID"),
    APPLE_APP_ATTEST_APP_ID: optional(source, "APPLE_APP_ATTEST_APP_ID"),
    APPLE_APP_ATTEST_DEVELOPMENT: optional(source, "APPLE_APP_ATTEST_DEVELOPMENT"),
    APPLE_IAP_PRODUCT_IDS: optional(source, "APPLE_IAP_PRODUCT_IDS"),
    APPLE_ROOT_CERTIFICATES_BASE64: optional(source, "APPLE_ROOT_CERTIFICATES_BASE64"),
    APPLE_IAP_ISSUER_ID: optional(source, "APPLE_IAP_ISSUER_ID"),
    APPLE_IAP_KEY_ID: optional(source, "APPLE_IAP_KEY_ID"),
    APPLE_IAP_PRIVATE_KEY: optional(source, "APPLE_IAP_PRIVATE_KEY"),
    ZEPTOMAIL_TOKEN: optional(source, "ZEPTOMAIL_TOKEN"),
    ZEPTOMAIL_API_URL: optional(source, "ZEPTOMAIL_API_URL"),
    MAIL_FROM_ADDRESS: optional(source, "MAIL_FROM_ADDRESS"),
    MAIL_FROM_NAME: optional(source, "MAIL_FROM_NAME"),
    MIXPANEL_PROJECT_TOKEN: optional(source, "MIXPANEL_PROJECT_TOKEN"),
    MIXPANEL_API_SECRET: optional(source, "MIXPANEL_API_SECRET"),
    SINGULAR_API_KEY: optional(source, "SINGULAR_API_KEY"),
    SINGULAR_SECRET_KEY: optional(source, "SINGULAR_SECRET_KEY"),
  };

  return {
    env,
    database,
    hostname: optional(source, "HOST") ?? "0.0.0.0",
    port: positiveInteger(source, "PORT", 3000),
    scheduledTaskIntervalMs:
      positiveInteger(source, "SCHEDULED_TASK_INTERVAL_SECONDS", 300) * 1000,
  };
}

function required(source: NodeJS.ProcessEnv, name: string): string {
  const value = optional(source, name);
  if (!value) throw new Error(`${name} is required for the Linux test runtime`);
  return value;
}

function optional(source: NodeJS.ProcessEnv, name: string): string | undefined {
  const value = source[name]?.trim();
  return value || undefined;
}

function positiveInteger(
  source: NodeJS.ProcessEnv,
  name: string,
  fallback: number,
): number {
  const value = optional(source, name);
  if (!value) return fallback;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}
