import type { Env } from "../env";

type ExpiredScanImage = {
  id: string;
  image_url: string;
};

const MAX_IMAGES_PER_RUN = 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

const SELECT_EXPIRED_SCAN_IMAGES_SQL = `
SELECT id, image_url
FROM scan_record
WHERE image_url IS NOT NULL AND created_at < ?
ORDER BY created_at ASC
LIMIT ${MAX_IMAGES_PER_RUN}
`;

const CLEAR_SCAN_IMAGE_SQL = `
UPDATE scan_record
SET image_url = NULL
WHERE id = ? AND image_url = ?
`;

export async function purgeExpiredScanImages(
  env: Env,
  now = new Date(),
): Promise<number> {
  const retentionDays = parseRetentionDays(env.SCAN_IMAGE_RETENTION_DAYS);
  if (!env.SCAN_IMAGES) throw new Error("SCAN_IMAGES binding is unavailable.");

  const cutoff = new Date(now.getTime() - retentionDays * DAY_MS).toISOString();
  const { results = [] } = await env.DB.prepare(SELECT_EXPIRED_SCAN_IMAGES_SQL)
    .bind(cutoff)
    .all<ExpiredScanImage>();
  const images = results.filter(isExpiredScanImage);
  if (images.length === 0) return 0;

  await env.SCAN_IMAGES.delete(images.map((image) => image.image_url));
  const updates = images.map((image) =>
    env.DB.prepare(CLEAR_SCAN_IMAGE_SQL).bind(image.id, image.image_url)
  );
  const updateResults = await env.DB.batch(updates);
  if (updateResults.some((result) => result.meta.changes !== 1)) {
    throw new Error("Failed to clear one or more expired scan image pointers.");
  }

  return images.length;
}

function parseRetentionDays(value: string | undefined): number {
  if (!value || !/^\d+$/.test(value)) {
    throw new Error("SCAN_IMAGE_RETENTION_DAYS must be a positive integer.");
  }
  const days = Number(value);
  if (!Number.isSafeInteger(days) || days < 1) {
    throw new Error("SCAN_IMAGE_RETENTION_DAYS must be a positive integer.");
  }
  return days;
}

function isExpiredScanImage(value: ExpiredScanImage): boolean {
  return typeof value.id === "string" &&
    value.id.length > 0 &&
    typeof value.image_url === "string" &&
    value.image_url.length > 0;
}
