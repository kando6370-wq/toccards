import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/card_image/card_image_url.dart';

void main() {
  test('display variants are transformed while exact image work uses R2 master', () {
    expect(
      cardImageUrl('93', CardImageVariant.thumbnail),
      contains(
        '/cdn-cgi/image/width=160,height=224,fit=scale-down,quality=60,format=auto,dpr=2/cards/93.jpg',
      ),
    );
    expect(
      cardImageUrl('93', CardImageVariant.list),
      contains(
        '/cdn-cgi/image/width=360,height=504,fit=scale-down,quality=50,format=auto/cards/93.jpg',
      ),
    );
    expect(
      cardImageUrl('93', CardImageVariant.detail),
      contains(
        '/cdn-cgi/image/width=600,height=800,fit=scale-down,quality=85,format=auto,sharpen=1/cards/93.jpg',
      ),
    );
    expect(
      cardImageUrl('93', CardImageVariant.preview),
      contains(
        '/cdn-cgi/image/width=1600,fit=scale-down,quality=92,format=auto/cards/93.jpg',
      ),
    );
    expect(
      cardImageUrl('93', CardImageVariant.master),
      'https://image.tcgcard.fun/cards/93.jpg',
    );
  });
}
