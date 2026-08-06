import { describe, expect, it } from "vitest";
import {
  gradedIncreaseField,
  gradedPriceHistoryField,
  isSupportedGradedSelection,
} from "./grading";

describe("graded collection price mapping", () => {
  it("maps every supported grader score to its database bucket because saved cards must remain priceable", () => {
    expect([
      ["PSA", 7, gradedPriceHistoryField("PSA", 7)],
      ["PSA", 7.5, gradedPriceHistoryField("PSA", 7.5)],
      ["BGS", 8.5, gradedPriceHistoryField("BGS", 8.5)],
      ["BGS", 9.5, gradedPriceHistoryField("BGS", 9.5)],
      ["PSA", 10, gradedPriceHistoryField("PSA", 10)],
      ["BGS", 10, gradedPriceHistoryField("BGS", 10)],
      ["CGC", 10, gradedPriceHistoryField("CGC", 10)],
      ["SGC", 10, gradedPriceHistoryField("SGC", 10)],
    ]).toEqual([
      ["PSA", 7, "price_Grade_7"],
      ["PSA", 7.5, "price_Grade_7"],
      ["BGS", 8.5, "price_Grade_8"],
      ["BGS", 9.5, "price_Grade_9_5"],
      ["PSA", 10, "price_PSA_10"],
      ["BGS", 10, "price_BGS_10"],
      ["CGC", 10, "price_CGC_10"],
      ["SGC", 10, "price_SGC_10"],
    ]);
  });

  it("uses the matching increase bucket because displayed percentages are already calculated", () => {
    expect(gradedIncreaseField("BGS", 9.5)).toBe("increase_Grade_9_5");
    expect(gradedIncreaseField("PSA", 10)).toBe("increase_PSA_10");
  });

  it("rejects removed graders and unsupported scores because they have no deterministic database price", () => {
    expect(isSupportedGradedSelection("TAG", 10)).toBe(false);
    expect(isSupportedGradedSelection("AGS", 10)).toBe(false);
    expect(isSupportedGradedSelection("PSA", 9.5)).toBe(false);
    expect(isSupportedGradedSelection("CGC", 9)).toBe(false);
  });
});
