import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/card_image/card_image_url.dart';

void main() {
  test('every display context uses the canonical card image URL', () {
    for (final variant in CardImageVariant.values) {
      expect(
        cardImageUrl('93', variant),
        'https://image.tcgcard.fun/cards/93.jpg',
      );
    }
  });
}
