import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_image_hasher.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

void main() {
  test(
    'native preprocessing matches the Python OpenCV reference because detection, perspective correction, and RGB channel order are part of the production index contract',
    () async {
      final hasher = createScanImageHasher();
      final hashes = await Future.wait([
        hasher.hash(_syntheticCardPpm()),
        hasher.hash(_syntheticCardPpm()),
      ]);

      for (final hash in hashes) {
        expect(hash.r, 'qxY0w2meSz0-aLTUPGngw2lrnNdhlsOgwZbLPMOWkzw');
        expect(hash.g, '7wNmh20pZwZtLZh4Mlpnh2ZsYwXGTczYzaWZy82TmMM');
        expect(hash.b, 'u0dMsDltLPE5LbNPOTizD2ZaTPA5jZMymYGzMpPHszI');
        final crop = cv.imdecode(hash.cardImageBytes!, cv.IMREAD_COLOR);
        try {
          expect((crop.cols, crop.rows), (745, 1043));
        } finally {
          crop.dispose();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: Platform.environment['DARTCV_LIB_PATH'] == null
        ? 'Requires the platform dartcv library.'
        : false,
  );
}

Uint8List _syntheticCardPpm() {
  const width = 240;
  const height = 360;
  final header = ascii.encode('P6\n$width $height\n255\n');
  final output = Uint8List(header.length + width * height * 3)
    ..setRange(0, header.length, header);
  var offset = header.length;
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      var red = 40;
      var green = 30;
      var blue = 20;
      if (x >= 30 && x <= 210 && y >= 40 && y <= 320) {
        if (x < 34 || x > 206 || y < 44 || y > 316) {
          red = green = blue = 245;
        } else {
          red = (x * 3 + y) % 256;
          green = (x + y * 2) % 256;
          blue = (x * 2 + y * 3) % 256;
        }
      }
      output[offset++] = red;
      output[offset++] = green;
      output[offset++] = blue;
    }
  }
  return output;
}
