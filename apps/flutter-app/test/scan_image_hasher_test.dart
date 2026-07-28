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
        expect(
          hash.diagnostics,
          isNot(contains('nested_card_surface')),
          reason: 'Ordinary cards must keep using the established crop path.',
        );
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

  test(
    'slab detection keeps the enclosed card because grading-case edges must not replace the card boundary',
    () async {
      final hash = await createScanImageHasher().hash(_syntheticSlabPng());

      expect(hash.diagnostics['area_ratio'], closeTo(0.048, 0.01));
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: Platform.environment['DARTCV_LIB_PATH'] == null
        ? 'Requires the platform dartcv library.'
        : false,
  );

  test(
    'grading-label recovery excludes the label because fragmented card edges must still hash the card slot',
    () async {
      final hash = await createScanImageHasher().hash(
        _syntheticLabeledSlabPng(),
      );

      expect(hash.diagnostics['slab_card_recovery'], 1.0);
      expect(hash.diagnostics['slab_frame_area_ratio'], greaterThan(0.80));
      expect(
        hash.diagnostics['area_ratio'],
        closeTo(0.39, 0.03),
        reason: 'Actual diagnostics: ${hash.diagnostics}',
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: Platform.environment['DARTCV_LIB_PATH'] == null
        ? 'Requires the platform dartcv library.'
        : false,
  );

  test(
    'landscape artwork recovery keeps the full card because an internal art panel must not become the recognition crop',
    () async {
      final hash = await createScanImageHasher().hash(
        _syntheticLandscapePanelPng(),
      );

      expect(hash.diagnostics['landscape_panel_recovery'], 1.0);
      expect(hash.diagnostics['pre_recovery_area_ratio'], lessThan(0.25));
      expect(hash.diagnostics['area_ratio'], closeTo(0.39, 0.05));
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
        final sampleName = file.path.split(Platform.pathSeparator).last;
        if ({
          'IMG_3799.jpg',
          'IMG_3801.jpg',
          'IMG_3804.jpg',
          'IMG_3807.jpg',
          'xy-p.PNG',
        }.contains(sampleName)) {
          expect(
            hash.diagnostics['card_surface_expansion'],
            1.0,
            reason:
                '$sampleName must preserve the title and full card surface inside its holder.',
          );
        }
        if (sampleName == 'IMG_3806.jpg') {
          expect(
            hash.diagnostics['right_edge_inset'],
            1.0,
            reason: 'Binder texture must not enter the recognition crop.',
          );
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

Uint8List _syntheticSlabPng() {
  final background = cv.Scalar.all(40);
  final parentColor = cv.Scalar.all(60);
  final parentBorder = cv.Scalar.all(68);
  final black = cv.Scalar.all(0);
  final white = cv.Scalar.all(255);
  final parent = cv.Rect(120, 90, 261, 371);
  final child = cv.Rect(200, 190, 101, 141);
  final image = cv.Mat.fromScalar(600, 500, cv.MatType.CV_8UC3, background);
  try {
    cv.rectangle(image, parent, parentColor, thickness: -1);
    cv.rectangle(image, parent, parentBorder, thickness: 3);
    cv.rectangle(image, child, black, thickness: 4);
    for (var y = 205; y < 320; y += 12) {
      final start = cv.Point(210, y);
      final end = cv.Point(290, y);
      try {
        cv.line(image, start, end, white, thickness: 2);
      } finally {
        end.dispose();
        start.dispose();
      }
    }
    final (encoded, bytes) = cv.imencode('.png', image);
    if (!encoded) {
      throw StateError('Synthetic slab image could not be encoded.');
    }
    return Uint8List.fromList(bytes);
  } finally {
    image.dispose();
    child.dispose();
    parent.dispose();
    white.dispose();
    black.dispose();
    parentBorder.dispose();
    parentColor.dispose();
    background.dispose();
  }
}

Uint8List _syntheticLabeledSlabPng() {
  final background = cv.Scalar.all(35);
  final slab = cv.Scalar.all(75);
  final slabBorder = cv.Scalar.all(230);
  final label = cv.Scalar.all(245);
  final labelBorder = cv.Scalar(40, 40, 210, 0);
  final black = cv.Scalar.all(20);
  final cardLine = cv.Scalar(180, 90, 220, 0);
  final slabRect = cv.Rect(35, 10, 430, 680);
  final labelRect = cv.Rect(70, 55, 360, 115);
  final image = cv.Mat.fromScalar(700, 500, cv.MatType.CV_8UC3, background);
  try {
    cv.rectangle(image, slabRect, slab, thickness: -1);
    cv.rectangle(image, slabRect, slabBorder, thickness: 6);
    cv.rectangle(image, labelRect, label, thickness: -1);
    cv.rectangle(image, labelRect, labelBorder, thickness: 4);
    for (var y = 75; y < 155; y += 18) {
      cv.line(image, cv.Point(90, y), cv.Point(410, y), black, thickness: 5);
    }
    for (var y = 220; y < 630; y += 22) {
      cv.line(
        image,
        cv.Point(105 + y % 44, y),
        cv.Point(395 - y % 33, y),
        cardLine,
        thickness: 9,
      );
    }
    for (var x = 130; x < 390; x += 45) {
      cv.line(
        image,
        cv.Point(x, 245),
        cv.Point(x + 35, 590),
        cardLine,
        thickness: 7,
      );
    }
    final (encoded, bytes) = cv.imencode('.png', image);
    if (!encoded) {
      throw StateError('Synthetic labeled slab image could not be encoded.');
    }
    return Uint8List.fromList(bytes);
  } finally {
    image.dispose();
    labelRect.dispose();
    slabRect.dispose();
    cardLine.dispose();
    black.dispose();
    labelBorder.dispose();
    label.dispose();
    slabBorder.dispose();
    slab.dispose();
    background.dispose();
  }
}

Uint8List _syntheticLandscapePanelPng() {
  final background = cv.Scalar.all(35);
  final holder = cv.Scalar.all(70);
  final holderBorder = cv.Scalar.all(235);
  final panel = cv.Scalar(220, 150, 70, 0);
  final panelBorder = cv.Scalar.all(245);
  final text = cv.Scalar.all(15);
  final holderRect = cv.Rect(45, 10, 410, 575);
  final panelRect = cv.Rect(105, 75, 290, 205);
  final image = cv.Mat.fromScalar(600, 500, cv.MatType.CV_8UC3, background);
  try {
    cv.rectangle(image, holderRect, holder, thickness: -1);
    cv.rectangle(image, holderRect, holderBorder, thickness: 6);
    cv.rectangle(image, panelRect, panel, thickness: -1);
    cv.rectangle(image, panelRect, panelBorder, thickness: 5);
    for (var y = 310; y < 475; y += 24) {
      cv.line(image, cv.Point(120, y), cv.Point(380, y), text, thickness: 5);
    }
    final (encoded, bytes) = cv.imencode('.png', image);
    if (!encoded) {
      throw StateError('Synthetic landscape-panel image could not be encoded.');
    }
    return Uint8List.fromList(bytes);
  } finally {
    image.dispose();
    panelRect.dispose();
    holderRect.dispose();
    text.dispose();
    panelBorder.dispose();
    panel.dispose();
    holderBorder.dispose();
    holder.dispose();
    background.dispose();
  }
}
