import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/card_image/kando_card_image.dart';

void main() {
  testWidgets('missing card art uses the global Figma placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: KandoCardImage(imageUrl: null)),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, const AssetImage('assets/home/trend_placeholder.png'));
  });

  testWidgets('failed card art uses the same global Figma placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: KandoCardImage(imageUrl: 'https://invalid.test')),
    );

    final networkImage = tester.widget<Image>(find.byType(Image));
    final fallback = networkImage.errorBuilder!(
      tester.element(find.byType(Image)),
      Exception('card image failed'),
      StackTrace.empty,
    );
    await tester.pumpWidget(MaterialApp(home: fallback));

    final placeholder = tester.widget<Image>(find.byType(Image));
    expect(
      placeholder.image,
      const AssetImage('assets/home/trend_placeholder.png'),
    );
  });
}
