import type { AuthenticatedOwner } from "../owner-auth";
import { cardImageUrl } from "../card-image-url";
import {
  gradedIncreaseField,
  gradedPriceHistoryField,
  type GradedIncreaseField,
  type GradedPriceHistoryField,
} from "../grading";

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
  quantity: number;
  event_type: "upsert" | "delete";
  effective_at: string;
};

export type SkuRow = {
  sku_id: number | null;
  product_id: string;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  price_history: string;
  increase_rate: number | null;
} & Record<GradedPriceHistoryField, string>
  & Record<GradedIncreaseField, number | null>;

export type MatchedPrice = {
  row: SkuRow;
  history: string;
  increaseRate: number | null;
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
  current_value_usd: number;
  series: Array<{ date: string; value_usd: number }>;
  most_valuable: MostValuableItem[];
};

const SELECT_EVENTS_SQL = `
SELECT id, item_id, folder_id, card_ref, grader, condition, grade, language,
  finish, quantity, event_type, effective_at
FROM collection_item_event
WHERE owner_type = ? AND owner_id = ?
ORDER BY effective_at ASC, id ASC
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
  const skus = await loadSkus(db, [...new Set(events.map((event) => event.card_ref))]);
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
    return {
      folder_id: folderId,
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
  const items: MostValuableItem[] = [];
  for (const events of eventsByItem.values()) {
    const state = stateOnDate(events, date);
    if (!state || state.event_type === "delete" || state.folder_id !== folderId) continue;
    const matched = matchingPrice(state, skusByProduct.get(state.card_ref) ?? []);
    const card = cardsByProduct.get(state.card_ref);
    const current = matched ? priceOnDate(matched.history, date) : null;
    if (!matched || !card || current === null) continue;
    const positionValue = roundMoney(current * state.quantity);
    const previous = priceOnDate(matched.history, baselineDate);
    items.push({
      item_id: state.item_id,
      card_ref: state.card_ref,
      name: card.name ?? state.card_ref,
      set_name: card.set_name ?? "",
      card_number: card.number ?? "",
      finish: state.finish,
      image_url: cardImageUrl(state.card_ref, "thumbnail"),
      price_usd: positionValue,
      previous_30d_price_usd:
        previous === null ? null : roundMoney(previous * state.quantity),
      increase_percent:
        matched.increaseRate !== null && Number.isFinite(matched.increaseRate)
          ? matched.increaseRate
          : null,
    });
  }
  return items
    .sort((left, right) => right.price_usd - left.price_usd || left.item_id.localeCompare(right.item_id))
    .slice(0, 3);
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
  event: Pick<ItemEventRow, "grader" | "condition" | "grade" | "language" | "finish">,
  rows: SkuRow[],
): MatchedPrice | null {
  if (event.grader.toLowerCase() === "raw") {
    const row = matchingSku(event, rows);
    return row
      ? { row, history: row.price_history, increaseRate: row.increase_rate }
      : null;
  }
  if (event.grade === null) return null;
  const field = gradedPriceHistoryField(event.grader.toUpperCase(), event.grade);
  const increaseField = gradedIncreaseField(event.grader.toUpperCase(), event.grade);
  if (!field || !increaseField) return null;
  const language = normalizedOptionalQualifier(event.language);
  const finish = normalizedOptionalQualifier(event.finish);
  const candidates = rows
    .filter((row) => optionalQualifierMatches(language, row.language_code, row.language_name))
    .filter((row) => optionalQualifierMatches(finish, row.variant_code, row.variant_name))
    .filter((row) => parsePriceHistory(row[field]).length > 0)
    .sort((left, right) =>
      qualifierRank(language, left.language_code, left.language_name)
      - qualifierRank(language, right.language_code, right.language_name)
      || qualifierRank(finish, left.variant_code, left.variant_name)
      - qualifierRank(finish, right.variant_code, right.variant_name)
      || (left.sku_id ?? Number.MAX_SAFE_INTEGER)
      - (right.sku_id ?? Number.MAX_SAFE_INTEGER)
  );
  const row = candidates[0];
  return row
    ? { row, history: row[field], increaseRate: row[increaseField] }
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
      .filter((row) => qualifierMatches(condition, row.condition_code, row.condition_name))
      .filter((row) => !language || qualifierMatches(language, row.language_code, row.language_name))
      .filter((row) => !finish || qualifierMatches(finish, row.variant_code, row.variant_name))
      .filter((row) => parsePriceHistory(row.price_history).length > 0)
      .sort((left, right) =>
        skuRank(left) - skuRank(right)
        || (left.sku_id ?? Number.MAX_SAFE_INTEGER)
        - (right.sku_id ?? Number.MAX_SAFE_INTEGER)
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

function parsePriceHistory(value: string): PricePoint[] {
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

export async function loadSkus(db: D1Database, cardRefs: string[]): Promise<SkuRow[]> {
  const productIds = cardRefs.filter((ref) => /^\d+$/.test(ref));
  const rows: SkuRow[] = [];
  for (let offset = 0; offset < productIds.length; offset += 80) {
    const chunk = productIds.slice(offset, offset + 80);
    const placeholders = chunk.map(() => "?").join(", ");
    const result = await db
      .prepare(
        `SELECT sku_id, product_id, condition_code, condition_name, language_code,
          language_name, variant_code, variant_name,
          price_Ungraded AS price_history,
          increase_Ungraded AS increase_rate,
          price_Grade_7, price_Grade_8, price_Grade_9, price_Grade_9_5,
          price_PSA_10, price_BGS_10, price_CGC_10, price_SGC_10,
          increase_Grade_7, increase_Grade_8, increase_Grade_9,
          increase_Grade_9_5, increase_PSA_10, increase_BGS_10,
          increase_CGC_10, increase_SGC_10
         FROM tcg_price
         WHERE product_id IN (${placeholders})`,
      )
      .bind(...chunk)
      .all<SkuRow>();
    rows.push(...(result.results ?? []));
  }
  return rows;
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

function shiftDate(date: string, days: number): string {
  const shifted = new Date(`${date}T00:00:00.000Z`);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}
