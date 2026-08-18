import type { AuthenticatedOwner } from "../owner-auth";
import {
  groupSkus,
  loadSkus,
  matchingPrice,
  parsePriceHistory,
  type SkuRow,
} from "./valuation-history";

export const PERFORMANCE_RANGES = ["1D", "7D", "15D", "1M", "3M", "1Y"] as const;
export type PerformanceRange = (typeof PERFORMANCE_RANGES)[number];

type PerformanceEventRow = {
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
  purchase_price: number | null;
  purchase_currency: string | null;
  performance_history_available_from: string | null;
  event_type: "upsert" | "delete";
  effective_at: string;
};

export type PerformancePoint = {
  date: string;
  market_value_usd: number;
  market_value_change_usd: number | null;
  market_change_usd: number | null;
  portfolio_change_usd: number | null;
  paid_market_value_usd: number | null;
  total_paid_usd: number | null;
  profit_loss_usd: number | null;
  profit_loss_change_usd: number | null;
  return_percent: number | null;
  quantity: number;
  quantity_change: number | null;
};

export type PerformanceResult = {
  range: PerformanceRange;
  range_start: string;
  range_end: string;
  history_available_from: string | null;
  partial_history: boolean;
  item_count: number;
  market_price_status: "available" | "missing";
  purchase_price_status: "complete" | "partial" | "missing";
  current: Omit<PerformancePoint, "date">;
  series: PerformancePoint[];
};

const PERFORMANCE_EVENT_LIMIT = 10_000;

const SELECT_PERFORMANCE_EVENTS_SQL = `
SELECT id, item_id, folder_id, card_ref, grader, condition, grade, language,
  finish, price_series_id, quantity, purchase_price, purchase_currency,
  performance_history_available_from, event_type, effective_at
FROM collection_item_event
WHERE owner_type = ? AND owner_id = ?`;

const SELECT_PERFORMANCE_EVENTS_ORDER_LIMIT_SQL = `
ORDER BY effective_at ASC, id ASC
LIMIT ${PERFORMANCE_EVENT_LIMIT + 1}
`;

export function parsePerformanceRange(value: string | undefined): PerformanceRange | null {
  const normalized = (value ?? "1M").toUpperCase();
  return PERFORMANCE_RANGES.find((range) => range === normalized) ?? null;
}

export async function loadPortfolioPerformance(
  db: D1Database,
  owner: AuthenticatedOwner,
  range: PerformanceRange,
  options: { folderId?: string; itemId?: string; now?: Date } = {},
): Promise<PerformanceResult> {
  const itemClause = options.itemId ? " AND item_id = ?" : "";
  const bindings = options.itemId
    ? [owner.owner_type, owner.owner_id, options.itemId]
    : [owner.owner_type, owner.owner_id];
  const result = await db
    .prepare(`${SELECT_PERFORMANCE_EVENTS_SQL}${itemClause}${SELECT_PERFORMANCE_EVENTS_ORDER_LIMIT_SQL}`)
    .bind(...bindings)
    .all<PerformanceEventRow>();
  const scopedEvents = result.results ?? [];
  if (scopedEvents.length > PERFORMANCE_EVENT_LIMIT) {
    throw new Error(`Portfolio performance query exceeded ${PERFORMANCE_EVENT_LIMIT} events`);
  }
  const now = options.now ?? new Date();
  const skus = await loadSkus(
    db,
    [...new Set(scopedEvents.map((event) => event.card_ref))],
    performanceRangeStart(range, now),
    dateKey(now),
  );
  return calculatePerformance(scopedEvents, skus, range, options);
}

export function calculatePerformance(
  events: PerformanceEventRow[],
  skus: SkuRow[],
  range: PerformanceRange,
  options: { folderId?: string; itemId?: string; now?: Date } = {},
): PerformanceResult {
  const now = options.now ?? new Date();
  const rangeEnd = dateKey(now);
  const rangeStart = performanceRangeStart(range, now);
  const grouped = groupEvents(events);
  const skusByProduct = groupSkus(skus);
  const folderGroups = [...grouped.values()].filter((itemEvents) =>
    options.folderId ? itemEvents.at(-1)?.folder_id === options.folderId : true,
  );
  const reliableStarts = folderGroups
    .map((itemEvents) => itemEvents.at(-1)?.performance_history_available_from)
    .filter((value): value is string => Boolean(value))
    .map((value) => value.slice(0, 10));
  const historyAvailableFrom = reliableStarts.length > 0
    ? reliableStarts.sort().at(0)!
    : null;
  const effectiveStart = historyAvailableFrom && historyAvailableFrom > rangeStart
    ? historyAvailableFrom
    : rangeStart;
  const dates = dateKeys(effectiveStart, rangeEnd);
  const baseSeries = dates.map((date) => pointOnDate(
    grouped,
    skusByProduct,
    date,
    options.folderId,
  ));
  const series = baseSeries.map((point, index) => {
    const previousDate = index > 0
      ? dates[index - 1]!
      : previousReliableDate(effectiveStart, historyAvailableFrom);
    if (previousDate === null) return point;
    const marketChange = marketChangeBetweenDates(
      grouped,
      skusByProduct,
      previousDate,
      point.date,
      options.folderId,
    );
    const dailyChange = marketValueOnDate(
      grouped,
      skusByProduct,
      point.date,
      options.folderId,
    ) - marketValueOnDate(
      grouped,
      skusByProduct,
      previousDate,
      options.folderId,
    );
    const previousQuantity = quantityOnDate(grouped, previousDate, options.folderId);
    const currentProfit = profitLossOnDate(grouped, skusByProduct, point.date, options.folderId);
    const previousProfit = profitLossOnDate(grouped, skusByProduct, previousDate, options.folderId);
    return {
      ...point,
      market_change_usd: round(marketChange),
      portfolio_change_usd: round(dailyChange - marketChange),
      quantity_change: point.quantity - previousQuantity,
      market_value_change_usd: round(dailyChange),
      profit_loss_change_usd: currentProfit === null || previousProfit === null
        ? null
        : round(currentProfit - previousProfit),
    };
  });
  const current = series.at(-1) ?? emptyPoint(rangeEnd);
  const currentStates = statesOnDate(grouped, rangeEnd, options.folderId);
  const priced = currentStates.filter(hasUsdPurchasePrice).length;
  const status = currentStates.length === 0 || priced === 0
    ? "missing"
    : priced === currentStates.length
      ? "complete"
      : "partial";
  return {
    range,
    range_start: rangeStart,
    range_end: rangeEnd,
    history_available_from: historyAvailableFrom,
    partial_history: reliableStarts.some((start) => start > rangeStart),
    item_count: currentStates.length,
    market_price_status: dates.some((date) =>
      hasMarketPriceOnDate(grouped, skusByProduct, date, options.folderId),
    )
      ? "available"
      : "missing",
    purchase_price_status: status,
    current: withoutDate(current),
    series,
  };
}

export function performanceRangeStart(range: PerformanceRange, now: Date): string {
  const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  if (range === "1D") return dateKey(date);
  if (range === "7D" || range === "15D") {
    date.setUTCDate(date.getUTCDate() - (range === "7D" ? 6 : 14));
  } else if (range === "1M" || range === "3M") {
    subtractUtcMonths(date, range === "1M" ? 1 : 3);
  } else {
    subtractUtcYears(date, 1);
  }
  return dateKey(date);
}

function subtractUtcMonths(date: Date, months: number): void {
  const day = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() - months);
  const lastDay = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
  date.setUTCDate(Math.min(day, lastDay));
}

function subtractUtcYears(date: Date, years: number): void {
  const month = date.getUTCMonth();
  const day = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCFullYear(date.getUTCFullYear() - years);
  date.setUTCMonth(month);
  const lastDay = new Date(Date.UTC(date.getUTCFullYear(), month + 1, 0)).getUTCDate();
  date.setUTCDate(Math.min(day, lastDay));
}

function pointOnDate(
  grouped: Map<string, PerformanceEventRow[]>,
  skus: Map<string, SkuRow[]>,
  date: string,
  folderId?: string,
): PerformancePoint {
  let market = 0;
  let paidMarket = 0;
  let paid = 0;
  let quantity = 0;
  let pricedCount = 0;
  const states = statesOnDate(grouped, date, folderId);
  for (const state of states) {
    quantity += state.quantity;
    const matched = matchingPrice(state, skus.get(state.card_ref) ?? []);
    const unitMarket = matched ? priceWithFallback(matched.history, date) : null;
    if (unitMarket === null) continue;
    const value = unitMarket * state.quantity;
    market += value;
    const purchasePrice = latestPurchasePrice(grouped.get(state.item_id) ?? []);
    if (purchasePrice !== null) {
      pricedCount += 1;
      paidMarket += value;
      paid += purchasePrice * state.quantity;
    }
  }
  const hasPaid = pricedCount > 0;
  const profit = hasPaid ? paidMarket - paid : null;
  return {
    date,
    market_value_usd: round(market),
    market_value_change_usd: null,
    market_change_usd: null,
    portfolio_change_usd: null,
    paid_market_value_usd: hasPaid ? round(paidMarket) : null,
    total_paid_usd: hasPaid ? round(paid) : null,
    profit_loss_usd: profit === null ? null : round(profit),
    profit_loss_change_usd: null,
    return_percent: profit === null || paid === 0 ? null : round((profit / paid) * 100),
    quantity,
    quantity_change: null,
  };
}

function hasMarketPriceOnDate(
  grouped: Map<string, PerformanceEventRow[]>,
  skus: Map<string, SkuRow[]>,
  date: string,
  folderId?: string,
): boolean {
  return statesOnDate(grouped, date, folderId).some((state) => {
    const matched = matchingPrice(state, skus.get(state.card_ref) ?? []);
    return matched !== null && priceWithFallback(matched.history, date) !== null;
  });
}

function marketChangeBetweenDates(
  grouped: Map<string, PerformanceEventRow[]>,
  skus: Map<string, SkuRow[]>,
  previousDate: string,
  currentDate: string,
  folderId?: string,
): number {
  const previousStates = statesOnDate(grouped, previousDate, folderId);
  const currentStates = new Map(
    statesOnDate(grouped, currentDate, folderId).map((state) => [state.item_id, state]),
  );
  let marketChange = 0;
  for (const previous of previousStates) {
    const current = currentStates.get(previous.item_id) ?? previous;
    const previousSku = matchingPrice(previous, skus.get(previous.card_ref) ?? []);
    const currentSku = matchingPrice(current, skus.get(current.card_ref) ?? []);
    const previousPrice = previousSku
      ? priceWithFallback(previousSku.history, previousDate)
      : null;
    const currentPrice = currentSku
      ? priceWithFallback(currentSku.history, currentDate)
      : null;
    if (previousPrice === null || currentPrice === null) continue;
    marketChange += (currentPrice - previousPrice) * previous.quantity;
  }
  return marketChange;
}

function marketValueOnDate(
  grouped: Map<string, PerformanceEventRow[]>,
  skus: Map<string, SkuRow[]>,
  date: string,
  folderId?: string,
): number {
  let marketValue = 0;
  for (const state of statesOnDate(grouped, date, folderId)) {
    const matched = matchingPrice(state, skus.get(state.card_ref) ?? []);
    const unitMarket = matched ? priceWithFallback(matched.history, date) : null;
    if (unitMarket !== null) marketValue += unitMarket * state.quantity;
  }
  return marketValue;
}

function profitLossOnDate(
  grouped: Map<string, PerformanceEventRow[]>,
  skus: Map<string, SkuRow[]>,
  date: string,
  folderId?: string,
): number | null {
  let paidMarket = 0;
  let paid = 0;
  let pricedCount = 0;
  for (const state of statesOnDate(grouped, date, folderId)) {
    const matched = matchingPrice(state, skus.get(state.card_ref) ?? []);
    const unitMarket = matched ? priceWithFallback(matched.history, date) : null;
    const purchasePrice = latestPurchasePrice(grouped.get(state.item_id) ?? []);
    if (unitMarket === null || purchasePrice === null) continue;
    paidMarket += unitMarket * state.quantity;
    paid += purchasePrice * state.quantity;
    pricedCount += 1;
  }
  return pricedCount === 0 ? null : paidMarket - paid;
}

function quantityOnDate(
  grouped: Map<string, PerformanceEventRow[]>,
  date: string,
  folderId?: string,
): number {
  return statesOnDate(grouped, date, folderId).reduce(
    (quantity, state) => quantity + state.quantity,
    0,
  );
}

function previousReliableDate(
  date: string,
  historyAvailableFrom: string | null,
): string | null {
  if (historyAvailableFrom === null || date <= historyAvailableFrom) return null;
  const previous = new Date(`${date}T00:00:00.000Z`);
  previous.setUTCDate(previous.getUTCDate() - 1);
  const key = dateKey(previous);
  return key >= historyAvailableFrom ? key : null;
}

function statesOnDate(
  grouped: Map<string, PerformanceEventRow[]>,
  date: string,
  folderId?: string,
): PerformanceEventRow[] {
  const end = `${date}T23:59:59.999Z`;
  return [...grouped.values()].flatMap((events) => {
    const latest = events.at(-1);
    if (folderId && latest?.folder_id !== folderId) return [];
    const state = events.filter((event) => event.effective_at <= end).at(-1);
    if (!state || state.event_type === "delete") {
      return [];
    }
    const reliable = state.performance_history_available_from?.slice(0, 10);
    return reliable && date < reliable ? [] : [state];
  });
}

function latestPurchasePrice(events: PerformanceEventRow[]): number | null {
  const latest = events.at(-1);
  return hasUsdPurchasePrice(latest) ? latest.purchase_price : null;
}

function hasUsdPurchasePrice(event: PerformanceEventRow | undefined): event is PerformanceEventRow & { purchase_price: number } {
  return event?.purchase_price !== null && event?.purchase_currency === "USD";
}

function priceWithFallback(history: string, date: string): number | null {
  const points = parsePriceHistory(history);
  return points.filter((point) => point.date <= date).at(-1)?.price
    ?? points.find((point) => point.date > date)?.price
    ?? null;
}

function groupEvents(rows: PerformanceEventRow[]): Map<string, PerformanceEventRow[]> {
  const grouped = new Map<string, PerformanceEventRow[]>();
  for (const row of rows) grouped.set(row.item_id, [...(grouped.get(row.item_id) ?? []), row]);
  return grouped;
}

function dateKeys(start: string, end: string): string[] {
  const cursor = new Date(`${start}T00:00:00.000Z`);
  const dates: string[] = [];
  while (dateKey(cursor) <= end) {
    dates.push(dateKey(cursor));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return dates;
}

function dateKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

function withoutDate(point: PerformancePoint): Omit<PerformancePoint, "date"> {
  const { date: _, ...current } = point;
  return current;
}

function emptyPoint(date: string): PerformancePoint {
  return {
    date,
    market_value_usd: 0,
    market_value_change_usd: null,
    market_change_usd: null,
    portfolio_change_usd: null,
    paid_market_value_usd: null,
    total_paid_usd: null,
    profit_loss_usd: null,
    profit_loss_change_usd: null,
    return_percent: null,
    quantity: 0,
    quantity_change: null,
  };
}
