const CARD_IMAGE_ORIGIN = "https://image.tcgcard.fun";

export type CardImageVariant = "thumbnail" | "list" | "detail" | "preview" | "master";

export function cardImageUrl(cardRef: string, _variant: CardImageVariant): string {
  const objectPath = `cards/${encodeURIComponent(cardRef)}.jpg`;
  return `${CARD_IMAGE_ORIGIN}/${objectPath}`;
}
