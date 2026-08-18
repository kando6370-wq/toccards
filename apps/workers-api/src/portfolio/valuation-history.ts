import type { AuthenticatedOwner } from "../owner-auth";
import { cardImageUrl } from "../card-image-url";
import {
  loadPriceHistoryBySeries,
  loadPublishedPriceRows,
  pointsWithPublishedSnapshot,
  shiftDate,
} from "../data-source/postgres-price-store";

type ItemEventRow = {
  id: string;
  item_id: string;
  folder_id: string;
  card_ref: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  price_series_id: number | null;
  quantity: number;
  event_type: "upsert" | "delete";
  effective_at: string;
};

export type SkuRow = {
  series_id: number;
  source_code: string;
  source_record_id: string;
  metric_code: string;
  product_id: string;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  grader_code: string;
  grade_min_x10: number | null;
  grade_max_x10: number | null;
  price_history: string;
  change_30d_percent: number | null;
};

export type MatchedPrice = {
  row: SkuRow;
  history: string;
  change30dPercent: number | null;
};

type PricePoint = { date: string; price: number };

export type CardRow = {
  product_id: string;
  game: string | null;
  name: string | null;
  set_name: string | null;
  number: string | null;
  rarity: string | null;
};

export type MostValuableItem = {
  item_id: string;
  card_ref: string;
  name: string;
  set_name: string;
  card_number: string;
  finish: string | null;
  image_url: string | null;
  price_usd: number;
  previous_30d_price_usd: number | null;
  increase_percent: number | null;
};

export type FolderValuationHistory = {
  folder_id: string;
  item_count: number;
  market_price_status: "available" | "missing";
  current_value_usd: number;
  series: Array<{ date: string; value_usd: number }>;
  most_valuable: MostValuableItem[];
};

const SELECT_EVENTS_SQL = `
SELECT id, item_id, folder_id, card_ref, grader, condition, grade, language,
  finish, price_series_id, quantity, event_type, effective_at
FROM collection_item_event
WHERE owner_type = ? AND owner_id = ?
ORDER BY effective_at ASC, id ASC
LIMIT 10001
`;

export async function loadValuationHistory(
  db: D1Database,
  owner: AuthenticatedOwner,
  folderIds: string[],
  days: number,
  now = new Date(),
): Promise<FolderValuationHistory[]> {
  const result = await db
    .prepare(SELECT_EVENTS_SQL)
    .bind(owner.owner_type, owner.owner_id)
    .all<ItemEventRow>();
  const events = result.results ?? [];
  if (events.length > 10000) {
    throw new Error("Portfolio valuation query exceeded 10000 events");
  }
  const endDate = dateKeys(now, 0)[0]!;
  const skus = await loadSkus(
    db,
    [...new Set(events.map((event) => event.card_ref))],
    shiftDate(endDate, -Math.max(days, 1) - 30),
    endDate,
  );
  const cards = await loadCards(db, [...new Set(events.map((event) => event.card_ref))]);
  const skusByProduct = groupSkus(skus);
  const cardsByProduct = new Map(cards.map((card) => [card.product_id, card]));
  const eventsByItem = groupEvents(events);
  const dates = dateKeys(now, days);

  return folderIds.map((folderId) => {
    const series = dates.map((date) => ({
      date,
      value_usd: valueOnDate(eventsByItem, skusByProduct, folderId, date),
    }));
    const currentItems = [...eventsByItem.values()]
      .map((itemEvents) => stateOnDate(itemEvents, endDate))
      .filter((state): state is ItemEventRow =>
        state !== null
        && state.event_type !== "delete"
        && state.folder_id === folderId
      );
    const hasMarketPrice = currentItems.some((state) => {
      const matched = matchingPrice(state, skusByProduct.get(state.card_ref) ?? []);
      return matched !== null && priceOnDate(matched.history, endDate) !== null;
    });
    return {
      folder_id: folderId,
      item_count: currentItems.length,
      market_price_status: hasMarketPrice ? "available" : "missing",
      current_value_usd: series.at(-1)?.value_usd ?? 0,
      series,
      most_valuable: mostValuableItems(
        eventsByItem,
        skusByProduct,
        cardsByProduct,
        folderId,
        dates.at(-1)!,
      ),
    };
  });
}

function mostValuableItems(
  eventsByItem: Map<string, ItemEventRow[]>,
  skusByProduct: Map<string, SkuRow[]>,
  cardsByProduct: Map<string, CardRow>,
  folderId: string,
  date: string,
): MostValuableItem[] {
  const baselineDate = shiftDate(date, -30);
  const items: Array<{
    item: MostValuableItem;
    unitPrice: number;
    addedAt: string;
  }> = [];
  for (const events of eventsByItem.values()) {
    const state = stateOnDate(events, date);
    if (!state || state.event_type === "delete" || state.folder_id !== folderId) continue;
    const matched = matchingPrice(state, skusByProduct.get(state.card_ref) ?? []);
    const card = cardsByProduct.get(state.card_ref);
    const current = matched ? priceOnDate(matched.history, date) : null;
    if (!matched || !card || current === null) continue;
    const previous = priceOnDate(matched.history, baselineDate);
    items.push({
      item: {
        item_id: state.item_id,
        card_ref: state.card_ref,
        name: card.name ?? state.card_ref,
        set_name: card.set_name ?? "",
        card_number: card.number ?? "",
        finish: state.finish,
        image_url: cardImageUrl(state.card_ref, "thumbnail"),
        price_usd: roundMoney(current),
        previous_30d_price_usd: previous === null ? null : roundMoney(previous),
        increase_percent:
          matched.change30dPercent !== null && Number.isFinite(matched.change30dPercent)
            ? matched.change30dPercent
            : null,
      },
      unitPrice: current,
      addedAt: events[0]!.effective_at,
    });
  }
  return items
    .sort((left, right) =>
      right.unitPrice - left.unitPrice
      || compareNullableNumberDesc(left.item.increase_percent, right.item.increase_percent)
      || right.addedAt.localeCompare(left.addedAt)
      || left.item.name.localeCompare(right.item.name)
      || left.item.item_id.localeCompare(right.item.item_id)
    )
    .slice(0, 3)
    .map(({ item }) => item);
}

function compareNullableNumberDesc(left: number | null, right: number | null): number {
  if (left === null) return right === null ? 0 : 1;
  if (right === null) return -1;
  return right - left;
}

function stateOnDate(events: ItemEventRow[], date: string): ItemEventRow | null {
  const endOfDay = `${date}T23:59:59.999Z`;
  return events.filter((event) => event.effective_at <= endOfDay).at(-1) ?? null;
}

function valueOnDate(
  eventsByItem: Map<string, ItemEventRow[]>,
  skusByProduct: Map<string, SkuRow[]>,
  folderId: string,
  date: string,
): number {
  let total = 0;
  for (const events of eventsByItem.values()) {
    const state = stateOnDate(events, date);
    if (!state || state.event_type === "delete" || state.folder_id !== folderId) {
      continue;
    }
    const matched = matchingPrice(state, skusByProduct.get(state.card_ref) ?? []);
    const price = matched ? priceOnDate(matched.history, date) : null;
    if (price !== null) total += price * state.quantity;
  }
  return roundMoney(total);
}

export function matchingPrice(
  event: Pick<
    ItemEventRow,
    "grader" | "condition" | "grade" | "language" | "finish" | "price_series_id"
  >,
  rows: SkuRow[],
): MatchedPrice | null {
  if (event.price_series_id !== null) {
    const row = rows.find((candidate) =>
      candidate.series_id === event.price_series_id
      && parsePriceHistory(candidate.price_history).length > 0
    );
    return row
      ? { row, history: row.price_history, change30dPercent: row.change_30d_percent }
      : null;
  }
  if (event.grader.toLowerCase() === "raw") {
    const row = matchingSku(event, rows);
    return row
      ? { row, history: row.price_history, change30dPercent: row.change_30d_percent }
      : null;
  }
  if (event.grade === null) return null;
  const language = normalizedOptionalQualifier(event.language);
  const finish = normalizedOptionalQualifier(event.finish);
  const candidates = rows
    .filter((row) => normalizedQualifier(row.grader_code) === normalizedQualifier(event.grader))
    .filter((row) => gradeMatches(event.grade!, row.grade_min_x10, row.grade_max_x10))
    .filter((row) => optionalQualifierMatches(language, row.language_code, row.language_name))
    .filter((row) => optionalQualifierMatches(finish, row.variant_code, row.variant_name))
    .filter((row) => parsePriceHistory(row.price_history).length > 0)
    .sort((left, right) =>
      ((left.grade_max_x10 ?? 100) - (left.grade_min_x10 ?? 0))
      - ((right.grade_max_x10 ?? 100) - (right.grade_min_x10 ?? 0))
      || qualifierRank(language, left.language_code, left.language_name)
      - qualifierRank(language, right.language_code, right.language_name)
      || qualifierRank(finish, left.variant_code, left.variant_name)
      - qualifierRank(finish, right.variant_code, right.variant_name)
      || compareNaturalQualifiers(left, right)
      || left.series_id - right.series_id
  );
  const row = candidates[0];
  return row
    ? { row, history: row.price_history, change30dPercent: row.change_30d_percent }
    : null;
}

export function matchingSku(
  event: Pick<ItemEventRow, "grader" | "condition" | "language" | "finish">,
  rows: SkuRow[],
): SkuRow | null {
  if (event.grader.toLowerCase() !== "raw") return null;
  const condition = normalizedQualifier(event.condition);
  const language = normalizedOptionalQualifier(event.language);
  const finish = normalizedOptionalQualifier(event.finish);
  return (
    rows
      .filter((row) => normalizedQualifier(row.grader_code) === "raw")
      .filter((row) => qualifierMatches(condition, row.condition_code, row.condition_name))
      .filter((row) => !language || qualifierMatches(language, row.language_code, row.language_name))
      .filter((row) => !finish || qualifierMatches(finish, row.variant_code, row.variant_name))
      .filter((row) => parsePriceHistory(row.price_history).length > 0)
      .sort((left, right) =>
        skuRank(left) - skuRank(right)
        || compareNaturalQualifiers(left, right)
        || left.series_id - right.series_id
      )[0] ??
    null
  );
}

function qualifierMatches(
  expected: string,
  code: string | null,
  name: string | null,
): boolean {
  if (!expected) return true;
  return [code, name].some((value) => normalizedQualifier(value) === expected);
}

function optionalQualifierMatches(
  expected: string,
  code: string | null,
  name: string | null,
): boolean {
  if (!expected) return true;
  const values = [code, name].map(normalizedQualifier).filter(Boolean);
  return values.length === 0 || values.includes(expected);
}

function qualifierRank(
  expected: string,
  code: string | null,
  name: string | null,
): number {
  if (!expected) return 0;
  return [code, name].some((value) => normalizedQualifier(value) === expected)
    ? 0
    : 1;
}

function normalizedQualifier(value: string | null): string {
  return (value ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s*\([^)]*\)\s*$/, "");
}

function normalizedOptionalQualifier(value: string | null): string {
  const qualifier = normalizedQualifier(value);
  return qualifier === "unknown" ? "" : qualifier;
}

function skuRank(row: SkuRow): number {
  return (
    (row.language_code === "EN" ? 0 : 10) +
    (row.variant_code === "N" ? 0 : 1)
  );
}

function compareNaturalQualifiers(left: SkuRow, right: SkuRow): number {
  return [left.condition_name, left.language_name, left.variant_name]
    .map(normalizedQualifier)
    .join("\u0000")
    .localeCompare(
      [right.condition_name, right.language_name, right.variant_name]
        .map(normalizedQualifier)
        .join("\u0000"),
    );
}

function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}

export function priceOnDate(history: string, date: string): number | null {
  return (
    parsePriceHistory(history)
      .filter((point) => point.date <= date)
      .at(-1)?.price ?? null
  );
}

export function parsePriceHistory(value: string): PricePoint[] {
  try {
    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .flatMap((entry): PricePoint[] => {
        const price = Number(entry?.price);
        return typeof entry?.date === "string" && Number.isFinite(price)
          ? [{ date: entry.date, price }]
          : [];
      })
      .sort((left, right) => left.date.localeCompare(right.date));
  } catch {
    return [];
  }
}

export async function loadSkus(
  db: D1Database,
  cardRefs: string[],
  startDate?: string,
  endDate?: string,
): Promise<SkuRow[]> {
  const effectiveEnd = endDate ?? new Date().toISOString().slice(0, 10);
  const effectiveStart = startDate ?? shiftDate(effectiveEnd, -31);
  const published = await loadPublishedPriceRows(db, cardRefs);
  const histories = published.length === 0
    ? new Map<number, PricePoint[]>()
    : await loadPriceHistoryBySeries(
      db,
      published.map((row) => row.series_id),
      effectiveStart,
      effectiveEnd,
    );
  return published.map((row) => ({
    series_id: row.series_id,
    source_code: row.source_code,
    source_record_id: row.source_record_id,
    metric_code: row.metric_code,
    product_id: row.product_id,
    condition_code: row.condition_code,
    condition_name: row.condition_name,
    language_code: row.language_code,
    language_name: row.language_name,
    variant_code: row.variant_code,
    variant_name: row.variant_name,
    grader_code: row.grader_code,
    grade_min_x10: row.grade_min_x10,
    grade_max_x10: row.grade_max_x10,
    price_history: JSON.stringify(
      pointsWithPublishedSnapshot(row, histories.get(row.series_id)),
    ),
    change_30d_percent: row.change_30d_percent,
  }));
}

function gradeMatches(
  grade: number,
  minX10: number | null,
  maxX10: number | null,
): boolean {
  if (minX10 === null || maxX10 === null) return false;
  const gradeX10 = Math.round(grade * 10);
  return gradeX10 >= minX10 && gradeX10 <= maxX10;
}

export async function loadCards(db: D1Database, cardRefs: string[]): Promise<CardRow[]> {
  const rows: CardRow[] = [];
  for (let offset = 0; offset < cardRefs.length; offset += 80) {
    const chunk = cardRefs.slice(offset, offset + 80);
    const placeholders = chunk.map(() => "?").join(", ");
    const result = await db
      .prepare(
        `SELECT product_id, game, name, set_name, number, rarity
         FROM cards_all WHERE product_id IN (${placeholders})`,
      )
      .bind(...chunk)
      .all<CardRow>();
    rows.push(...(result.results ?? []));
  }
  return rows;
}

export function groupSkus(rows: SkuRow[]): Map<string, SkuRow[]> {
  const grouped = new Map<string, SkuRow[]>();
  for (const row of rows) {
    const key = row.product_id;
    grouped.set(key, [...(grouped.get(key) ?? []), row]);
  }
  return grouped;
}

function groupEvents(rows: ItemEventRow[]): Map<string, ItemEventRow[]> {
  const grouped = new Map<string, ItemEventRow[]>();
  for (const row of rows) {
    grouped.set(row.item_id, [...(grouped.get(row.item_id) ?? []), row]);
  }
  return grouped;
}

function dateKeys(now: Date, days: number): string[] {
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  return Array.from({ length: days + 1 }, (_, index) => {
    const date = new Date(end);
    date.setUTCDate(date.getUTCDate() - days + index);
    return date.toISOString().slice(0, 10);
  });
}
