enum CardImageVariant { thumbnail, list, detail, preview, master }

const _cardImageOrigin = 'https://image.tcgcard.fun';

String cardImageUrl(String cardRef, CardImageVariant _) {
  final objectPath = 'cards/${Uri.encodeComponent(cardRef)}.jpg';
  return '$_cardImageOrigin/$objectPath';
}
