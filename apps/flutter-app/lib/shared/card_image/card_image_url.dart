enum CardImageVariant { thumbnail, list, detail, preview, master }

const _cardImageOrigin = 'https://image.tcgcard.fun';

const _cardImageTransforms = {
  CardImageVariant.thumbnail:
      'width=160,height=224,fit=scale-down,quality=60,format=auto,dpr=2',
  CardImageVariant.list:
      'width=360,height=504,fit=scale-down,quality=75,format=auto',
  CardImageVariant.detail:
      'width=600,height=800,fit=scale-down,quality=85,format=auto,sharpen=1',
  CardImageVariant.preview: 'width=1600,fit=scale-down,quality=92,format=auto',
};

String cardImageUrl(String cardRef, CardImageVariant variant) {
  final objectPath = 'cards/${Uri.encodeComponent(cardRef)}.jpg';
  if (variant == CardImageVariant.master) {
    return '$_cardImageOrigin/$objectPath';
  }
  return '$_cardImageOrigin/cdn-cgi/image/${_cardImageTransforms[variant]}/$objectPath';
}
