import type { AuthenticatedOwner } from "../owner-auth";
import { cardImageUrl } from "../card-image-url";
import {
  groupSkus,
  loadCards,
  loadSkus,
  matchingPrice,
  parsePriceHistory,
  type CardRow,
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

export type TopPerformer = {
  item_id: string;
  card_ref: string;
  name: string;
  set_name: string;
  card_number: string;
  image_url: string;
  profit_loss_usd: number;
  return_percent: number | null;
  market_value_usd: number;
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
  purchase_price_item_count: number;
  top_performer_count: number;
  top_performer_item_ids: string[];
  top_performers: TopPerformer[];
  current: Omit<PerformancePoint, "date">;
  series: PerformancePoint[];
};

type PerformanceOptions = {
  folderId?: string;
  itemId?: string;
  now?: Date;
  includeTopPerformers?: boolean;
  cards?: CardRow[];
};

type PerformanceCalculationCache = {
  statesByDate: Map<string, PerformanceEventRow[]>;
  matchingPriceByState: WeakMap<PerformanceEventRow, ReturnType<typeof matchingPrice>>;
  priceHistoryByValue: Map<string, {
    points: ReturnType<typeof parsePriceHistory>;
    pricesByDate: Map<string, number | null>;
  }>;
};

const PERFORMANCE_EVENT_LIMIT = 10_000;

const PERFORMANCE_EVENT_COLUMNS = `
id, item_id, folder_id, card_ref, grader, condition, grade, language,
  finish, price_series_id, quantity, purchase_price, purchase_currency,
  performance_history_available_from, event_type, effective_at`;

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
  options: PerformanceOptions = {},
): Promise<PerformanceResult> {
  const now = options.now ?? new Date();
  const rangeStart = performanceRangeStart(range, now);
  const rangeStartTimestamp = `${rangeStart}T00:00:00.000Z`;
  const itemClause = options.itemId ? " AND item_id = ?" : "";
  const folderClause = options.folderId ? "latest.folder_id = ?" : "TRUE";
  const bindings = [
    owner.owner_type,
    owner.owner_id,
    ...(options.itemId ? [options.itemId] : []),
    ...(options.folderId ? [options.folderId] : []),
    rangeStartTimestamp,
    rangeStartTimestamp,
  ];
  const result = await db
    .prepare(`
WITH scoped_events AS (
  SELECT ${PERFORMANCE_EVENT_COLUMNS}
  FROM collection_item_event
  WHERE owner_type = ? AND owner_id = ?${itemClause}
),
latest_items AS (
  SELECT DISTINCT ON (item_id) item_id, folder_id
  FROM scoped_events
  ORDER BY item_id, effective_at DESC, id DESC
),
selected_events AS (
  SELECT events.*
  FROM scoped_events AS events
  JOIN latest_items AS latest ON latest.item_id = events.item_id
  WHERE ${folderClause}
),
bounded_events AS (
  SELECT *
  FROM selected_events
  WHERE effective_at >= ?
  UNION ALL
  SELECT *
  FROM (
    SELECT DISTINCT ON (item_id) *
    FROM selected_events
    WHERE effective_at < ?
    ORDER BY item_id, effective_at DESC, id DESC
  ) AS baselines
)
SELECT ${PERFORMANCE_EVENT_COLUMNS}
FROM bounded_events
${SELECT_PERFORMANCE_EVENTS_ORDER_LIMIT_SQL}`)
    .bind(...bindings)
    .all<PerformanceEventRow>();
  const scopedEvents = result.results ?? [];
  if (scopedEvents.length > PERFORMANCE_EVENT_LIMIT) {
    throw new Error(`Portfolio performance query exceeded ${PERFORMANCE_EVENT_LIMIT} events`);
  }
  const cardRefs = [...new Set(scopedEvents.map((event) => event.card_ref))];
  const skus = await loadSkus(
    db,
    cardRefs,
    rangeStart,
    dateKey(now),
  );
  const performance = calculatePerformance(scopedEvents, skus, range, {
    ...options,
    cards: [],
  });
  if (!options.includeTopPerformers || performance.top_performers.length === 0) {
    return performance;
  }
  const cards = await loadCards(
    db,
    performance.top_performers.map((performer) => performer.card_ref),
  );
  const cardsByRef = new Map(cards.map((card) => [card.product_id, card]));
  return {
    ...performance,
    top_performers: performance.top_performers.map((performer) => {
      const card = cardsByRef.get(performer.card_ref);
      return {
        ...performer,
        name: card?.name ?? performer.name,
        set_name: card?.set_name ?? performer.set_name,
        card_number: card?.number ?? performer.card_number,
      };
    }),
  };
}

export function calculatePerformance(
  events: PerformanceEventRow[],
  skus: SkuRow[],
  range: PerformanceRange,
  options: PerformanceOptions = {},
): PerformanceResult {
  const now = options.now ?? new Date();
  const rangeEnd = dateKey(now);
  const rangeStart = performanceRangeStart(range, now);
  const grouped = groupEvents(events);
  const skusByProduct = groupSkus(skus);
  const cache: PerformanceCalculationCache = {
    statesByDate: new Map(),
    matchingPriceByState: new WeakMap(),
    priceHistoryByValue: new Map(),
  };
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
    cache,
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
      cache,
    );
    const dailyChange = marketValueOnDate(
      grouped,
      skusByProduct,
      point.date,
      options.folderId,
      cache,
    ) - marketValueOnDate(
      grouped,
      skusByProduct,
      previousDate,
      options.folderId,
      cache,
    );
    const previousQuantity = quantityOnDate(grouped, previousDate, options.folderId, cache);
    const currentProfit = profitLossOnDate(
      grouped,
      skusByProduct,
      point.date,
      options.folderId,
      cache,
    );
    const previousProfit = profitLossOnDate(
      grouped,
      skusByProduct,
      previousDate,
      options.folderId,
      cache,
    );
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
  const currentStates = statesOnDate(grouped, rangeEnd, options.folderId, cache);
  const topPerformers = options.includeTopPerformers
    ? calculateTopPerformers(
      currentStates,
      grouped,
      skusByProduct,
      new Map((options.cards ?? []).map((card) => [card.product_id, card])),
      rangeEnd,
      cache,
    )
    : [];
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
      hasMarketPriceOnDate(grouped, skusByProduct, date, options.folderId, cache),
    )
      ? "available"
      : "missing",
    purchase_price_status: status,
    purchase_price_item_count: priced,
    top_performer_count: topPerformers.length,
    top_performer_item_ids: topPerformers.map((performer) => performer.item_id),
    top_performers: topPerformers.slice(0, 5),
    current: withoutDate(current),
    series,
  };
}

function calculateTopPerformers(
  states: PerformanceEventRow[],
  grouped: Map<string, PerformanceEventRow[]>,
  skus: Map<string, SkuRow[]>,
  cards: Map<string, CardRow>,
  date: string,
  cache: PerformanceCalculationCache,
): TopPerformer[] {
  const ranked = [];
  for (const state of states) {
    const purchasePrice = latestPurchasePrice(grouped.get(state.item_id) ?? []);
    const matched = matchingPriceForState(state, skus.get(state.card_ref) ?? [], cache);
    const unitMarket = matched ? priceWithFallback(matched.history, date, cache) : null;
    if (purchasePrice === null || unitMarket === null) continue;

    const marketValue = unitMarket * state.quantity;
    const totalPaid = purchasePrice * state.quantity;
    const profitLoss = marketValue - totalPaid;
    const card = cards.get(state.card_ref);
    ranked.push({
      itemId: state.item_id,
      cardRef: state.card_ref,
      name: card?.name ?? state.card_ref,
      setName: card?.set_name ?? "Card data unavailable",
      cardNumber: card?.number ?? "",
      profitLoss,
      returnPercent: totalPaid === 0 ? null : (profitLoss / totalPaid) * 100,
      marketValue,
    });
  }

  ranked.sort((left, right) =>
    compareNullableDescending(left.returnPercent, right.returnPercent)
    || right.profitLoss - left.profitLoss
    || right.marketValue - left.marketValue
    || left.itemId.localeCompare(right.itemId)
  );

  return ranked.map((item) => ({
    item_id: item.itemId,
    card_ref: item.cardRef,
    name: item.name,
    set_name: item.setName,
    card_number: item.cardNumber,
    image_url: cardImageUrl(item.cardRef, "thumbnail"),
    profit_loss_usd: round(item.profitLoss),
    return_percent: item.returnPercent === null ? null : round(item.returnPercent),
    market_value_usd: round(item.marketValue),
  }));
}

function compareNullableDescending(left: number | null, right: number | null): number {
  if (left === null) return right === null ? 0 : 1;
  if (right === null) return -1;
  return right - left;
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
  folderId: string | undefined,
  cache: PerformanceCalculationCache,
): PerformancePoint {
  let market = 0;
  let paidMarket = 0;
  let paid = 0;
  let quantity = 0;
  let pricedCount = 0;
  const states = statesOnDate(grouped, date, folderId, cache);
  for (const state of states) {
    quantity += state.quantity;
    const matched = matchingPriceForState(
      state,
      skus.get(state.card_ref) ?? [],
      cache,
    );
    const unitMarket = matched
      ? priceWithFallback(matched.history, date, cache)
      : null;
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
  folderId: string | undefined,
  cache: PerformanceCalculationCache,
): boolean {
  return statesOnDate(grouped, date, folderId, cache).some((state) => {
    const matched = matchingPriceForState(
      state,
      skus.get(state.card_ref) ?? [],
      cache,
    );
    return matched !== null
      && priceWithFallback(matched.history, date, cache) !== null;
  });
}

function marketChangeBetweenDates(
  grouped: Map<string, PerformanceEventRow[]>,
  skus: Map<string, SkuRow[]>,
  previousDate: string,
  currentDate: string,
  folderId: string | undefined,
  cache: PerformanceCalculationCache,
): number {
  const previousStates = statesOnDate(grouped, previousDate, folderId, cache);
  const currentStates = new Map(
    statesOnDate(grouped, currentDate, folderId, cache)
      .map((state) => [state.item_id, state]),
  );
  let marketChange = 0;
  for (const previous of previousStates) {
    const current = currentStates.get(previous.item_id) ?? previous;
    const previousSku = matchingPriceForState(
      previous,
      skus.get(previous.card_ref) ?? [],
      cache,
    );
    const currentSku = matchingPriceForState(
      current,
      skus.get(current.card_ref) ?? [],
      cache,
    );
    const previousPrice = previousSku
      ? priceWithFallback(previousSku.history, previousDate, cache)
      : null;
    const currentPrice = currentSku
      ? priceWithFallback(currentSku.history, currentDate, cache)
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
  folderId: string | undefined,
  cache: PerformanceCalculationCache,
): number {
  let marketValue = 0;
  for (const state of statesOnDate(grouped, date, folderId, cache)) {
    const matched = matchingPriceForState(
      state,
      skus.get(state.card_ref) ?? [],
      cache,
    );
    const unitMarket = matched
      ? priceWithFallback(matched.history, date, cache)
      : null;
    if (unitMarket !== null) marketValue += unitMarket * state.quantity;
  }
  return marketValue;
}

function profitLossOnDate(
  grouped: Map<string, PerformanceEventRow[]>,
  skus: Map<string, SkuRow[]>,
  date: string,
  folderId: string | undefined,
  cache: PerformanceCalculationCache,
): number | null {
  let paidMarket = 0;
  let paid = 0;
  let pricedCount = 0;
  for (const state of statesOnDate(grouped, date, folderId, cache)) {
    const matched = matchingPriceForState(
      state,
      skus.get(state.card_ref) ?? [],
      cache,
    );
    const unitMarket = matched
      ? priceWithFallback(matched.history, date, cache)
      : null;
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
  folderId: string | undefined,
  cache: PerformanceCalculationCache,
): number {
  return statesOnDate(grouped, date, folderId, cache).reduce(
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
  folderId: string | undefined,
  cache: PerformanceCalculationCache,
): PerformanceEventRow[] {
  const cached = cache.statesByDate.get(date);
  if (cached) return cached;
  const end = `${date}T23:59:59.999Z`;
  const states: PerformanceEventRow[] = [];
  for (const events of grouped.values()) {
    const latest = events.at(-1);
    if (folderId && latest?.folder_id !== folderId) continue;
    let low = 0;
    let high = events.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (events[middle]!.effective_at <= end) low = middle + 1;
      else high = middle;
    }
    const state = events[low - 1];
    if (!state || state.event_type === "delete") {
      continue;
    }
    const reliable = state.performance_history_available_from?.slice(0, 10);
    if (!reliable || date >= reliable) states.push(state);
  }
  cache.statesByDate.set(date, states);
  return states;
}

function latestPurchasePrice(events: PerformanceEventRow[]): number | null {
  const latest = events.at(-1);
  return hasUsdPurchasePrice(latest) ? latest.purchase_price : null;
}

function hasUsdPurchasePrice(event: PerformanceEventRow | undefined): event is PerformanceEventRow & { purchase_price: number } {
  return event?.purchase_price !== null && event?.purchase_currency === "USD";
}

function matchingPriceForState(
  state: PerformanceEventRow,
  skus: SkuRow[],
  cache: PerformanceCalculationCache,
): ReturnType<typeof matchingPrice> {
  if (cache.matchingPriceByState.has(state)) {
    return cache.matchingPriceByState.get(state) ?? null;
  }
  const matched = matchingPrice(state, skus);
  cache.matchingPriceByState.set(state, matched);
  return matched;
}

function priceWithFallback(
  history: string,
  date: string,
  cache: PerformanceCalculationCache,
): number | null {
  let cached = cache.priceHistoryByValue.get(history);
  if (!cached) {
    cached = {
      points: parsePriceHistory(history),
      pricesByDate: new Map(),
    };
    cache.priceHistoryByValue.set(history, cached);
  }
  if (cached.pricesByDate.has(date)) {
    return cached.pricesByDate.get(date) ?? null;
  }
  let low = 0;
  let high = cached.points.length;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (cached.points[middle]!.date <= date) low = middle + 1;
    else high = middle;
  }
  const price = (cached.points[low - 1] ?? cached.points[0])?.price ?? null;
  cached.pricesByDate.set(date, price);
  return price;
}

function groupEvents(rows: PerformanceEventRow[]): Map<string, PerformanceEventRow[]> {
  const grouped = new Map<string, PerformanceEventRow[]>();
  for (const row of rows) {
    const events = grouped.get(row.item_id);
    if (events) events.push(row);
    else grouped.set(row.item_id, [row]);
  }
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
