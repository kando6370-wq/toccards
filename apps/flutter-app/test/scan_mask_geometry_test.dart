import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_mask_geometry.dart';

void main() {
  test('fits and scales the largest rectangular mask component', () {
    const width = 20;
    const height = 20;
    final mask = Float32List(width * height);
    for (var y = 2; y <= 17; y += 1) {
      for (var x = 3; x <= 14; x += 1) {
        mask[y * width + x] = 1;
      }
    }
    mask[19 * width + 19] = 1;

    final result = fitScanMaskQuad(
      mask,
      maskOffset: 0,
      maskRows: height,
      maskCols: width,
      resizedWidth: width,
      resizedHeight: height,
      sourceWidth: 200,
      sourceHeight: 100,
    );

    expect(result, isNotNull);
    expect(result!.areaRatio, closeTo(165 / 400, 0.0001));
    expect(result.usedMinimumAreaRectangle, isFalse);
    expect(
      result.points.map((point) => (point.x, point.y)),
      [(30.0, 10.0), (140.0, 10.0), (140.0, 85.0), (30.0, 85.0)],
    );
  });

  test('rejects masks whose largest component is too small', () {
    final mask = Float32List(100);
    for (var y = 0; y < 3; y += 1) {
      for (var x = 0; x < 3; x += 1) {
        mask[y * 10 + x] = 1;
      }
    }

    expect(
      fitScanMaskQuad(
        mask,
        maskOffset: 0,
        maskRows: 10,
        maskCols: 10,
        resizedWidth: 10,
        resizedHeight: 10,
        sourceWidth: 10,
        sourceHeight: 10,
      ),
      isNull,
    );
  });

  test('orders arbitrary corners as top-left through bottom-left', () {
    final points = orderScanCorners(const [
      ScanImagePoint(90, 80),
      ScanImagePoint(10, 10),
      ScanImagePoint(5, 70),
      ScanImagePoint(100, 20),
    ]);

    expect(
      points.map((point) => (point.x, point.y)),
      [(10.0, 10.0), (100.0, 20.0), (90.0, 80.0), (5.0, 70.0)],
    );
  });
}
