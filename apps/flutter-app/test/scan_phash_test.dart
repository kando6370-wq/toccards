import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_phash.dart';

void main() {
  test('pHash matches the original Python imagehash bit ordering', () {
    final channel = Uint8List(1024 * 1024);
    for (var y = 0; y < 1024; y += 1) {
      for (var x = 0; x < 1024; x += 1) {
        channel[y * 1024 + x] = (x * 3 + y * 5 + (x * y) % 251) % 256;
      }
    }
    expect(encodeScanPhash(channel), '1cCign9zODpbOT4OfyiqgtDBqoBrPz07HT9-L0Q_Acg');
  });

  test('rectified RGB channels match the original Pillow letterbox hashes', () {
    const width = 745;
    const height = 1043;
    final pixels = Uint8List(width * height * 3);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final offset = (y * width + x) * 3;
        pixels[offset] = (x * 2 + y * 3) % 256;
        pixels[offset + 1] = (x + y * 2) % 256;
        pixels[offset + 2] = (x * 3 + y) % 256;
      }
    }
    final hashes = hashScanCardRgb(pixels, width: width, height: height);
    expect(hashes.r, 'r0DwL4Va4C-FWuAvhVrgL6Va8C8lWvAvhVrwL6V68C8');
    expect(hashes.g, 'rwLw06WO8NOljvDTpY7w06WO8NOlhvDRpYbw0aWG8NA');
    expect(hashes.b, 'r0Cleg_QpXoP0KV6D9Cleg_QWoXwL1qFWq9ahVql-hU');
  });
}
