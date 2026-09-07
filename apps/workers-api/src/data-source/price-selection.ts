export type DisplayPriceRow = {
  series_id: number;
  source_code: string;
  source_record_id: string;
  metric_code: string;
  condition_code: string | null;
  condition_name: string | null;
  language_code: string | null;
  language_name: string | null;
  variant_code: string | null;
  variant_name: string | null;
  observed_on?: string | null;
  change_30d_percent: number | null;
};

export function compareDisplayPriceRows(
  left: DisplayPriceRow,
  right: DisplayPriceRow,
): number {
  return displayPriceRank(left) - displayPriceRank(right)
    || compareChangeDescending(left, right)
    || (right.observed_on ?? "").localeCompare(left.observed_on ?? "")
    || left.source_code.localeCompare(right.source_code)
    || left.source_record_id.localeCompare(right.source_record_id)
    || left.metric_code.localeCompare(right.metric_code)
    || left.series_id - right.series_id
    || compareNaturalQualifiers(left, right);
}

function displayPriceRank(row: DisplayPriceRow): number {
  return (row.condition_code === "NM" ? 0 : 100)
    + (row.language_code === "EN" ? 0 : 10)
    + (row.variant_code === "N" ? 0 : 1);
}

function compareChangeDescending(
  left: DisplayPriceRow,
  right: DisplayPriceRow,
): number {
  const leftChange = Number.isFinite(left.change_30d_percent)
    ? left.change_30d_percent!
    : null;
  const rightChange = Number.isFinite(right.change_30d_percent)
    ? right.change_30d_percent!
    : null;
  if (leftChange === null) return rightChange === null ? 0 : 1;
  if (rightChange === null) return -1;
  return rightChange - leftChange;
}

function compareNaturalQualifiers(
  left: DisplayPriceRow,
  right: DisplayPriceRow,
): number {
  return [left.condition_name, left.language_name, left.variant_name]
    .map(normalizedQualifier)
    .join("\u0000")
    .localeCompare(
      [right.condition_name, right.language_name, right.variant_name]
        .map(normalizedQualifier)
        .join("\u0000"),
    );
}

function normalizedQualifier(value: string | null): string {
  return (value ?? "").trim().toLowerCase();
}
