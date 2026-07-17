import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashPassword,
  hashRefreshToken,
  refreshTokenExpiresAt,
  verifyPassword,
} from "@kando/auth-core";
import { Hono } from "hono";
import type { Context, Next } from "hono";
import type { Env } from "../env";
import { getBearerToken, hasSigningSecret } from "../auth/http-auth";
import { createId } from "../id";
import {
  getJustTcgPriceSyncStatus,
  runJustTcgPriceSync,
} from "../price-sync/justtcg";

type AdminRole = "super_admin" | "operator";
type AdminStatus = "active" | "disabled";
type FeedbackStatus = "pending" | "processed" | "ignored";
type FeedbackStorageStatus = FeedbackStatus | "open" | "in_progress" | "closed";
type AppVersionPlatform = "iOS" | "Google";
type AppVersionStatus = "enabled" | "disabled";

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

type InstallationSourceRow = {
  install_type: "user" | "anonymous";
  uid: string;
  platform: string;
  country: string;
  environment: string;
  created_at: string;
};

type FeedbackTicketRow = {
  id: string;
  email: string;
  types: string;
  functions: string;
  message: string;
  status: FeedbackStorageStatus;
  created_at: string;
  updated_at: string;
};

type ScanRecordRow = {
  id: string;
  owner_type: string;
  owner_id: string;
  image_url: string | null;
  filename: string;
  platform: string;
  app_version: string;
  device_model: string | null;
  os_version: string | null;
  recognition_status: string;
  user_confirmation_status: string;
  modified_result: number;
  system_result: string;
  user_result: string;
  candidates: string;
  created_at: string;
};

type AppConfigRow = {
  key: string;
  value: string;
  updated_by: string | null;
  updated_at: string;
};

type AppVersionRecord = {
  platform: AppVersionPlatform;
  min_supported_version: string;
  recommended_version: string;
  force_update: boolean;
  store_url: string;
  recommended_update_message: string;
  forced_update_message: string;
  status: AppVersionStatus;
  updated_at: string;
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
const VALID_ADMIN_STATUSES = new Set<AdminStatus>(["active", "disabled"]);
const VALID_FEEDBACK_STATUSES = new Set<FeedbackStatus>(["pending", "processed", "ignored"]);
const LEGACY_FEEDBACK_STATUS_MAP: Record<string, FeedbackStatus> = {
  open: "pending",
  in_progress: "pending",
  closed: "processed",
};
const VALID_APP_VERSION_STATUSES = new Set<AppVersionStatus>(["enabled", "disabled"]);
const APP_VERSION_PLATFORMS: AppVersionPlatform[] = ["iOS", "Google"];
const APP_VERSION_CONFIG_PREFIX = "admin.app_version.";
const VERSION_PATTERN = /^\d+\.\d+\.\d+$/;
const DUMMY_PASSWORD_HASH =
  "pbkdf2-sha256$v1$100000$AAECAwQFBgcICQoLDA0ODw$n9d-PfgjYCpuBQORe6IZg6Op-rlL_-TOqIyWwG54xHI";

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

const SELECT_ADMIN_PERMISSIONS_SQL = `
  SELECT id, email, password_hash, role, status, created_at
  FROM admin_user
  WHERE (? IS NULL OR lower(email) LIKE '%' || ? || '%')
    AND (? IS NULL OR status = ?)
  ORDER BY created_at DESC
  LIMIT ? OFFSET ?
`;

const INSERT_ADMIN_PERMISSION_SQL = `
  INSERT INTO admin_user (id, email, password_hash, role, status, created_at)
  VALUES (?, ?, ?, ?, ?, ?)
`;

const UPDATE_ADMIN_PERMISSION_SQL = `
  UPDATE admin_user SET role = ?, status = ?
  WHERE id = ?
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

const ADMIN_USERS_FILTERED_SQL = `
  WITH accounts AS (
    SELECT 'user' AS account_type, u.id, u.email, NULL AS device_id, u.created_at,
      CASE WHEN u.deleted_at IS NULL THEN 'active' ELSE 'disabled' END AS status,
      COALESCE((
        SELECT ai.provider FROM auth_identity ai WHERE ai.user_id = u.id
        ORDER BY CASE ai.provider WHEN 'google' THEN 1 WHEN 'apple' THEN 2 ELSE 3 END LIMIT 1
      ), 'email') AS identity,
      COALESCE((
        SELECT sr.platform FROM scan_record sr
        WHERE sr.owner_type = 'user' AND sr.owner_id = u.id
        ORDER BY sr.created_at DESC LIMIT 1
      ), 'Unknown') AS platform
    FROM user u
    UNION ALL
    SELECT 'anonymous', a.id, NULL, a.device_id, a.created_at,
      CASE WHEN a.upgraded_user_id IS NULL THEN 'guest' ELSE 'upgraded' END,
      'anonymous',
      COALESCE((
        SELECT sr.platform FROM scan_record sr
        WHERE sr.owner_type = 'anonymous' AND sr.owner_id = a.id
        ORDER BY sr.created_at DESC LIMIT 1
      ), 'Unknown')
    FROM anonymous_account a
  )
  SELECT * FROM accounts
  WHERE (? IS NULL OR account_type = ?)
    AND (? IS NULL OR lower(id) LIKE '%' || ? || '%' OR lower(COALESCE(email, device_id, '')) LIKE '%' || ? || '%')
    AND (? IS NULL OR identity = ?)
    AND (? IS NULL OR lower(platform) = ?)
    AND (? IS NULL OR created_at >= ?)
    AND (? IS NULL OR created_at <= ?)
`;

const SELECT_ADMIN_USERS_SQL = `${ADMIN_USERS_FILTERED_SQL}
  ORDER BY created_at DESC
  LIMIT ? OFFSET ?
`;

const COUNT_ADMIN_USERS_SQL = `SELECT COUNT(*) AS total FROM (${ADMIN_USERS_FILTERED_SQL})`;

const SELECT_INSTALLATION_SOURCES_SQL = `
  SELECT 'user' AS install_type, id AS uid, 'iOS' AS platform,
    'Unknown' AS country, 'production' AS environment, created_at
  FROM user
  WHERE deleted_at IS NULL
  UNION ALL
  SELECT 'anonymous' AS install_type, id AS uid, 'iOS' AS platform,
    'Unknown' AS country, 'production' AS environment, created_at
  FROM anonymous_account
  ORDER BY created_at ASC
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

const SELECT_SCAN_RECORDS_SQL = `
  SELECT id, owner_type, owner_id, image_url, filename, platform, app_version,
    device_model, os_version, recognition_status, user_confirmation_status,
    modified_result, system_result, user_result, candidates, created_at
  FROM scan_record
  WHERE (? IS NULL OR lower(owner_id) LIKE '%' || ? || '%')
    AND (? IS NULL OR lower(platform) = ?)
    AND (? IS NULL OR lower(app_version) = ?)
    AND (? IS NULL OR recognition_status = ?)
    AND (? IS NULL OR user_confirmation_status = ?)
    AND (? IS NULL OR modified_result = ?)
    AND (? IS NULL OR created_at >= ?)
    AND (? IS NULL OR created_at <= ?)
  ORDER BY created_at DESC
  LIMIT ? OFFSET ?
`;

const COUNT_SCAN_RECORDS_SQL = `
  SELECT COUNT(*) AS total
  FROM scan_record
  WHERE (? IS NULL OR lower(owner_id) LIKE '%' || ? || '%')
    AND (? IS NULL OR lower(platform) = ?)
    AND (? IS NULL OR lower(app_version) = ?)
    AND (? IS NULL OR recognition_status = ?)
    AND (? IS NULL OR user_confirmation_status = ?)
    AND (? IS NULL OR modified_result = ?)
    AND (? IS NULL OR created_at >= ?)
    AND (? IS NULL OR created_at <= ?)
`;

const SELECT_SCAN_RECORD_BY_ID_SQL = `
  SELECT id, owner_type, owner_id, image_url, filename, platform, app_version,
    device_model, os_version, recognition_status, user_confirmation_status,
    modified_result, system_result, user_result, candidates, created_at
  FROM scan_record
  WHERE id = ?
  LIMIT 1
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
  const sessionId = createId();
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

adminRoutes.get("/price-sync", async (c) => {
  const status = await getJustTcgPriceSyncStatus(c.env);
  return c.json({ success: true, data: status });
});

adminRoutes.post("/price-sync/run", async (c) => {
  if (c.get("admin").role !== "super_admin") {
    return c.json(FORBIDDEN_RESPONSE, 403);
  }
  const status = await runJustTcgPriceSync(c.env, { force: true });
  if (status.status === "blocked" || status.status === "failed") {
    return c.json({
      success: false,
      error: {
        code: status.status === "blocked"
          ? "PRICE_SYNC_NOT_CONFIGURED"
          : "PRICE_SYNC_FAILED",
        message: status.last_error ?? "Price synchronization failed.",
      },
      data: status,
    }, 503);
  }
  return c.json({ success: true, data: status });
});

adminRoutes.get("/analytics/installations", async (c) => {
  const page = readPositiveInt(c.req.query("page"), 1);
  const pageSize = Math.min(readPositiveInt(c.req.query("page_size"), 20), 100);
  const dateFrom = readDateOnly(c.req.query("date_from"));
  const dateTo = readDateOnly(c.req.query("date_to"));
  const platform = normalizeQuery(c.req.query("platform"));
  const country = normalizeQuery(c.req.query("country"));
  const environment = normalizeQuery(c.req.query("environment"));
  const offset = (page - 1) * pageSize;

  const { results = [] } = await c.env.DB.prepare(SELECT_INSTALLATION_SOURCES_SQL)
    .all<InstallationSourceRow>();
  const installs = results
    .map(toInstallationRecord)
    .filter((item) => isWithinDateRange(item.date, dateFrom, dateTo))
    .filter((item) => !platform || item.platform.toLowerCase() === platform)
    .filter((item) => !country || item.country.toLowerCase() === country)
    .filter((item) => !environment || item.environment.toLowerCase() === environment);
  const trend = buildInstallationTrend(installs, dateFrom, dateTo);
  const rows = buildInstallationRows(installs);

  return c.json({
    success: true,
    data: {
      summary: {
        total_installations: installs.length,
        countries: new Set(installs.map((item) => item.country)).size,
        platforms: new Set(installs.map((item) => item.platform)).size,
      },
      trend,
      rows: rows.slice(offset, offset + pageSize),
      page,
      page_size: pageSize,
    },
  });
});

adminRoutes.get("/users", async (c) => {
  const page = readPositiveInt(c.req.query("page"), 1);
  const pageSize = Math.min(readPositiveInt(c.req.query("page_size"), 20), 100);
  const type = readUserType(c.req.query("type"));
  const q = normalizeQuery(c.req.query("q"));
  const identity = normalizeQuery(c.req.query("identity"));
  const platform = normalizeQuery(c.req.query("platform"));
  const dateFrom = readDateBoundary(c.req.query("date_from"), false);
  const dateTo = readDateBoundary(c.req.query("date_to"), true);
  if (dateFrom === "invalid" || dateTo === "invalid") {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }
  const offset = (page - 1) * pageSize;
  const filterBindings = [
    type, type, q, q, q, identity, identity, platform, platform,
    dateFrom, dateFrom, dateTo, dateTo,
  ] as const;
  const [{ results = [] }, count] = await Promise.all([
    c.env.DB.prepare(SELECT_ADMIN_USERS_SQL)
      .bind(...filterBindings, pageSize, offset)
      .all(),
    c.env.DB.prepare(COUNT_ADMIN_USERS_SQL)
      .bind(...filterBindings)
      .first<{ total: number }>(),
  ]);

  return c.json({
    success: true,
    data: { items: results, total: count?.total ?? 0, page, page_size: pageSize },
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
    .bind(null, null, pageSize, offset)
    .all<FeedbackTicketRow>();
  const items = results
    .map(toAdminFeedbackTicket)
    .filter((item) => !status || item.status === status);

  return c.json({ success: true, data: { items, page, page_size: pageSize } });
});

adminRoutes.get("/feedbacks/:ticketId", async (c) => {
  const row = await c.env.DB.prepare(SELECT_FEEDBACK_BY_ID_SQL)
    .bind(c.req.param("ticketId"))
    .first<FeedbackTicketRow>();
  return row ? c.json({ success: true, data: toAdminFeedbackTicket(row) }) : c.json(NOT_FOUND_RESPONSE, 404);
});

adminRoutes.patch("/feedbacks/:ticketId/status", async (c) => {
  const input = await readJsonObject(c.req);
  const status = readFeedbackStatus(input.status);
  if (!status) return c.json(VALIDATION_ERROR_RESPONSE, 422);

  const id = c.req.param("ticketId");
  await c.env.DB.prepare(UPDATE_FEEDBACK_STATUS_SQL)
    .bind(status, new Date().toISOString(), id)
    .run();
  const row = await c.env.DB.prepare(SELECT_FEEDBACK_BY_ID_SQL).bind(id).first<FeedbackTicketRow>();

  return row ? c.json({ success: true, data: toAdminFeedbackTicket(row) }) : c.json(NOT_FOUND_RESPONSE, 404);
});

adminRoutes.get("/scans", async (c) => {
  const page = readPositiveInt(c.req.query("page"), 1);
  const pageSize = Math.min(readPositiveInt(c.req.query("page_size"), 20), 100);
  const uid = normalizeQuery(c.req.query("uid"));
  const platform = normalizeQuery(c.req.query("platform"));
  const appVersion = normalizeQuery(c.req.query("app_version"));
  const recognitionStatus = normalizeQuery(c.req.query("recognition_status"));
  const confirmationStatus = normalizeQuery(c.req.query("user_confirmation_status"));
  const modifiedResult = readBooleanQuery(c.req.query("modified_result"));
  const dateFrom = readDateBoundary(c.req.query("date_from"), false);
  const dateTo = readDateBoundary(c.req.query("date_to"), true);
  if (dateFrom === "invalid" || dateTo === "invalid") {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }
  const modifiedResultValue = modifiedResult === null ? null : modifiedResult ? 1 : 0;
  const offset = (page - 1) * pageSize;
  const filterBindings = [
      uid,
      uid,
      platform,
      platform,
      appVersion,
      appVersion,
      recognitionStatus,
      recognitionStatus,
      confirmationStatus,
      confirmationStatus,
      modifiedResultValue,
      modifiedResultValue,
      dateFrom,
      dateFrom,
      dateTo,
      dateTo,
  ] as const;
  const [{ results = [] }, count] = await Promise.all([
    c.env.DB.prepare(SELECT_SCAN_RECORDS_SQL)
      .bind(
        ...filterBindings,
      pageSize,
      offset,
      )
      .all<ScanRecordRow>(),
    c.env.DB.prepare(COUNT_SCAN_RECORDS_SQL)
      .bind(...filterBindings)
      .first<{ total: number }>(),
  ]);
  const items = results.map(toScanListItem);

  return c.json({
    success: true,
    data: { items, page, page_size: pageSize, total: count?.total ?? 0 },
  });
});

adminRoutes.get("/scans/:scanId/image", async (c) => {
  const bucket = c.env.SCAN_IMAGES;
  if (!bucket) return c.json(INTERNAL_ERROR_RESPONSE, 503);
  const row = await c.env.DB.prepare(SELECT_SCAN_RECORD_BY_ID_SQL)
    .bind(c.req.param("scanId"))
    .first<ScanRecordRow>();
  if (!row?.image_url) return c.json(NOT_FOUND_RESPONSE, 404);
  const object = await bucket.get(row.image_url);
  if (!object) return c.json(NOT_FOUND_RESPONSE, 404);
  const headers = new Headers({
    "Cache-Control": "private, no-store",
    "Content-Type": object.httpMetadata?.contentType ?? "application/octet-stream",
    "X-Content-Type-Options": "nosniff",
  });
  return new Response(object.body, { headers });
});

adminRoutes.get("/scans/:scanId", async (c) => {
  const row = await c.env.DB.prepare(SELECT_SCAN_RECORD_BY_ID_SQL)
    .bind(c.req.param("scanId"))
    .first<ScanRecordRow>();
  return row ? c.json({ success: true, data: toScanDetail(row) }) : c.json(NOT_FOUND_RESPONSE, 404);
});

adminRoutes.get("/permissions", async (c) => {
  const page = readPositiveInt(c.req.query("page"), 1);
  const pageSize = Math.min(readPositiveInt(c.req.query("page_size"), 20), 100);
  const q = normalizeQuery(c.req.query("q") ?? c.req.query("email"));
  const status = readAdminStatus(c.req.query("status"));
  const offset = (page - 1) * pageSize;
  const { results = [] } = await c.env.DB.prepare(SELECT_ADMIN_PERMISSIONS_SQL)
    .bind(q, q, status, status, pageSize, offset)
    .all<AdminUserRow>();

  return c.json({
    success: true,
    data: { items: results.map(toPermissionRecord), page, page_size: pageSize },
  });
});

adminRoutes.post("/permissions", async (c) => {
  if (c.get("admin").role !== "super_admin") {
    return c.json(FORBIDDEN_RESPONSE, 403);
  }

  const input = await readJsonObject(c.req);
  const email = normalizeEmail(input.email);
  const role = readAdminRole(input.role) ?? "operator";
  const status = readAdminStatus(input.status) ?? "active";
  const password = readRequiredString(input.password);
  if (!email || !isValidEmail(email) || !password) {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }

  const id = createId();
  const createdAt = new Date().toISOString();
  await c.env.DB.prepare(INSERT_ADMIN_PERMISSION_SQL)
    .bind(id, email, await hashPassword(password), role, status, createdAt)
    .run();
  const row = await c.env.DB.prepare(SELECT_ADMIN_BY_ID_SQL).bind(id).first<AdminUserRow>();

  return c.json({ success: true, data: row ? toPermissionRecord(row) : null });
});

adminRoutes.patch("/permissions/:adminId", async (c) => {
  if (c.get("admin").role !== "super_admin") {
    return c.json(FORBIDDEN_RESPONSE, 403);
  }

  const id = c.req.param("adminId");
  const existing = await c.env.DB.prepare(SELECT_ADMIN_BY_ID_SQL).bind(id).first<AdminUserRow>();
  if (!existing) return c.json(NOT_FOUND_RESPONSE, 404);

  const input = await readJsonObject(c.req);
  const role = readAdminRole(input.role) ?? (existing.role as AdminRole);
  const status = readAdminStatus(input.status) ?? existing.status;
  await c.env.DB.prepare(UPDATE_ADMIN_PERMISSION_SQL).bind(role, status, id).run();
  const row = await c.env.DB.prepare(SELECT_ADMIN_BY_ID_SQL).bind(id).first<AdminUserRow>();

  return row ? c.json({ success: true, data: toPermissionRecord(row) }) : c.json(NOT_FOUND_RESPONSE, 404);
});

adminRoutes.get("/app-versions", async (c) => {
  const { results = [] } = await c.env.DB.prepare(SELECT_APP_CONFIG_SQL).all<AppConfigRow>();
  return c.json({ success: true, data: { items: buildAppVersionRecords(results) } });
});

adminRoutes.patch("/app-versions/:platform", async (c) => {
  const platform = readAppVersionPlatform(c.req.param("platform"));
  if (!platform) return c.json(NOT_FOUND_RESPONSE, 404);

  const input = await readJsonObject(c.req);
  const minSupportedVersion = readRequiredString(input.min_supported_version);
  const recommendedVersion = readRequiredString(input.recommended_version);
  const forceUpdate = input.force_update === true;
  const storeUrl = typeof input.store_url === "string" ? input.store_url.trim() : "";
  const status = readAppVersionStatus(input.status) ?? "enabled";
  if (
    !minSupportedVersion ||
    !recommendedVersion ||
    !VERSION_PATTERN.test(minSupportedVersion) ||
    !VERSION_PATTERN.test(recommendedVersion)
  ) {
    return c.json(VALIDATION_ERROR_RESPONSE, 422);
  }

  const now = new Date().toISOString();
  const record: AppVersionRecord = {
    platform,
    min_supported_version: minSupportedVersion,
    recommended_version: recommendedVersion,
    force_update: forceUpdate,
    store_url: storeUrl,
    recommended_update_message: typeof input.recommended_update_message === "string"
      ? input.recommended_update_message
      : "",
    forced_update_message: typeof input.forced_update_message === "string"
      ? input.forced_update_message
      : "",
    status,
    updated_at: now,
  };
  await c.env.DB.prepare(UPSERT_APP_CONFIG_SQL)
    .bind(appVersionConfigKey(platform), JSON.stringify(record), c.get("admin").admin_id, now)
    .run();

  return c.json({ success: true, data: record });
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

  const id = createId();
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

  const id = createId();
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

  const id = createId();
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

function readAdminRole(value: unknown): AdminRole | null {
  return typeof value === "string" && isAdminRole(value) ? value : null;
}

function readAdminStatus(value: unknown): AdminStatus | null {
  return typeof value === "string" && VALID_ADMIN_STATUSES.has(value as AdminStatus)
    ? (value as AdminStatus)
    : null;
}

function readUserType(value: string | undefined): "user" | "anonymous" | null {
  return value === "user" || value === "anonymous" ? value : null;
}

function readFeedbackStatus(value: unknown): FeedbackStatus | null {
  if (typeof value !== "string") return null;
  if (VALID_FEEDBACK_STATUSES.has(value as FeedbackStatus)) return value as FeedbackStatus;
  return LEGACY_FEEDBACK_STATUS_MAP[value] ?? null;
}

function readBooleanFilter(value: string | undefined): number | null {
  if (value === "true") return 1;
  if (value === "false") return 0;
  return null;
}

function readBooleanQuery(value: string | undefined): boolean | null {
  if (value === "true") return true;
  if (value === "false") return false;
  return null;
}

function readDateOnly(value: string | undefined): string | null {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  return Number.isNaN(Date.parse(`${value}T00:00:00.000Z`)) ? null : value;
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

function toInstallationRecord(row: InstallationSourceRow) {
  return {
    uid: row.uid,
    install_type: row.install_type,
    platform: row.platform || "Unknown",
    country: row.country || "Unknown",
    environment: row.environment || "production",
    date: row.created_at.slice(0, 10),
    created_at: row.created_at,
  };
}

function isWithinDateRange(date: string, dateFrom: string | null, dateTo: string | null): boolean {
  if (dateFrom && date < dateFrom) return false;
  if (dateTo && date > dateTo) return false;
  return true;
}

function buildInstallationTrend(
  installs: Array<ReturnType<typeof toInstallationRecord>>,
  dateFrom: string | null,
  dateTo: string | null,
) {
  const dates = dateFrom && dateTo ? enumerateDates(dateFrom, dateTo) : [...new Set(installs.map((item) => item.date))].sort();
  const totals = new Map<string, number>();
  for (const item of installs) {
    totals.set(item.date, (totals.get(item.date) ?? 0) + 1);
  }
  return dates.map((date) => ({ date, total: totals.get(date) ?? 0 }));
}

function buildInstallationRows(installs: Array<ReturnType<typeof toInstallationRecord>>) {
  const groups = new Map<string, {
    date: string;
    country: string;
    platform: string;
    environment: string;
    installs: number;
  }>();

  for (const item of installs) {
    const key = [item.date, item.country, item.platform, item.environment].join("|");
    const existing = groups.get(key);
    if (existing) {
      existing.installs += 1;
    } else {
      groups.set(key, {
        date: item.date,
        country: item.country,
        platform: item.platform,
        environment: item.environment,
        installs: 1,
      });
    }
  }

  return [...groups.values()].sort((left, right) => left.date.localeCompare(right.date));
}

function enumerateDates(dateFrom: string, dateTo: string): string[] {
  const start = new Date(`${dateFrom}T00:00:00.000Z`);
  const end = new Date(`${dateTo}T00:00:00.000Z`);
  if (start.getTime() > end.getTime()) return [];
  const dates: string[] = [];
  for (const current = start; current.getTime() <= end.getTime(); current.setUTCDate(current.getUTCDate() + 1)) {
    dates.push(current.toISOString().slice(0, 10));
  }
  return dates;
}

function normalizeFeedbackStorageStatus(value: FeedbackStorageStatus): FeedbackStatus {
  return VALID_FEEDBACK_STATUSES.has(value as FeedbackStatus)
    ? (value as FeedbackStatus)
    : LEGACY_FEEDBACK_STATUS_MAP[value] ?? "pending";
}

function toAdminFeedbackTicket(row: FeedbackTicketRow) {
  const types = parseJsonArray(row.types);
  const functions = parseJsonArray(row.functions);
  return {
    ...row,
    status: normalizeFeedbackStorageStatus(row.status),
    issue_type: types[0] ?? "其他",
    module: functions[0] ?? "App",
    uid: row.id,
    platform: "iOS",
    app_version: "1.9.0",
    device_model: "Unknown",
    os_version: "Unknown",
    environment: "production",
  };
}

function toScanListItem(row: ScanRecordRow) {
  return {
    scan_id: row.id,
    image_url: row.image_url
      ? `/scans/${encodeURIComponent(row.id)}/image`
      : "",
    uid: row.owner_id,
    platform: row.platform,
    app_version: row.app_version,
    scan_time: row.created_at,
    recognition_status: row.recognition_status,
    user_confirmation_status: row.user_confirmation_status,
    modified_result: row.modified_result === 1,
  };
}

function readDateBoundary(
  value: string | undefined,
  endOfDay: boolean,
): string | null | "invalid" {
  const normalized = value?.trim();
  if (!normalized) return null;
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(normalized);
  const date = new Date(dateOnly
    ? `${normalized}T${endOfDay ? "23:59:59.999" : "00:00:00.000"}Z`
    : normalized);
  return Number.isNaN(date.getTime()) ? "invalid" : date.toISOString();
}

function toScanDetail(row: ScanRecordRow) {
  return {
    ...toScanListItem(row),
    device_model: row.device_model ?? "Unknown",
    os_version: row.os_version ?? "Unknown",
    system_result: parseJsonObject(row.system_result),
    user_result: parseJsonObject(row.user_result),
    candidates: parseJsonObjectArray(row.candidates),
  };
}

function toPermissionRecord(row: AdminUserRow) {
  return {
    id: row.id,
    email: row.email,
    role: row.role,
    status: row.status,
    permission_status: row.status,
    created_at: row.created_at,
    updated_at: row.created_at,
  };
}

function readAppVersionPlatform(value: string): AppVersionPlatform | null {
  const normalized = value.trim().toLowerCase();
  if (normalized === "ios") return "iOS";
  if (normalized === "google" || normalized === "android") return "Google";
  return null;
}

function readAppVersionStatus(value: unknown): AppVersionStatus | null {
  return typeof value === "string" && VALID_APP_VERSION_STATUSES.has(value as AppVersionStatus)
    ? (value as AppVersionStatus)
    : null;
}

function appVersionConfigKey(platform: AppVersionPlatform): string {
  return `${APP_VERSION_CONFIG_PREFIX}${platform.toLowerCase()}`;
}

function buildAppVersionRecords(configs: AppConfigRow[]): AppVersionRecord[] {
  const records = new Map<AppVersionPlatform, AppVersionRecord>(
    APP_VERSION_PLATFORMS.map((platform) => [platform, defaultAppVersionRecord(platform)]),
  );

  for (const config of configs) {
    if (!config.key.startsWith(APP_VERSION_CONFIG_PREFIX)) continue;
    const parsed = parseAppVersionRecord(config.value, config.updated_at);
    if (parsed) records.set(parsed.platform, parsed);
  }

  return APP_VERSION_PLATFORMS.map((platform) => records.get(platform) ?? defaultAppVersionRecord(platform));
}

function defaultAppVersionRecord(platform: AppVersionPlatform): AppVersionRecord {
  return {
    platform,
    min_supported_version: "1.0.0",
    recommended_version: "1.9.0",
    force_update: false,
    store_url: "",
    recommended_update_message: "优化首页加载速度",
    forced_update_message: "请更新至最新版本后继续使用。",
    status: "disabled",
    updated_at: "2025-04-30T00:00:00.000Z",
  };
}

function parseAppVersionRecord(value: string, updatedAt: string): AppVersionRecord | null {
  try {
    const parsed = JSON.parse(value);
    if (!isRecord(parsed)) return null;
    const platform = typeof parsed.platform === "string" ? readAppVersionPlatform(parsed.platform) : null;
    const minSupportedVersion = readRequiredString(parsed.min_supported_version);
    const recommendedVersion = readRequiredString(parsed.recommended_version);
    const status = readAppVersionStatus(parsed.status) ?? "enabled";
    if (!platform || !minSupportedVersion || !recommendedVersion) return null;
    return {
      platform,
      min_supported_version: minSupportedVersion,
      recommended_version: recommendedVersion,
      force_update: parsed.force_update === true,
      store_url: typeof parsed.store_url === "string" ? parsed.store_url.trim() : "",
      recommended_update_message: typeof parsed.recommended_update_message === "string"
        ? parsed.recommended_update_message
        : "",
      forced_update_message: typeof parsed.forced_update_message === "string"
        ? parsed.forced_update_message
        : "",
      status,
      updated_at: typeof parsed.updated_at === "string" ? parsed.updated_at : updatedAt,
    };
  } catch {
    return null;
  }
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

function parseJsonArray(value: string): string[] {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.map(String) : [];
  } catch {
    return [];
  }
}

function parseJsonObject(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value);
    return isRecord(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function parseJsonObjectArray(value: string): Array<Record<string, unknown>> {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.filter(isRecord) : [];
  } catch {
    return [];
  }
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
