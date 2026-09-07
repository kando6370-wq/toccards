import isoCountries from "i18n-iso-countries";

export function countryDisplayName(value: unknown): string {
  if (typeof value !== "string") return "";
  const normalized = value.trim().toUpperCase();
  const alpha2 = /^[A-Z]{2}$/.test(normalized) && isoCountries.isValid(normalized)
    ? normalized
    : /^[A-Z]{3}$/.test(normalized)
      ? isoCountries.alpha3ToAlpha2(normalized)
      : undefined;
  if (!alpha2) return "";
  return new Intl.DisplayNames(["zh-CN"], { type: "region" }).of(alpha2) ?? alpha2;
}
