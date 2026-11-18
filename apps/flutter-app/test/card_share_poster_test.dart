import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/card_detail/card_share_poster.dart';

import 'support/load_inter_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadInterFonts();
    final fraunces = FontLoader('Fraunces')
      ..addFont(
        rootBundle.load('assets/fonts/Baskerville-BaskervilleSemiBold.ttf'),
      );
    await fraunces.load();
  });

  test(
    'poster is a fixed PNG with card artwork and a high-contrast QR panel',
    () async {
      final poster = await renderCardSharePoster(
        imageBytes: await _testCardPng(),
        name: 'Charizard ex',
        setName: 'Obsidian Flames',
        marketPrice: r'$780.00',
        cardUrl: Uri.parse('https://api.tcgcard.fun/share/cards/560537'),
      );

      expect(
        poster.take(8),
        orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      );
      final image = await _decode(poster);
      try {
        expect(image.width, cardSharePosterWidth);
        expect(image.height, cardSharePosterHeight);
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;

        // The synthetic red card remains visible inside the poster's card frame.
        expect(_pixel(rgba, image.width, 540, 600), const [220, 32, 32, 255]);

        // The QR panel contains both its white quiet zone and black modules.
        final qrColors = <int>{};
        for (var y = 1518; y < 1842; y += 6) {
          for (var x = 132; x < 456; x += 6) {
            final pixel = _pixel(rgba, image.width, x, y);
            if (pixel[0] < 24 && pixel[1] < 24 && pixel[2] < 24) {
              qrColors.add(0);
            }
            if (pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240) {
              qrColors.add(1);
            }
          }
        }
        expect(qrColors, {0, 1});
      } finally {
        image.dispose();
      }
    },
  );

  test(
    'long identity and price stay inside the poster without truncating the amount',
    () async {
      final poster = await renderCardSharePoster(
        imageBytes: await _testCardPng(),
        name:
            'A deliberately long trading card name that must stay inside two lines',
        setName: 'A deliberately long set name that must be truncated',
        marketPrice: r'$123,456,789.00',
        cardUrl: Uri.parse(
          'https://api.tcgcard.fun/share/cards/pokemon%3Asv3%3A125',
        ),
      );
      final image = await _decode(poster);
      try {
        expect(image.width, cardSharePosterWidth);
        expect(image.height, cardSharePosterHeight);
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var moneyPixelsBeforeFormerNarrowColumn = 0;
        var moneyPixelsAfterFormerNarrowColumn = 0;
        for (var y = 1300; y < 1455; y += 2) {
          for (var x = 60; x < 1020; x += 2) {
            final pixel = _pixel(rgba, image.width, x, y);
            final isMoneyText =
                pixel[0] > 235 &&
                pixel[1] > 220 &&
                pixel[2] > 135 &&
                pixel[2] < 220;
            if (!isMoneyText) continue;
            if (x < 480) {
              moneyPixelsBeforeFormerNarrowColumn++;
            } else {
              moneyPixelsAfterFormerNarrowColumn++;
            }
          }
        }
        expect(moneyPixelsBeforeFormerNarrowColumn, greaterThan(10));
        expect(moneyPixelsAfterFormerNarrowColumn, greaterThan(10));
      } finally {
        image.dispose();
      }
    },
  );

  test('empty or invalid poster inputs fail explicitly', () async {
    await expectLater(
      renderCardSharePoster(
        imageBytes: Uint8List(0),
        name: 'Switch',
        setName: 'Deck Exclusives',
        marketPrice: r'$0.27',
        cardUrl: Uri.parse('https://example.com/card'),
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      renderCardSharePoster(
        imageBytes: await _testCardPng(),
        name: 'Switch',
        setName: 'Deck Exclusives',
        marketPrice: r'$0.27',
        cardUrl: Uri(path: '/relative-card'),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<Uint8List> _testCardPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 200, 280),
    ui.Paint()..color = const ui.Color(0xFFDC2020),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 280);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

List<int> _pixel(ByteData data, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return [
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
    data.getUint8(offset + 3),
  ];
}
