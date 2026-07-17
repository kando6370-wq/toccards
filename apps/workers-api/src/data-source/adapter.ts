export type CardObjectType = "tcg" | "sports" | "sealed" | "other";

export type CardSearchOptions = {
  object_type?: CardObjectType;
  game?: string;
  page?: number;
  page_size?: number;
};

export type SetSearchResult = {
  set_code: string;
  set_name: string;
  game: string | null;
  image_url: string | null;
  image_card_ref: string | null;
  card_count: number;
};

export type CardSearchResult = {
  card_ref: string;
  name: string;
  game?: string | null;
  set_name: string;
  set_code: string;
  card_number: string;
  finish: string | null;
  language: string | null;
  object_type: CardObjectType;
  image_url: string | null;
  rarity: string | null;
  price_usd?: number;
  previous_30d_price_usd?: number;
  previous_1d_price_usd?: number;
  price_change_1d_percent?: number;
  price_as_of?: string;
  previous_price_as_of?: string;
};

export type PricePoint = {
  date: string;
  price: number;
};

export type MarketPrice = {
  grader: string;
  grade: number | null;
  condition: string | null;
  price: number | null;
};

export type SoldListing = {
  date: string;
  title: string;
  price: number;
  platform: string;
  url: string | null;
};

export interface DataSourceAdapter {
  searchCards(
    query: string,
    options?: CardSearchOptions,
  ): Promise<CardSearchResult[]>;
  searchSets(
    query: string,
    options?: Pick<CardSearchOptions, "game" | "page" | "page_size">,
  ): Promise<SetSearchResult[]>;
  getCard(card_ref: string): Promise<CardSearchResult | null>;
  getPriceSeries(
    card_ref: string,
    grader: string,
    grade: number | null,
    condition: string | null,
    days: number,
  ): Promise<PricePoint[]>;
  getMarketPrices(card_ref: string): Promise<MarketPrice[]>;
  getTrending(): Promise<CardSearchResult[]>;
  getSoldListings(card_ref: string): Promise<SoldListing[]>;
}
