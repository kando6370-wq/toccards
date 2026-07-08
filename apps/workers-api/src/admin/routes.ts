import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashRefreshToken,
  refreshTokenExpiresAt,
  verifyPassword,
} from "@kando/auth-core";
import { Hono } from "hono";
import type { Context, Next } from "hono";
import { ulid } from "ulid";
import type { Env } from "../env";
import { getBearerToken, hasSigningSecret } from "../auth/http-auth";

type AdminRole = "super_admin" | "operator";
type AdminStatus = "active" | "disabled";
type FeedbackStatus = "open" | "in_progress" | "closed";

type AdminPrincipal = {
  admin_id: string;
  email: string;
  role: AdminRole;
  session_id: string;
};

type AdminUserRow = {
  id: string;
  email: string;
  password_hash: string;
  role: string;
  status: AdminStatus;
  created_at: string;
};

type SessionRow = {
  id: string;
  owner_type: string;
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

type AdminJwtPayload = {
  token_type: "admin";
  admin_id: string;
  role: AdminRole;
  session_id: string;
  iat: number;
  exp: number;
};

type AdminBindings = { Bindings: Env; Variables: { admin: AdminPrincipal } };
type AdminContext = Context<AdminBindings>;

const EMAIL_MAX_LENGTH = 254;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const VALID_ROLES = new Set<AdminRole>(["super_admin", "operator"]);
const VALID_FEEDBACK_STATUSES = new Set<FeedbackStatus>([
  "open",
  "in_progress",
  "closed",
]);
const DUMMY_PASSWORD_HASH =
  "pbkdf2-sha256$v1$210000$AAECAwQFBgcICQoLDA0ODw$5n_O9-8D7zbhW7HPSP6NZf4STgnvUR115Y1j4dCrwHo";

const UNAUTHORIZED_RESPONSE = {
  success: false,
  error: { code: "UNAUTHORIZED", message: "Unauthorized." },
} as const;

const FORBIDDEN_RESPONSE = {
  success: false,
  error: { code: "FORBIDDEN", message: "Forbidden." },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const NOT_FOUND_RESPONSE = {
  success: false,
  error: { code: "NOT_FOUND", message: "Not found." },
} as const;

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: { code: "VALIDATION_ERROR", message: "Invalid request." },
} as const;

const SELECT_ADMIN_BY_EMAIL_SQL = `
  SELECT id, email, password_hash, role, status, created_at
  FROM admin_user
  WHERE email = ?
  LIMIT 1
`;

const SELECT_ADMIN_BY_ID_SQL = `
  SELECT id, email, password_hash, role, status, created_at
  FROM admin_user
  WHERE id = ?
  LIMIT 1
`;

const INSERT_ADMIN_SESSION_SQL = `
  INSERT INTO session
    (id, owner_type, owner_id, refresh_token, expires_at, created_at, revoked_at)
  VALUES (?, ?, ?, ?, ?, ?, NULL)
`;

const SELECT_SESSION_BY_REFRESH_TOKEN_SQL = `
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE refresh_token = ?
  LIMIT 1
`;

const SELECT_SESSION_BY_ID_SQL = `
  SELECT id, owner_type, owner_id, expires_at, revoked_at
  FROM session
  WHERE id = ?
  LIMIT 1
`;

const REVOKE_SESSION_SQL = `
  UPDATE session SET revoked_at = ?
  WHERE id = ? AND revoked_at IS NULL
`;

const SELECT_ADMIN_USERS_SQL = `
  SELECT 'user' AS account_type, id, email, NULL AS device_id, created_at,
    CASE WHEN deleted_at IS NULL THEN 'active' ELSE 'disabled' END AS status
  FROM user
  WHERE (? IS NULL OR ? = 'user')
    AND (? IS NULL OR lower(email) LIKE '%' || ? || '%')
  UNION ALL
  SELECT 'anonymous' AS account_type, id, NULL AS email, device_id, created_at,
    CASE WHEN upgraded_user_id IS NULL THEN 'guest' ELSE 'upgraded' END AS status
  FROM anonymous_account
  WHERE (? IS NULL OR ? = 'anonymous')
    AND (? IS NULL OR lower(device_id) LIKE '%' || ? || '%')
  ORDER BY created_at DESC
  LIMIT ? OFFSET ?
`;

const SELECT_USER_DETAIL_SQL = `
  SELECT id, email, display_name, created_at, updated_at, deleted_at
  FROM user
  WHERE id = ?
  LIMIT 1
`;

const SELECT_ANONYMOUS_DETAIL_SQL = `
  SELECT id, device_id, created_at, upgraded_user_id
  FROM anonymous_account
  WHERE id = ?
  LIMIT 1
`;

const DISABLE_USER_SQL = `
  UPDATE user SET deleted_at = ?
  WHERE id = ? AND deleted_at IS NULL
`;

const SELECT_FEEDBACKS_SQL = `
  SELECT id, email, types, functions, message, status, created_at, updated_at
  FROM feedback_ticket
  WHERE (? IS NULL OR status = ?)
  ORDER BY created_at DESC
  LIMIT ? OFFSET ?
`;

const SELECT_FEEDBACK_BY_ID_SQL = `
  SELECT id, email, types, functions, message, status, created_at, updated_at
  FROM feedback_ticket
  WHERE id = ?
  LIMIT 1
`;

const UPDATE_FEEDBACK_STATUS_SQL = `
  UPDATE feedback_ticket SET status = ?, updated_at = ?
  WHERE id = ?
`;

const SELECT_APP_CONFIG_SQL = `
  SELECT key, value, updated_by, updated_at
  FROM app_config
  ORDER BY key ASC
`;

const UPSERT_APP_CONFIG_SQL = `
  INSERT INTO app_config (key, value, updated_by, updated_at)
  VALUES (?, ?, ?, ?)
  ON CONFLICT(key) DO UPDATE SET
    value = excluded.value,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
`;

const SELECT_TRENDING_PINS_SQL = `
  SELECT id, card_ref, rank, active, updated_by, updated_at
  FROM trending_pin
  ORDER BY rank ASC
`;

const SELECT_TRENDING_PIN_BY_ID_SQL = `
  SELECT id, card_ref, rank, active, updated_by, updated_at
  FROM trending_pin
  WHERE id = ?
  LIMIT 1
`;

const INSERT_TRENDING_PIN_SQL = `
  INSERT INTO trending_pin (id, card_ref, rank, active, updated_by, updated_at)
  VALUES (?, ?, ?, ?, ?, ?)
`;

const UPDATE_TRENDING_PIN_SQL = `
  UPDATE trending_pin SET rank = ?, active = ?, updated_by = ?, updated_at = ?
  WHERE id = ?
`;

const DELETE_TRENDING_PIN_SQL = `
  DELETE FROM trending_pin
  WHERE id = ?
`;

const SELECT_CARD_OVERRIDES_SQL = `
  SELECT id, card_ref, override_fields, image_url, is_missing_card, updated_by, updated_at
  FROM card_override
  WHERE (? IS NULL OR is_missing_card = ?)
    AND (? IS NULL OR lower(card_ref) LIKE '%' || ? || '%')
  ORDER BY updated_at DESC
  LIMIT ? OFFSET ?
`;

const SELECT_CARD_OVERRIDE_BY_ID_SQL = `
  SELECT id, card_ref, override_fields, image_url, is_missing_card, updated_by, updated_at
  FROM card_override
  WHERE id = ?
  LIMIT 1
`;

const SELECT_CARD_OVERRIDE_BY_REF_SQL = `
  SELECT id, card_ref, override_fields, image_url, is_missing_card, updated_by, updated_at
  FROM card_override
  WHERE card_ref = ?
  LIMIT 1
`;

const INSERT_CARD_OVERRIDE_SQL = `
  INSERT INTO card_override
    (id, card_ref, override_fields, image_url, is_missing_card, updated_by, updated_at)
  VALUES (?, ?, ?, ?, ?, ?, ?)
`;

const UPDATE_CARD_OVERRIDE_SQL = `
  UPDATE card_override SET
    override_fields = ?,
    image_url = ?,
    is_missing_card = ?,
    updated_by = ?,
    updated_at = ?
  WHERE id = ?
`;

const DELETE_CARD_OVERRIDE_SQL = `
  DELETE FROM card_override
  WHERE id = ?
`;

export const adminRoutes = new Hono<AdminBindings>();

adminRoutes.post("/auth/login", async (c) => {
  const input = await readJsonObject(c.req);
  const email = normalizeEmail(input.email);
  const password = typeof input.password === "string" ? input.password : null;

  if (!email || !isValidEmail(email) || !password) {
    return c.json({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Incorrect email or password.",
      },
    }, 422);
  }

  if (!hasSigningSecret(c.env.JWT_SECRET)) {
    return c.json(INTERNAL_ERROR_RESPONSE, 500);
  }

  const admin = await c.env.DB.prepare(SELECT_ADMIN_BY_EMAIL_SQL)
    .bind(email)
    .first<AdminUserRow>();
  const passwordMatches = await verifyPassword(
    password,
    admin?.password_hash ?? DUMMY_PASSWORD_HASH,
  );

  if (!admin || !passwordMatches || !isAdminRole(admin.role)) {
    return c.json({
      success: false,
      error: {
        code: "VALIDATION_ERROR",
        message: "Incorrect email or password.",
      },
    }, 422);
  }

  if (admin.status === "disabled") {
    return c.json({
      success: false,
      error: {
        code: "FORBIDDEN",
        message: "Your account has been disabled.",
      },
    }, 403);
  }

  const now = new Date();
  const createdAt = now.toISOString();
  const sessionId = ulid();
  const refreshToken = createRefreshToken();
  const hashedRefreshToken = await hashRefreshToken(refreshToken);

  await c.env.DB.prepare(INSERT_ADMIN_SESSION_SQL)
    .bind(
      sessionId,
      "admin",
      admin.id,
      hashedRefreshToken,
      refreshTokenExpiresAt(now),
      createdAt,
    )
    .run();

  const accessToken = await signAdminAccessToken(
    {
      admin_id: admin.id,
      role: admin.role,
      session_id: sessionId,
    },
    c.env.JWT_SECRET,
    now,
  );

  return c.json({
    success: true,
    data: {
      admin_id: admin.id,
      email: admin.email,
      role: admin.role,
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
    },
  });
});

adminRoutes.post("/auth/refresh", async (c) => {
  const refreshToken = await readRefreshToken(c.req);
  if (!refreshToken) return c.json(UNAUTHORIZED_RESPONSE, 401);
  if (!hasSigningSecret(c.env.JWT_SECRET)) {
    return c.json(INTERNAL_ERROR_RESPONSE, 500);
  }

  const session = await findLiveAdminSessionByRefreshToken(
    c.env.DB,
    refreshToken,
    new Date(),
  );
  if (!session) return c.json(UNAUTHORIZED_RESPONSE, 401);

  const admin = await findActiveAdmin(c.env.DB, session.owner_id);
  if (!admin) return c.json(FORBIDDEN_RESPONSE, 403);

  const accessToken = await signAdminAccessToken(
    {
      admin_id: admin.id,
      role: admin.role,
      session_id: session.id,
    },
    c.env.JWT_SECRET,
  );

  return c.json({
    success: true,
    data: {
      access_token: accessToken,
      expires_in: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
    },
  });
});

adminRoutes.use("*", requireAdmin);

adminRoutes.post("/auth/logout", async (c) => {
  const refreshToken = await readRefreshToken(c.req);
  if (!refreshToken) return c.json(VALIDATION_ERROR_RESPONSE, 422);

  const admin = c.get("admin");
  const session = await findLiveAdminSessionByRefreshToken(
    c.env.DB,
    refreshToken,
    new Date(),
  );

  if (
    !session ||
    session.id !== admin.session_id ||
    session.owner_id !== admin.admin_id
  ) {
    return c.json(UNAUTHORIZED_RESPONSE, 401);
  }

  await c.env.DB.prepare(REVOKE_SESSION_SQL)
    .bind(new Date().toISOString(), session.id)
    .run();

  return c.json({ success: true, data: {} });
});

adminRoutes.get("/users", async (c) => {
  const page = readPositiveInt(c.req.query("page"), 1);
  const pageSize = Math.min(readPositiveInt(c.req.query("page_size"), 20), 100);
  const type = readUserType(c.req.query("type"));
  const q = normalizeQuery(c.req.query("q"));
  const offset = (page - 1) * pageSize;
  const { results = [] } = await c.env.DB.prepare(SELECT_ADMIN_USERS_SQL)
    .bind(type, type, q, q, type, type, q, q, pageSize, offset)
    .all();

  return c.json({
    success: true,
    data: { items: results, page, page_size: pageSize },
  });
});

adminRoutes.get("/users/:accountType/:id", async (c) => {
  const accountType = c.req.param("accountType");
  const id = c.req.param("id");
  const row =
    accountType === "user"
      ? await c.env.DB.prepare(SELECT_USER_DETAIL_SQL).bind(id).first()
      : accountType === "anonymous"
        ? await c.env.DB.prepare(SELECT_ANONYMOUS_DETAIL_SQL).bind(id).first()
        : null;

  if (!row) return c.json(NOT_FOUND_RESPONSE, 404);

  return c.json({
    success: true,
    data: {
      account_type: accountType,
      ...row,
      asset_summary: {
        folder_count: 0,
        item_count: 0,
        wishlist_count: 0,
      },
    },
  });
});

adminRoutes.patch("/users/user/:id/disable", async (c) => {
  if (c.get("admin").role !== "super_admin") {
    return c.json(FORBIDDEN_RESPONSE, 403);
  }

  const id = c.req.param("id");
  const existing = await c.env.DB.prepare(SELECT_USER_DETAIL_SQL).bind(id).first();
  if (!existing) return c.json(NOT_FOUND_RESPONSE, 404);

  await c.env.DB.prepare(DISABLE_USER_SQL).bind(new Date().toISOString(), id).run();
  const row = await c.env.DB.prepare(SELECT_USER_DETAIL_SQL).bind(id).first();
  return c.json({ success: true, data: row });
});

adminRoutes.get("/feedbacks", async (c) => {
  const page = readPositiveInt(c.req.query("page"), 1);
  const pageSize = Math.min(readPositiveInt(c.req.query("page_size"), 20), 100);
  const status = readFeedbackStatus(c.req.query("status"));
  const offset = (page - 1) * pageSize;
  const { results = [] } = await c.env.DB.prepare(SELECT_FEEDBACKS_SQL)
    .bind(status, status, pageSize, offset)
    .all();

  return c.json({ success: true, data: { items: results, page, page_size: pageSize } });
});

adminRoutes.get("/feedbacks/:ticketId", async (c) => {
  const row = await c.env.DB.prepare(SELECT_FEEDBACK_BY_ID_SQL)
    .bind(c.req.param("ticketId"))
    .first();
  return row ? c.json({ success: true, data: row }) : c.json(NOT_FOUND_RESPONSE, 404);
});

adminRoutes.patch("/feedbacks/:ticketId/status", async (c) => {
  const input = await readJsonObject(c.req);
  const status = readFeedbackStatus(input.status);
  if (!status) return c.json(VALIDATION_ERROR_RESPONSE, 422);

  const id = c.req.param("ticketId");
  await c.env.DB.prepare(UPDATE_FEEDBACK_STATUS_SQL)
    .bind(status, new Date().toISOString(), id)
    .run();
  const row = await c.env.DB.prepare(SELECT_FEEDBACK_BY_ID_SQL).bind(id).first();

  return row ? c.json({ success: true, data: row }) : c.json(NOT_FOUND_RESPONSE, 404);
});

adminRoutes.get("/app-config", async (c) => {
  const { results = [] } = await c.env.DB.prepare(SELECT_APP_CONFIG_SQL).all();
  return c.json({ success: true, data: { configs: results } });
});

adminRoutes.patch("/app-config/:key", async (c) => {
  const input = await readJsonObject(c.req);
  if (typeof input.value !== "string") {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }

  const key = c.req.param("key");
  await c.env.DB.prepare(UPSERT_APP_CONFIG_SQL)
    .bind(key, input.value, c.get("admin").admin_id, new Date().toISOString())
    .run();
  const { results = [] } = await c.env.DB.prepare(SELECT_APP_CONFIG_SQL).all();
  const row = results.find((config) => isRecord(config) && config.key === key);

  return c.json({ success: true, data: row ?? { key, value: input.value } });
});

adminRoutes.get("/trending-pins", async (c) => {
  const { results = [] } = await c.env.DB.prepare(SELECT_TRENDING_PINS_SQL).all();
  return c.json({ success: true, data: { items: results } });
});

adminRoutes.post("/trending-pins", async (c) => {
  const input = await readJsonObject(c.req);
  const cardRef = readRequiredString(input.card_ref);
  const rank = readPositiveInt(input.rank, 0);
  const active = input.active === false ? 0 : 1;
  if (!cardRef || rank <= 0) return c.json(VALIDATION_ERROR_RESPONSE, 422);

  const id = ulid();
  await c.env.DB.prepare(INSERT_TRENDING_PIN_SQL)
    .bind(id, cardRef, rank, active, c.get("admin").admin_id, new Date().toISOString())
    .run();
  const row = await c.env.DB.prepare(SELECT_TRENDING_PIN_BY_ID_SQL).bind(id).first();
  return c.json({ success: true, data: row });
});

adminRoutes.patch("/trending-pins/:pinId", async (c) => {
  const input = await readJsonObject(c.req);
  const rank = readPositiveInt(input.rank, 0);
  const active = input.active === false ? 0 : 1;
  if (rank <= 0) return c.json(VALIDATION_ERROR_RESPONSE, 422);

  const id = c.req.param("pinId");
  await c.env.DB.prepare(UPDATE_TRENDING_PIN_SQL)
    .bind(rank, active, c.get("admin").admin_id, new Date().toISOString(), id)
    .run();
  const row = await c.env.DB.prepare(SELECT_TRENDING_PIN_BY_ID_SQL).bind(id).first();
  return row ? c.json({ success: true, data: row }) : c.json(NOT_FOUND_RESPONSE, 404);
});

adminRoutes.delete("/trending-pins/:pinId", async (c) => {
  if (c.get("admin").role !== "super_admin") {
    return c.json(FORBIDDEN_RESPONSE, 403);
  }
  await c.env.DB.prepare(DELETE_TRENDING_PIN_SQL).bind(c.req.param("pinId")).run();
  return c.json({ success: true, data: {} });
});

adminRoutes.get("/card-overrides", async (c) => {
  const page = readPositiveInt(c.req.query("page"), 1);
  const pageSize = Math.min(readPositiveInt(c.req.query("page_size"), 20), 100);
  const missingFilter = readBooleanFilter(c.req.query("is_missing_card"));
  const q = normalizeQuery(c.req.query("q"));
  const offset = (page - 1) * pageSize;
  const { results = [] } = await c.env.DB.prepare(SELECT_CARD_OVERRIDES_SQL)
    .bind(missingFilter, missingFilter, q, q, pageSize, offset)
    .all();
  return c.json({ success: true, data: { items: results, page, page_size: pageSize } });
});

adminRoutes.post("/card-overrides", async (c) => {
  const input = await readJsonObject(c.req);
  const cardRef = readRequiredString(input.card_ref);
  if (!cardRef) return c.json(VALIDATION_ERROR_RESPONSE, 422);

  const id = ulid();
  await insertCardOverride(c, id, cardRef, input);
  const row = await c.env.DB.prepare(SELECT_CARD_OVERRIDE_BY_ID_SQL).bind(id).first();
  return c.json({ success: true, data: row });
});

adminRoutes.patch("/card-overrides/:overrideId", async (c) => {
  const input = await readJsonObject(c.req);
  const id = c.req.param("overrideId");
  const existing = await c.env.DB.prepare(SELECT_CARD_OVERRIDE_BY_ID_SQL).bind(id).first();
  if (!isRecord(existing)) return c.json(NOT_FOUND_RESPONSE, 404);

  await updateCardOverride(c, id, {
    override_fields: input.override_fields ?? existing.override_fields ?? null,
    image_url: input.image_url ?? existing.image_url ?? null,
    is_missing_card: input.is_missing_card ?? existing.is_missing_card ?? 0,
  });
  const row = await c.env.DB.prepare(SELECT_CARD_OVERRIDE_BY_ID_SQL).bind(id).first();
  return c.json({ success: true, data: row });
});

adminRoutes.delete("/card-overrides/:overrideId", async (c) => {
  if (c.get("admin").role !== "super_admin") {
    return c.json(FORBIDDEN_RESPONSE, 403);
  }
  await c.env.DB.prepare(DELETE_CARD_OVERRIDE_SQL)
    .bind(c.req.param("overrideId"))
    .run();
  return c.json({ success: true, data: {} });
});

adminRoutes.post("/card-overrides/image-upload", async (c) => {
  const input = await readJsonObject(c.req);
  const cardRef = readRequiredString(input.card_ref);
  const imageUrl = readRequiredString(input.image_url);
  if (!cardRef || !imageUrl) return c.json(VALIDATION_ERROR_RESPONSE, 422);

  const existing = await c.env.DB.prepare(SELECT_CARD_OVERRIDE_BY_REF_SQL)
    .bind(cardRef)
    .first();

  if (isRecord(existing) && typeof existing.id === "string") {
    await updateCardOverride(c, existing.id, {
      override_fields: existing.override_fields ?? null,
      image_url: imageUrl,
      is_missing_card: existing.is_missing_card ?? 0,
    });
    const row = await c.env.DB.prepare(SELECT_CARD_OVERRIDE_BY_ID_SQL)
      .bind(existing.id)
      .first();
    return c.json({ success: true, data: row });
  }

  const id = ulid();
  await c.env.DB.prepare(INSERT_CARD_OVERRIDE_SQL)
    .bind(id, cardRef, null, imageUrl, 0, c.get("admin").admin_id, new Date().toISOString())
    .run();
  const row = await c.env.DB.prepare(SELECT_CARD_OVERRIDE_BY_ID_SQL).bind(id).first();
  return c.json({ success: true, data: row });
});

async function requireAdmin(c: AdminContext, next: Next): Promise<Response | void> {
  const token = getBearerToken(c.req.header("Authorization"));
  if (!token) return c.json(UNAUTHORIZED_RESPONSE, 401);
  if (!hasSigningSecret(c.env.JWT_SECRET)) {
    return c.json(INTERNAL_ERROR_RESPONSE, 500);
  }

  const verification = await verifyAdminAccessToken(token, c.env.JWT_SECRET);
  if (!verification.valid) return c.json(UNAUTHORIZED_RESPONSE, 401);

  const [admin, session] = await Promise.all([
    findActiveAdmin(c.env.DB, verification.payload.admin_id),
    findLiveAdminSessionById(c.env.DB, verification.payload.session_id, new Date()),
  ]);

  if (
    !admin ||
    !session ||
    session.owner_id !== verification.payload.admin_id ||
    admin.role !== verification.payload.role
  ) {
    return c.json(UNAUTHORIZED_RESPONSE, 401);
  }

  c.set("admin", {
    admin_id: admin.id,
    email: admin.email,
    role: admin.role,
    session_id: session.id,
  });
  await next();
}

async function findActiveAdmin(
  db: D1Database,
  adminId: string,
): Promise<(AdminUserRow & { role: AdminRole }) | null> {
  const admin = await db.prepare(SELECT_ADMIN_BY_ID_SQL).bind(adminId).first<AdminUserRow>();
  if (!admin || admin.status !== "active" || !isAdminRole(admin.role)) {
    return null;
  }
  return admin as AdminUserRow & { role: AdminRole };
}

async function findLiveAdminSessionByRefreshToken(
  db: D1Database,
  refreshToken: string,
  now: Date,
): Promise<SessionRow | null> {
  const hashedRefreshToken = await hashRefreshToken(refreshToken);
  const session = await db
    .prepare(SELECT_SESSION_BY_REFRESH_TOKEN_SQL)
    .bind(hashedRefreshToken)
    .first<SessionRow>();
  return isLiveAdminSession(session, now) ? session : null;
}

async function findLiveAdminSessionById(
  db: D1Database,
  sessionId: string,
  now: Date,
): Promise<SessionRow | null> {
  const session = await db
    .prepare(SELECT_SESSION_BY_ID_SQL)
    .bind(sessionId)
    .first<SessionRow>();
  return isLiveAdminSession(session, now) ? session : null;
}

function isLiveAdminSession(
  session: SessionRow | null,
  now: Date,
): session is SessionRow {
  const expiresAt = session ? Date.parse(session.expires_at) : NaN;
  return (
    !!session &&
    session.owner_type === "admin" &&
    session.revoked_at === null &&
    Number.isFinite(expiresAt) &&
    expiresAt > now.getTime()
  );
}

async function readJsonObject(request: { json(): Promise<unknown> }): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    return isRecord(value) ? value : {};
  } catch {
    return {};
  }
}

async function readRefreshToken(request: { json(): Promise<unknown> }): Promise<string | null> {
  const input = await readJsonObject(request);
  return readRequiredString(input.refresh_token);
}

function normalizeEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  return email.length > 0 ? email : null;
}

function isValidEmail(email: string): boolean {
  return email.length <= EMAIL_MAX_LENGTH && EMAIL_PATTERN.test(email);
}

function isAdminRole(value: string): value is AdminRole {
  return VALID_ROLES.has(value as AdminRole);
}

function readUserType(value: string | undefined): "user" | "anonymous" | null {
  return value === "user" || value === "anonymous" ? value : null;
}

function readFeedbackStatus(value: unknown): FeedbackStatus | null {
  return typeof value === "string" && VALID_FEEDBACK_STATUSES.has(value as FeedbackStatus)
    ? (value as FeedbackStatus)
    : null;
}

function readBooleanFilter(value: string | undefined): number | null {
  if (value === "true") return 1;
  if (value === "false") return 0;
  return null;
}

function normalizeQuery(value: string | undefined): string | null {
  const query = typeof value === "string" ? value.trim().toLowerCase() : "";
  return query.length > 0 ? query : null;
}

function readPositiveInt(value: unknown, fallback: number): number {
  const parsed =
    typeof value === "number"
      ? value
      : typeof value === "string"
        ? Number.parseInt(value, 10)
        : NaN;
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function readRequiredString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

async function insertCardOverride(
  c: AdminContext,
  id: string,
  cardRef: string,
  input: Record<string, unknown>,
): Promise<void> {
  await c.env.DB.prepare(INSERT_CARD_OVERRIDE_SQL)
    .bind(
      id,
      cardRef,
      stringifyJsonObject(input.override_fields),
      typeof input.image_url === "string" ? input.image_url : null,
      input.is_missing_card === true ? 1 : 0,
      c.get("admin").admin_id,
      new Date().toISOString(),
    )
    .run();
}

async function updateCardOverride(
  c: AdminContext,
  id: string,
  input: {
    override_fields: unknown;
    image_url: unknown;
    is_missing_card: unknown;
  },
): Promise<void> {
  await c.env.DB.prepare(UPDATE_CARD_OVERRIDE_SQL)
    .bind(
      stringifyJsonObject(input.override_fields),
      typeof input.image_url === "string" ? input.image_url : null,
      input.is_missing_card === true || input.is_missing_card === 1 ? 1 : 0,
      c.get("admin").admin_id,
      new Date().toISOString(),
      id,
    )
    .run();
}

function stringifyJsonObject(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "string") return value;
  if (isRecord(value)) return JSON.stringify(value);
  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function signAdminAccessToken(
  payload: Omit<AdminJwtPayload, "token_type" | "iat" | "exp">,
  secret: string,
  now = new Date(),
): Promise<string> {
  const iat = Math.floor(now.getTime() / 1000);
  return signJwt(
    {
      token_type: "admin",
      ...payload,
      iat,
      exp: iat + ACCESS_TOKEN_EXPIRES_IN_SECONDS,
    },
    secret,
  );
}

async function verifyAdminAccessToken(
  token: string,
  secret: string,
  now = new Date(),
): Promise<
  | { valid: true; payload: AdminJwtPayload }
  | { valid: false }
> {
  const parts = token.split(".");
  if (parts.length !== 3) return { valid: false };
  const [encodedHeader, encodedPayload, encodedSignature] = parts as [
    string,
    string,
    string,
  ];

  try {
    const header = JSON.parse(decodeText(decodeBase64Url(encodedHeader)));
    if (!isRecord(header) || header.alg !== "HS256" || header.typ !== "JWT") {
      return { valid: false };
    }

    const expectedSignature = await signHs256(`${encodedHeader}.${encodedPayload}`, secret);
    const signature = decodeBase64Url(encodedSignature);
    if (!signatureMatches(signature, expectedSignature)) return { valid: false };

    const payload = JSON.parse(decodeText(decodeBase64Url(encodedPayload)));
    if (!isAdminJwtPayload(payload)) return { valid: false };
    if (payload.exp <= Math.floor(now.getTime() / 1000)) return { valid: false };

    return { valid: true, payload };
  } catch {
    return { valid: false };
  }
}

async function signJwt(payload: AdminJwtPayload, secret: string): Promise<string> {
  const encodedHeader = encodeBase64Url(encodeText(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const encodedPayload = encodeBase64Url(encodeText(JSON.stringify(payload)));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await signHs256(signingInput, secret);
  return `${signingInput}.${encodeBase64Url(signature)}`;
}

async function signHs256(signingInput: string, secret: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    encodeText(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encodeText(signingInput));
  return new Uint8Array(signature);
}

function isAdminJwtPayload(value: unknown): value is AdminJwtPayload {
  return (
    isRecord(value) &&
    value.token_type === "admin" &&
    typeof value.admin_id === "string" &&
    isAdminRole(String(value.role)) &&
    typeof value.session_id === "string" &&
    typeof value.iat === "number" &&
    typeof value.exp === "number"
  );
}

function signatureMatches(actual: Uint8Array, expected: Uint8Array): boolean {
  if (actual.length !== expected.length) return false;
  let difference = 0;
  for (let index = 0; index < actual.length; index += 1) {
    difference |= actual[index] ^ expected[index];
  }
  return difference === 0;
}

function encodeText(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function decodeText(value: Uint8Array): string {
  return new TextDecoder().decode(value);
}

const BASE64URL_ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

function encodeBase64Url(bytes: Uint8Array): string {
  let output = "";
  for (let index = 0; index < bytes.length; index += 3) {
    const first = bytes[index] ?? 0;
    const hasSecond = index + 1 < bytes.length;
    const hasThird = index + 2 < bytes.length;
    const second = hasSecond ? bytes[index + 1] : 0;
    const third = hasThird ? bytes[index + 2] : 0;
    const triplet = (first << 16) | (second << 8) | third;
    output += BASE64URL_ALPHABET[(triplet >> 18) & 0x3f];
    output += BASE64URL_ALPHABET[(triplet >> 12) & 0x3f];
    if (hasSecond) output += BASE64URL_ALPHABET[(triplet >> 6) & 0x3f];
    if (hasThird) output += BASE64URL_ALPHABET[triplet & 0x3f];
  }
  return output;
}

function decodeBase64Url(value: string): Uint8Array {
  if (value.length % 4 === 1) throw new Error("Invalid base64url.");
  let bits = 0;
  let bitLength = 0;
  const bytes: number[] = [];
  for (const char of value) {
    const index = BASE64URL_ALPHABET.indexOf(char);
    if (index === -1) throw new Error("Invalid base64url.");
    bits = (bits << 6) | index;
    bitLength += 6;
    if (bitLength >= 8) {
      bitLength -= 8;
      bytes.push((bits >> bitLength) & 0xff);
      bits &= (1 << bitLength) - 1;
    }
  }
  return new Uint8Array(bytes);
}
