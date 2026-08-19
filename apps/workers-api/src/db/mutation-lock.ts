const MUTATION_LOCK_SQL = `
  INSERT INTO mutation_lock (lock_key)
  VALUES (?)
  ON CONFLICT(lock_key) DO UPDATE SET lock_key = excluded.lock_key
`;
const MUTATION_LOCK_SCOPE_PATTERN = /^[a-z][a-z0-9-]{0,62}$/;
const MUTATION_LOCK_KEY_PATTERN = /^[a-z][a-z0-9-]{0,62}(?::[0-9a-f]{64})?$/;

export async function mutationLockKey(scope: string, identity?: string): Promise<string> {
  if (!MUTATION_LOCK_SCOPE_PATTERN.test(scope)) {
    throw new Error("Invalid mutation lock scope");
  }
  if (identity === undefined) return scope;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(identity));
  const hex = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0")).join("");
  return `${scope}:${hex}`;
}

export async function runWithMutationLock<T = Record<string, unknown>>(
  db: D1Database,
  lockKey: string,
  guardedStatement: D1PreparedStatement,
): Promise<D1Result<T>> {
  const [guardedResult] = await runWithMutationLockStatements<T>(
    db,
    lockKey,
    [guardedStatement],
  );
  return guardedResult!;
}

export async function runWithMutationLockStatements<T = Record<string, unknown>>(
  db: D1Database,
  lockKey: string,
  guardedStatements: D1PreparedStatement[],
): Promise<D1Result<T>[]> {
  return runWithMutationLocks(db, [lockKey], guardedStatements);
}

export async function runWithMutationLocks<T = Record<string, unknown>>(
  db: D1Database,
  lockKeys: string[],
  guardedStatements: D1PreparedStatement[],
): Promise<D1Result<T>[]> {
  const orderedLockKeys = [...new Set(lockKeys)].sort();
  if (
    orderedLockKeys.length === 0 ||
    orderedLockKeys.some((lockKey) => !MUTATION_LOCK_KEY_PATTERN.test(lockKey))
  ) {
    throw new Error("Invalid mutation lock key");
  }
  if (guardedStatements.length === 0) {
    throw new Error("Mutation lock requires at least one guarded statement");
  }
  const results = await db.batch<T>([
    ...orderedLockKeys.map((lockKey) =>
      db.prepare(MUTATION_LOCK_SQL).bind(lockKey)),
    ...guardedStatements,
  ]);
  const lockResults = results.slice(0, orderedLockKeys.length);
  const guardedResults = results.slice(orderedLockKeys.length);
  if (
    lockResults.length !== orderedLockKeys.length ||
    lockResults.some((result) => !result.success) ||
    guardedResults.length !== guardedStatements.length ||
    guardedResults.some((result) => !result.success)
  ) {
    throw new Error("Mutation lock transaction did not complete");
  }
  return guardedResults;
}

export function ownerCardMutationLockKey(
  owner: { owner_type: string; owner_id: string },
  cardRef: string,
): Promise<string> {
  return mutationLockKey(
    "owner-card",
    `${owner.owner_type}:${owner.owner_id}:${cardRef}`,
  );
}
