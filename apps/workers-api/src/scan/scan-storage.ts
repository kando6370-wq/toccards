import type { Env } from "../env";

type ScanImageRow = { image_url: string | null };

const SELECT_OWNER_SCAN_IMAGES_SQL = `
  SELECT image_url
  FROM scan_record
  WHERE owner_type = ? AND owner_id = ? AND image_url IS NOT NULL
`;

const DELETE_OWNER_SCAN_RECORDS_SQL = `
  DELETE FROM scan_record
  WHERE owner_type = ? AND owner_id = ?
`;

export async function deleteOwnerScanData(
  env: Env,
  ownerType: "anonymous" | "user",
  ownerId: string,
): Promise<void> {
  const { results = [] } = await env.DB.prepare(SELECT_OWNER_SCAN_IMAGES_SQL)
    .bind(ownerType, ownerId)
    .all<ScanImageRow>();
  const keys = results
    .map((row) => row.image_url)
    .filter((key): key is string => typeof key === "string" && key.length > 0);
  if (keys.length > 0) {
    if (!env.SCAN_IMAGES) throw new Error("SCAN_IMAGES binding is unavailable.");
    for (var offset = 0; offset < keys.length; offset += 1000) {
      await env.SCAN_IMAGES.delete(keys.slice(offset, offset + 1000));
    }
  }
  await env.DB.prepare(DELETE_OWNER_SCAN_RECORDS_SQL)
    .bind(ownerType, ownerId)
    .run();
}
