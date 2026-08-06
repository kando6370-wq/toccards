export type GradedPriceHistoryField =
  | "price_Grade_7"
  | "price_Grade_8"
  | "price_Grade_9"
  | "price_Grade_9_5"
  | "price_PSA_10"
  | "price_BGS_10"
  | "price_CGC_10"
  | "price_SGC_10";

export type GradedIncreaseField =
  | "increase_Grade_7"
  | "increase_Grade_8"
  | "increase_Grade_9"
  | "increase_Grade_9_5"
  | "increase_PSA_10"
  | "increase_BGS_10"
  | "increase_CGC_10"
  | "increase_SGC_10";

const GRADES_BY_GRADER = {
  PSA: [10, 9, 8.5, 8, 7.5, 7],
  BGS: [10, 9.5, 9, 8.5, 8, 7.5, 7],
  CGC: [10],
  SGC: [10],
} as const;

export function isSupportedGradedSelection(
  grader: string,
  grade: number,
): boolean {
  const grades = GRADES_BY_GRADER[grader as keyof typeof GRADES_BY_GRADER];
  return grades?.some((candidate) => candidate === grade) ?? false;
}

export function gradedPriceHistoryField(
  grader: string,
  grade: number,
): GradedPriceHistoryField | null {
  if (!isSupportedGradedSelection(grader, grade)) return null;
  if (grade === 7 || grade === 7.5) return "price_Grade_7";
  if (grade === 8 || grade === 8.5) return "price_Grade_8";
  if (grade === 9) return "price_Grade_9";
  if (grade === 9.5) return "price_Grade_9_5";
  return `price_${grader}_10` as GradedPriceHistoryField;
}

export function gradedIncreaseField(
  grader: string,
  grade: number,
): GradedIncreaseField | null {
  const priceField = gradedPriceHistoryField(grader, grade);
  return priceField?.replace("price_", "increase_") as GradedIncreaseField | null;
}
