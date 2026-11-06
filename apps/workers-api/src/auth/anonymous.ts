import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
} from "@kando/auth-core";
import { Hono } from "hono";
import { reserveAccountUid } from "../account-uid";
import {
  mutationLockKey,
  runWithMutationLockStatements,
} from "../db/mutation-lock";
import type { Env } from "../env";
import { createId } from "../id";
import { registerAccountRoutes } from "./account";
import { registerCurrentAccountRoutes } from "./current";
import { registerForgotPasswordRoutes } from "./forgot-password";
import { registerEmailLoginRoutes } from "./login";
import { registerOAuthRoutes } from "./oauth";
import { registerEmailRegistrationRoutes } from "./register";
import { registerSessionRoutes } from "./session";
import { resolveAuthPlatform } from "./platform";

type AnonymousAccountRow = {
  id: string;
};

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "device_id is required.",
  },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const SELECT_REUSABLE_ANONYMOUS_ACCOUNT_SQL = `
  SELECT id
  FROM anonymous_account
  WHERE device_id = ? AND platform = ? AND upgraded_user_id IS NULL AND status = 'active'
  ORDER BY created_at DESC, id ASC
  LIMIT 1
`;

const INSERT_ANONYMOUS_ACCOUNT_SQL = `
  INSERT INTO anonymous_account
    (id, device_id, created_at, upgraded_user_id, platform, status, deleted_at)
  SELECT ?, ?, ?, NULL, ?, 'active', NULL
  WHERE NOT EXISTS (
    SELECT 1 FROM anonymous_account
    WHERE device_id = ? AND platform = ? AND upgraded_user_id IS NULL AND status = 'active'
  )
`;

const UPSERT_APP_INSTALLATION_SQL = `
  INSERT INTO app_installation
    (installation_id, uid, platform, country_code, first_seen_at, last_seen_at)
  VALUES (?, ?, ?, ?, ?, ?)
  ON CONFLICT(installation_id) DO UPDATE SET
    uid = excluded.uid,
    platform = CASE WHEN excluded.platform = 'Unknown' THEN app_installation.platform ELSE excluded.platform END,
    country_code = COALESCE(excluded.country_code, app_installation.country_code),
    last_seen_at = excluded.last_seen_at
`;

const INSERT_PORTFOLIO_FOLDER_SQL = `
  INSERT INTO portfolio_folder
    (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  SELECT ?, 'anonymous', ?, 'Main', 1, 0, ?, ?
  WHERE EXISTS (SELECT 1 FROM anonymous_account WHERE id = ?)
`;

const INSERT_USER_PREFERENCE_SQL = `
  INSERT INTO user_preference
    (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  SELECT ?, 'anonymous', ?, 'USD', 0, NULL, ?, ?
  WHERE EXISTS (SELECT 1 FROM anonymous_account WHERE id = ?)
`;

const INSERT_SESSION_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, login_method, refresh_token, expires_at, created_at, revoked_at, platform, user_id)
  VALUES (?, 'anonymous', ?, NULL, ?, ?, ?, NULL, ?, NULL)
`;

export const authRoutes = new Hono<{ Bindings: Env }>();

registerAccountRoutes(authRoutes);
registerCurrentAccountRoutes(authRoutes);
registerSessionRoutes(authRoutes);
registerEmailRegistrationRoutes(authRoutes);
registerEmailLoginRoutes(authRoutes);
registerForgotPasswordRoutes(authRoutes);
registerOAuthRoutes(authRoutes);

authRoutes.post("/anonymous", async (c) => {
  let body: unknown;

  try {
    body = await c.req.json();
  } catch {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }

  const rawDeviceId =
    body && typeof body === "object"
      ? (body as { device_id?: unknown }).device_id
      : undefined;
  const rawPlatform =
    body && typeof body === "object"
      ? (body as { platform?: unknown }).platform
      : undefined;
  const rawIntegrityToken = body && typeof body === "object"
    ? (body as { integrity_token?: unknown }).integrity_token : undefined;
  const rawRequestNonce = body && typeof body === "object"
    ? (body as { request_nonce?: unknown }).request_nonce : undefined;

  if (typeof rawDeviceId !== "string") {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }

  const deviceId = rawDeviceId.trim();

  if (deviceId.length === 0) {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }

  const requestNonce = typeof rawRequestNonce === "string" ? rawRequestNonce.trim() : "";
  const platformResult = await resolveAuthPlatform(
    c.env,
    c.req.header("Authorization"),
    rawPlatform,
    typeof rawIntegrityToken === "string" ? rawIntegrityToken.trim() : undefined,
    { deviceId, requestNonce },
  );
  if (platformResult.status !== "ok") {
    return c.json({ success: false, error: { code: "PLATFORM_AUTH_FAILED", message: "Unable to verify this app installation." } }, 401);
  }

  if (
    !(
      typeof c.env.JWT_SECRET === "string" &&
      c.env.JWT_SECRET.trim().length > 0
    )
  ) {
    return c.json(INTERNAL_ERROR_RESPONSE, 500);
  }

  try {
    const now = new Date();
    const createdAt = now.toISOString();
    const platform = platformResult.platform;
    const countryCode = normalizeCountryCode(c.req.raw.cf?.country);
    const anonymousId = await findOrCreateAnonymousAccount(
      c.env.DB,
      deviceId,
      platform,
      createdAt,
    );
    await c.env.DB.prepare(UPSERT_APP_INSTALLATION_SQL)
      .bind(deviceId, anonymousId, platform === "ios" ? "iOS" : "Android", countryCode, createdAt, createdAt)
      .run();
    const sessionId = createId();
    const refreshToken = createRefreshToken();
    const hashedRefreshToken = await hashRefreshToken(refreshToken);
    const expiresAt = refreshTokenExpiresAt(now);

    await c.env.DB.prepare(INSERT_SESSION_SQL)
      .bind(sessionId, anonymousId, hashedRefreshToken, expiresAt, createdAt, platform)
      .run();

    const accessToken = await signAccessToken(
      {
        owner_type: "anonymous",
        owner_id: anonymousId,
        session_id: sessionId,
      },
      c.env.JWT_SECRET,
      now,
    );

    return c.json({
      success: true,
      data: {
        anonymous_id: anonymousId,
        access_token: accessToken,
        refresh_token: refreshToken,
        expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
          platform,
          data_space_id: anonymousId,
      },
    });
  } catch (error) {
    console.error("Failed to create anonymous session.", error);
    return c.json(INTERNAL_ERROR_RESPONSE, 500);
  }
});

function normalizeCountryCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.trim().toUpperCase();
  return /^[A-Z]{2}$/.test(code) && code !== "XX" ? code : null;
}

async function findOrCreateAnonymousAccount(
  db: D1Database,
  deviceId: string,
  platform: "ios" | "android",
  createdAt: string,
): Promise<string> {
  const existing = await db
    .prepare(SELECT_REUSABLE_ANONYMOUS_ACCOUNT_SQL)
    .bind(deviceId, platform)
    .first<AnonymousAccountRow>();

  if (existing) {
    return existing.id;
  }

  const anonymousId = await reserveAccountUid(db, createdAt);

  const [createdAccount] = await runWithMutationLockStatements(
    db,
    await mutationLockKey("anonymous-device", deviceId),
    [
      db
        .prepare(INSERT_ANONYMOUS_ACCOUNT_SQL)
        .bind(anonymousId, deviceId, createdAt, platform, deviceId, platform),
      db
        .prepare(INSERT_PORTFOLIO_FOLDER_SQL)
        .bind(createId(), anonymousId, createdAt, createdAt, anonymousId),
      db
        .prepare(INSERT_USER_PREFERENCE_SQL)
        .bind(createId(), anonymousId, createdAt, createdAt, anonymousId),
    ],
  );

  if (createdAccount?.meta.changes === 1) {
    return anonymousId;
  }

  const created = await db
    .prepare(SELECT_REUSABLE_ANONYMOUS_ACCOUNT_SQL)
    .bind(deviceId, platform)
    .first<AnonymousAccountRow>();
  if (!created) {
    throw new Error("Anonymous account mutation did not create or find an account");
  }
  return created.id;
}
