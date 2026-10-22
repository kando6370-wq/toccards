import type { DisplayConfig, MarketingCopy } from "./model";
import type { ProductCatalog } from "./catalog";

export const copyFixture = (name: string): MarketingCopy => ({
  name, subtitle: "", badge: "", price_note: "", cta: "", billing_note_mode: "custom", billing_note: "",
});
export function displayFixture(): DisplayConfig {
  return {
    schema_version: 1, name: "Test configuration", page_type: "page", trial_enabled: true,
    trial_toggle_text: "Enable free trial", cta: "", close_delay_seconds: 0,
    skus: [
      { ...copyFixture("Weekly"), product_id: "paid.week", product_type: "subscription", price_mode: "actual", is_default: true,
        trial: { ...copyFixture("Weekly trial"), product_id: "trial.week" } },
      { ...copyFixture("Lifetime"), product_id: "lifetime", product_type: "non_consumable", price_mode: "actual", is_default: false, trial: null },
    ],
  };
}
export function catalogFixture(): ProductCatalog {
  return { app_id: "456", bundle_id: "example.app", subscription_group_id: "123", products: [
    { product_id: "paid.week", reference_name: "Weekly", product_type: "subscription", subscription_group_id: "123", period: "ONE_WEEK", group_level: 1,
      state: "APPROVED", has_free_trial: false, introductory_offers: [] },
    { product_id: "trial.week", reference_name: "Trial", product_type: "subscription", subscription_group_id: "123", period: "ONE_WEEK", group_level: 1,
      state: "APPROVED", has_free_trial: true, introductory_offers: [
        { territory: "USA", mode: "FREE_TRIAL", duration: "THREE_DAYS", periods: 1, start_date: null, end_date: null },
      ] },
    { product_id: "lifetime", reference_name: "Lifetime", product_type: "non_consumable", subscription_group_id: null, period: null, group_level: null,
      state: "APPROVED", has_free_trial: false, introductory_offers: [] },
  ] };
}
