import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
} from "@kando/auth-core";
import { Hono } from "hono";
import { ulid } from "ulid";
import type { Env } from "../env";

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
  WHERE device_id = ? AND upgraded_user_id IS NULL
  ORDER BY created_at DESC
  LIMIT 1
`;

const INSERT_ANONYMOUS_ACCOUNT_SQL = `
  INSERT INTO anonymous_account (id, device_id, created_at, upgraded_user_id)
  VALUES (?, ?, ?, NULL)
`;

const INSERT_PORTFOLIO_FOLDER_SQL = `
  INSERT INTO portfolio_folder
    (id, owner_type, owner_id, name, is_default, sort_order, created_at, updated_at)
  VALUES (?, 'anonymous', ?, 'Main', 1, 0, ?, ?)
`;

const INSERT_USER_PREFERENCE_SQL = `
  INSERT INTO user_preference
    (id, owner_type, owner_id, currency, amount_hidden, last_selected_folder_id, created_at, updated_at)
  VALUES (?, 'anonymous', ?, 'USD', 0, NULL, ?, ?)
`;

const INSERT_SESSION_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, 'anonymous', ?, ?, ?, ?, NULL)
`;

export const authRoutes = new Hono<{ Bindings: Env }>();

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

  if (typeof rawDeviceId !== "string") {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }

  const deviceId = rawDeviceId.trim();

  if (deviceId.length === 0) {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
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
    const anonymousId = await findOrCreateAnonymousAccount(
      c.env.DB,
      deviceId,
      createdAt,
    );
    const sessionId = ulid();
    const refreshToken = createRefreshToken();
    const hashedRefreshToken = await hashRefreshToken(refreshToken);
    const expiresAt = refreshTokenExpiresAt(now);

    await c.env.DB.prepare(INSERT_SESSION_SQL)
      .bind(sessionId, anonymousId, hashedRefreshToken, expiresAt, createdAt)
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
      },
    });
  } catch (error) {
    console.error("Failed to create anonymous session.", error);
    return c.json(INTERNAL_ERROR_RESPONSE, 500);
  }
});

async function findOrCreateAnonymousAccount(
  db: D1Database,
  deviceId: string,
  createdAt: string,
): Promise<string> {
  const existing = await db
    .prepare(SELECT_REUSABLE_ANONYMOUS_ACCOUNT_SQL)
    .bind(deviceId)
    .first<AnonymousAccountRow>();

  if (existing) {
    return existing.id;
  }

  const anonymousId = ulid();

  await db.batch([
    db
      .prepare(INSERT_ANONYMOUS_ACCOUNT_SQL)
      .bind(anonymousId, deviceId, createdAt),
    db
      .prepare(INSERT_PORTFOLIO_FOLDER_SQL)
      .bind(ulid(), anonymousId, createdAt, createdAt),
    db
      .prepare(INSERT_USER_PREFERENCE_SQL)
      .bind(ulid(), anonymousId, createdAt, createdAt),
  ]);

  return anonymousId;
}
