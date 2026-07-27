import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_image_hasher.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

void main() {
  test(
    'camera crop maps the visible preview back to the sensor image because recognition must use the same card area shown inside the viewfinder',
    () {
      const crop = ScanImageCrop(
        left: 55 / 390,
        top: 163 / 844,
        width: 280 / 390,
        height: 400 / 844,
        viewportAspectRatio: 390 / 844,
      );

      final resolved = crop.resolve(imageWidth: 3024, imageHeight: 4032);

      expect(resolved.x, greaterThan(0));
      expect(resolved.y, greaterThan(0));
      expect(resolved.x + resolved.width, lessThan(3024));
      expect(resolved.y + resolved.height, lessThan(4032));
      expect(resolved.width / resolved.height, closeTo(280 / 400, 0.01));
    },
  );

  test(
    'native preprocessing matches the Python OpenCV reference because detection, perspective correction, and RGB channel order are part of the production index contract',
    () async {
      final hasher = createScanImageHasher();
      final hashes = await Future.wait([
        hasher.hash(_syntheticCardPpm()),
        hasher.hash(_syntheticCardPpm()),
      ]);

      for (final hash in hashes) {
        expect(hash.r, '-0KssPngU1KG5xdNhhjzT9YdE8WGWLdOhh1atYYdPeA');
        expect(hash.g, '6xJl_MnwZfjLUp4HPa2eBRkvmXSzpZtksaFDQpYXLGw');
        expect(hash.b, 'ulJNH5h4TR-YeE0LmHqz8MYp8_DGafLSxnjw0oWFTzI');
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

  final sampleDirectory = Platform.environment['SCAN_TEST_IMAGE_DIR'];
  test(
    'real card samples remain detectable because production camera and gallery images must reach the fixed-size hashing contract',
    () async {
      final files = Directory(sampleDirectory!)
          .listSync()
          .whereType<File>()
          .where(
            (file) => RegExp(
              r'\.(jpe?g|png)$',
              caseSensitive: false,
            ).hasMatch(file.path),
          )
          .toList();
      expect(files, isNotEmpty);
      final hasher = createScanImageHasher();
      for (final file in files) {
        late final ScanImageHashes hash;
        try {
          hash = await hasher.hash(await file.readAsBytes());
        } catch (error) {
          fail('${file.path}: $error');
        }
        final crop = cv.imdecode(hash.cardImageBytes!, cv.IMREAD_COLOR);
        try {
          expect((crop.cols, crop.rows), (745, 1043), reason: file.path);
        } finally {
          crop.dispose();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip:
        sampleDirectory == null ||
            Platform.environment['DARTCV_LIB_PATH'] == null
        ? 'Requires SCAN_TEST_IMAGE_DIR and the platform dartcv library.'
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
