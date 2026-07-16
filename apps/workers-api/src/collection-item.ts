export type CollectionItemDraft = {
  folder_id: string;
  card_ref: string;
  object_type: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  quantity: number;
  purchase_price: number | null;
  purchase_currency: string | null;
  notes: string | null;
};

type CollectionItemOverrides = Partial<
  Pick<CollectionItemDraft, "folder_id" | "card_ref" | "object_type">
>;

const SUPPORTED_OBJECT_TYPES = new Set(["tcg", "sports", "sealed", "other"]);
const SUPPORTED_GRADERS = new Set(["Raw", "PSA", "BGS", "SGC", "CGC", "TAG", "AGS"]);
const SUPPORTED_RAW_CONDITIONS = new Set([
  "Near Mint (NM)",
  "Lightly Played (LP)",
  "Moderately Played (MP)",
  "Heavily Played (HP)",
  "Damaged (D)",
]);
const ISO_4217_CURRENCY_PATTERN = /^[A-Z]{3}$/;

export function collectionItemDraftFromBody(
  body: unknown,
  overrides: CollectionItemOverrides = {},
): CollectionItemDraft | null {
  if (!isRecord(body)) return null;

  const folderId = overrides.folder_id ?? requiredString(body.folder_id);
  const cardRef = overrides.card_ref ?? requiredString(body.card_ref);
  const objectType = overrides.object_type ?? requiredString(body.object_type);
  const grader = requiredString(body.grader);
  const quantity = positiveInteger(body.quantity);
  const condition = nullableString(body.condition);
  const grade = nullableNumber(body.grade);
  const language = nullableString(body.language);
  const finish = nullableString(body.finish);
  const purchasePrice = nullableNumber(body.purchase_price);
  const purchaseCurrency = nullableString(body.purchase_currency);
  const notes = nullableString(body.notes);

  if (
    !folderId ||
    !cardRef ||
    !objectType ||
    !grader ||
    !quantity ||
    !condition.valid ||
    !grade.valid ||
    !language.valid ||
    !finish.valid ||
    !purchasePrice.valid ||
    !purchaseCurrency.valid ||
    !notes.valid
  ) {
    return null;
  }

  return normalizeCollectionItemDraft({
    folder_id: folderId,
    card_ref: cardRef,
    object_type: objectType,
    grader,
    condition: condition.value,
    grade: grade.value,
    language: language.value,
    finish: finish.value,
    quantity,
    purchase_price: purchasePrice.value,
    purchase_currency: purchaseCurrency.value,
    notes: notes.value,
  });
}

export function collectionItemPatchFromBody(
  body: unknown,
  item: CollectionItemDraft,
): CollectionItemDraft | null {
  if (!isRecord(body)) return null;

  return collectionItemDraftFromBody(
    {
      grader: body.grader === undefined ? item.grader : body.grader,
      condition: body.condition === undefined ? item.condition : body.condition,
      grade: body.grade === undefined ? item.grade : body.grade,
      language: body.language === undefined ? item.language : body.language,
      finish: body.finish === undefined ? item.finish : body.finish,
      quantity: body.quantity === undefined ? item.quantity : body.quantity,
      purchase_price:
        body.purchase_price === undefined ? item.purchase_price : body.purchase_price,
      purchase_currency:
        body.purchase_currency === undefined
          ? item.purchase_currency
          : body.purchase_currency,
      notes: body.notes === undefined ? item.notes : body.notes,
    },
    {
      folder_id: item.folder_id,
      card_ref: item.card_ref,
      object_type: item.object_type,
    },
  );
}

function normalizeCollectionItemDraft(
  draft: CollectionItemDraft,
): CollectionItemDraft | null {
  if (
    !SUPPORTED_OBJECT_TYPES.has(draft.object_type) ||
    !SUPPORTED_GRADERS.has(draft.grader) ||
    (draft.notes?.length ?? 0) > 500 ||
    (draft.purchase_price !== null && draft.purchase_price < 0) ||
    (draft.purchase_currency !== null &&
      !ISO_4217_CURRENCY_PATTERN.test(draft.purchase_currency)) ||
    (draft.purchase_price !== null && !draft.purchase_currency)
  ) {
    return null;
  }

  if (draft.object_type === "sealed") {
    return draft.grader === "Raw" && draft.condition === null && draft.grade === null
      ? draft
      : null;
  }

  if (draft.grader === "Raw") {
    return draft.condition &&
      SUPPORTED_RAW_CONDITIONS.has(draft.condition) &&
      draft.grade === null
      ? draft
      : null;
  }

  return draft.grade !== null &&
    isValidGrade(draft.grade) &&
    draft.condition === null
    ? draft
    : null;
}

function requiredString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function nullableString(
  value: unknown,
): { valid: boolean; value: string | null } {
  if (value === null || value === undefined) return { valid: true, value: null };
  if (typeof value !== "string") return { valid: false, value: null };
  return { valid: true, value: requiredString(value) };
}

function nullableNumber(
  value: unknown,
): { valid: boolean; value: number | null } {
  if (value === null || value === undefined) return { valid: true, value: null };
  return typeof value === "number" && Number.isFinite(value)
    ? { valid: true, value }
    : { valid: false, value: null };
}

function positiveInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
    ? value
    : null;
}

function isValidGrade(grade: number): boolean {
  return grade > 0 && grade <= 10 && Number.isSafeInteger(grade * 2);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
