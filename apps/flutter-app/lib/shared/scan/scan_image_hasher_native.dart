import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'scan_image_hasher_contract.dart';
import 'scan_phash.dart';

const _cardWidth = 745;
const _cardHeight = 1043;
const _canvasSize = 1024;

ScanImageHasher createScanImageHasher() => _OpenCvScanImageHasher();

class _OpenCvScanImageHasher implements ScanImageHasher {
  Future<void> _tail = Future.value();

  @override
  Future<ScanImageHashes> hash(Uint8List imageBytes) {
    final result = Completer<ScanImageHashes>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await _runHashIsolate(imageBytes));
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

Future<ScanImageHashes> _runHashIsolate(Uint8List imageBytes) {
  return Isolate.run(() => _hashImage(imageBytes));
}

ScanImageHashes _hashImage(Uint8List imageBytes) {
  final decoded = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
  if (decoded.isEmpty) {
    decoded.dispose();
    throw const ScanImageProcessingException('The selected image is invalid.');
  }

  cv.Mat? card;
  cv.Mat? rgb;
  cv.Mat? canvas;
  try {
    final corners = _detectCardCorners(decoded);
    card = _warpCard(decoded, corners);
    rgb = cv.cvtColor(card, cv.COLOR_BGR2RGB);
    canvas = _letterbox(rgb);

    final pixelCount = _canvasSize * _canvasSize;
    final red = Uint8List(pixelCount);
    final green = Uint8List(pixelCount);
    final blue = Uint8List(pixelCount);
    final pixels = canvas.data;
    for (var index = 0; index < pixelCount; index += 1) {
      final offset = index * 3;
      red[index] = pixels[offset];
      green[index] = pixels[offset + 1];
      blue[index] = pixels[offset + 2];
    }

    return ScanImageHashes(
      r: encodeScanPhash(red),
      g: encodeScanPhash(green),
      b: encodeScanPhash(blue),
    );
  } finally {
    canvas?.dispose();
    rgb?.dispose();
    card?.dispose();
    decoded.dispose();
  }
}

List<_ImagePoint> _detectCardCorners(cv.Mat image) {
  final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
  final blurred = cv.gaussianBlur(gray, (5, 5), 0);
  final edges = cv.canny(blurred, 75, 200);
  final (contours, hierarchy) = cv.findContours(
    edges,
    cv.RETR_EXTERNAL,
    cv.CHAIN_APPROX_SIMPLE,
  );
  try {
    final minimumArea = image.rows * image.cols * 0.12;
    var bestArea = 0.0;
    List<_ImagePoint>? best;
    for (var index = 0; index < contours.length; index += 1) {
      final contour = contours[index];
      final area = cv.contourArea(contour).abs();
      if (area < minimumArea || area <= bestArea) continue;
      final perimeter = cv.arcLength(contour, true);
      final polygon = cv.approxPolyDP(contour, perimeter * 0.02, true);
      try {
        if (polygon.length != 4 || !cv.isContourConvex(polygon)) continue;
        final ordered = _orderCorners([
          for (var pointIndex = 0; pointIndex < polygon.length; pointIndex += 1)
            _ImagePoint(
              polygon[pointIndex].x.toDouble(),
              polygon[pointIndex].y.toDouble(),
            ),
        ]);
        final width = math.max(
          _distance(ordered[0], ordered[1]),
          _distance(ordered[3], ordered[2]),
        );
        final height = math.max(
          _distance(ordered[0], ordered[3]),
          _distance(ordered[1], ordered[2]),
        );
        final aspect = math.min(width, height) / math.max(width, height);
        if (aspect < 0.5 || aspect > 0.85) continue;
        bestArea = area;
        best = ordered;
      } finally {
        polygon.dispose();
      }
    }
    if (best == null) {
      throw const ScanImageProcessingException(
        'Keep one card fully visible inside the frame and try again.',
      );
    }
    return best;
  } finally {
    hierarchy.dispose();
    contours.dispose();
    edges.dispose();
    blurred.dispose();
    gray.dispose();
  }
}

List<_ImagePoint> _orderCorners(List<_ImagePoint> points) {
  final topLeft = points.reduce(
    (left, right) => left.x + left.y < right.x + right.y ? left : right,
  );
  final bottomRight = points.reduce(
    (left, right) => left.x + left.y > right.x + right.y ? left : right,
  );
  final topRight = points.reduce(
    (left, right) => left.x - left.y > right.x - right.y ? left : right,
  );
  final bottomLeft = points.reduce(
    (left, right) => left.x - left.y < right.x - right.y ? left : right,
  );
  final ordered = [topLeft, topRight, bottomRight, bottomLeft];
  if (ordered.toSet().length != 4) {
    throw const ScanImageProcessingException(
      'The card corners could not be detected.',
    );
  }
  return ordered;
}

cv.Mat _warpCard(cv.Mat image, List<_ImagePoint> corners) {
  final sourceWidth = math.max(
    _distance(corners[0], corners[1]),
    _distance(corners[3], corners[2]),
  );
  final sourceHeight = math.max(
    _distance(corners[0], corners[3]),
    _distance(corners[1], corners[2]),
  );
  final landscape = sourceWidth > sourceHeight;
  final width = landscape ? _cardHeight : _cardWidth;
  final height = landscape ? _cardWidth : _cardHeight;
  final source = cv.VecPoint2f.generate(
    4,
    (index) => cv.Point2f(corners[index].x, corners[index].y),
  );
  final target = cv.VecPoint2f.generate(
    4,
    (index) => switch (index) {
      0 => cv.Point2f(0, 0),
      1 => cv.Point2f(width - 1, 0),
      2 => cv.Point2f(width - 1, height - 1),
      _ => cv.Point2f(0, height - 1),
    },
  );
  final transform = cv.getPerspectiveTransform2f(source, target);
  final border = cv.Scalar.all(255);
  try {
    final warped = cv.warpPerspective(
      image,
      transform,
      (width, height),
      flags: cv.INTER_LINEAR,
      borderMode: cv.BORDER_CONSTANT,
      borderValue: border,
    );
    if (!landscape) return warped;
    try {
      return cv.rotate(warped, cv.ROTATE_90_COUNTERCLOCKWISE);
    } finally {
      warped.dispose();
    }
  } finally {
    border.dispose();
    transform.dispose();
    target.dispose();
    source.dispose();
  }
}

cv.Mat _letterbox(cv.Mat image) {
  final scale = math.min(_canvasSize / image.cols, _canvasSize / image.rows);
  final width = (image.cols * scale).round();
  final height = (image.rows * scale).round();
  final resized = cv.resize(image, (
    width,
    height,
  ), interpolation: cv.INTER_LANCZOS4);
  final white = cv.Scalar.all(255);
  final canvas = cv.Mat.fromScalar(
    _canvasSize,
    _canvasSize,
    cv.MatType.CV_8UC3,
    white,
  );
  final rectangle = cv.Rect(
    (_canvasSize - width) ~/ 2,
    (_canvasSize - height) ~/ 2,
    width,
    height,
  );
  final region = canvas.region(rectangle);
  try {
    resized.copyTo(region);
    return canvas;
  } catch (_) {
    canvas.dispose();
    rethrow;
  } finally {
    region.dispose();
    rectangle.dispose();
    white.dispose();
    resized.dispose();
  }
}

double _distance(_ImagePoint left, _ImagePoint right) {
  return math.sqrt(
    math.pow(left.x - right.x, 2) + math.pow(left.y - right.y, 2),
  );
}

class _ImagePoint {
  const _ImagePoint(this.x, this.y);

  final double x;
  final double y;
}
