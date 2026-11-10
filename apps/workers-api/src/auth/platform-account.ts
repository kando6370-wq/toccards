import type { Database } from "../db/database";

export type AuthPlatform = "ios" | "android";

export type PlatformAccountRow = {
  id: string;
  user_id: string;
  platform: AuthPlatform;
  status: "active" | "disabled" | "deleting" | "deleted";
};

const SELECT_LATEST_PLATFORM_ACCOUNT_SQL = `
  SELECT id, user_id, platform, status
  FROM platform_account
  WHERE user_id = ? AND platform = ?
  ORDER BY created_at DESC, id DESC
  LIMIT 1
`;

export async function findLatestPlatformAccount(
  db: Database,
  userId: string,
  platform: AuthPlatform,
): Promise<PlatformAccountRow | null> {
  return db.prepare(SELECT_LATEST_PLATFORM_ACCOUNT_SQL)
    .bind(userId, platform)
    .first<PlatformAccountRow>();
}
