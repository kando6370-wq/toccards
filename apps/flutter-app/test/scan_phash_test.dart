import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_phash.dart';

void main() {
  test(
    'pHash matches the Python imagehash reference because a valid request with different resize or bit ordering always misses production cards',
    () {
      final channel = Uint8List(1024 * 1024);
      for (var y = 0; y < 1024; y += 1) {
        for (var x = 0; x < 1024; x += 1) {
          channel[y * 1024 + x] = (x * 3 + y * 5 + (x * y) % 251) % 256;
        }
      }

      expect(
        encodeScanPhash(channel),
        '1cCign9zODpbOT4OfyiqgtDBqoBrPz07HT9-L0Q_Acg',
      );
    },
  );
}
