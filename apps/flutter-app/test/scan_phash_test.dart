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

  test(
    'RGB hashes match recognition.py because Pillow letterboxing is part of the production index contract',
    () {
      const width = 745;
      const height = 1043;

      String hashChannel(int Function(int x, int y) pixel) {
        final source = Uint8List(width * height);
        for (var y = 0; y < height; y += 1) {
          for (var x = 0; x < width; x += 1) {
            source[y * width + x] = pixel(x, y) % 256;
          }
        }
        return encodeScanPhash(
          letterboxScanChannelPillowLanczos(
            source,
            width: width,
            height: height,
          ),
        );
      }

      expect(
        hashChannel((x, y) => x * 2 + y * 3),
        'r0DwL4Va4C-FWuAvhVrgL6Va8C8lWvAvhVrwL6V68C8',
      );
      expect(
        hashChannel((x, y) => x + y * 2),
        'rwLw06WO8NOljvDTpY7w06WO8NOlhvDRpYbw0aWG8NA',
      );
      expect(
        hashChannel((x, y) => x * 3 + y),
        'r0Cleg_QpXoP0KV6D9Cleg_QWoXwL1qFWq9ahVql-hU',
      );
    },
  );
}
