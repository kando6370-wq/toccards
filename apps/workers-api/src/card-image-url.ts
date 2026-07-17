const CARD_IMAGE_ORIGIN = "https://image.tcgcard.fun";

export type CardImageVariant = "thumbnail" | "list" | "detail" | "preview" | "master";

const CARD_IMAGE_TRANSFORMS: Record<Exclude<CardImageVariant, "master">, string> = {
  thumbnail: "width=160,height=224,fit=scale-down,quality=60,format=auto,dpr=2",
  list: "width=360,height=504,fit=scale-down,quality=75,format=auto",
  detail: "width=600,height=800,fit=scale-down,quality=85,format=auto,sharpen=1",
  preview: "width=1600,fit=scale-down,quality=92,format=auto",
};

export function cardImageUrl(cardRef: string, variant: CardImageVariant): string {
  const objectPath = `cards/${encodeURIComponent(cardRef)}.jpg`;
  return variant === "master"
    ? `${CARD_IMAGE_ORIGIN}/${objectPath}`
    : `${CARD_IMAGE_ORIGIN}/cdn-cgi/image/${CARD_IMAGE_TRANSFORMS[variant]}/${objectPath}`;
}
