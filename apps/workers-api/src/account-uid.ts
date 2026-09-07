import { runWithMutationLock } from "./db/mutation-lock";

type AccountUidRow = {
  uid: number;
};

const RESERVE_ACCOUNT_UID_SQL = `
  INSERT INTO account_uid (uid, created_at)
  SELECT COALESCE(MAX(uid), 99999) + 1, ?
  FROM account_uid
  RETURNING uid
`;

export async function reserveAccountUid(
  db: D1Database,
  createdAt: string,
): Promise<string> {
  const result = await runWithMutationLock<AccountUidRow>(
    db,
    "account-uid",
    db.prepare(RESERVE_ACCOUNT_UID_SQL).bind(createdAt),
  );
  const row = result.results[0];

  if (!row || !Number.isSafeInteger(row.uid) || row.uid < 100000) {
    throw new Error("Failed to reserve account UID.");
  }

  return String(row.uid);
}
