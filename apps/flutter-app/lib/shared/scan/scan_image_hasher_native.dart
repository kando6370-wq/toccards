import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'scan_image_hasher_contract.dart';
import 'scan_phash.dart';

const _cardWidth = 745;
const _cardHeight = 1043;
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
  try {
    final corners = _detectCardCorners(decoded);
    card = _warpCard(decoded, corners);
    rgb = cv.cvtColor(card, cv.COLOR_BGR2RGB);
    final parameters = [cv.IMWRITE_JPEG_QUALITY, 85].i32;
    late final Uint8List cardImageBytes;
    try {
      final (encoded, buffer) = cv.imencode('.jpg', card, params: parameters);
      if (!encoded) {
        throw const ScanImageProcessingException(
          'The corrected card image could not be encoded.',
        );
      }
      cardImageBytes = Uint8List.fromList(buffer);
    } finally {
      parameters.dispose();
    }

    final sourcePixelCount = rgb.rows * rgb.cols;
    final sourceRed = Uint8List(sourcePixelCount);
    final sourceGreen = Uint8List(sourcePixelCount);
    final sourceBlue = Uint8List(sourcePixelCount);
    final pixels = rgb.data;
    for (var index = 0; index < sourcePixelCount; index += 1) {
      final offset = index * 3;
      sourceRed[index] = pixels[offset];
      sourceGreen[index] = pixels[offset + 1];
      sourceBlue[index] = pixels[offset + 2];
    }

    final red = letterboxScanChannelPillowLanczos(
      sourceRed,
      width: rgb.cols,
      height: rgb.rows,
    );
    final green = letterboxScanChannelPillowLanczos(
      sourceGreen,
      width: rgb.cols,
      height: rgb.rows,
    );
    final blue = letterboxScanChannelPillowLanczos(
      sourceBlue,
      width: rgb.cols,
      height: rgb.rows,
    );

    return ScanImageHashes(
      r: encodeScanPhash(red),
      g: encodeScanPhash(green),
      b: encodeScanPhash(blue),
      cardImageBytes: cardImageBytes,
    );
  } finally {
    rgb?.dispose();
    card?.dispose();
    decoded.dispose();
  }
}

List<_ImagePoint> _detectCardCorners(cv.Mat image) {
  const maximumDimension = 960;
  final scale = math.min(
    1.0,
    maximumDimension / math.max(image.cols, image.rows),
  );
  cv.Mat? resized;
  final working = scale < 1
      ? (resized = cv.resize(image, (
          (image.cols * scale).round(),
          (image.rows * scale).round(),
        ), interpolation: cv.INTER_AREA))
      : image;
  final gray = cv.cvtColor(working, cv.COLOR_BGR2GRAY);
  final blurred = cv.gaussianBlur(gray, (5, 5), 0);
  final (_, threshold) = cv.threshold(
    blurred,
    0,
    255,
    cv.THRESH_BINARY_INV + cv.THRESH_OTSU,
  );
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
  final closed = cv.morphologyEx(threshold, cv.MORPH_CLOSE, kernel);
  final (contours, hierarchy) = cv.findContours(
    closed,
    cv.RETR_EXTERNAL,
    cv.CHAIN_APPROX_SIMPLE,
  );
  try {
    final minimumArea = working.rows * working.cols * 0.04;
    var bestScore = 0.0;
    List<_ImagePoint>? best;
    for (var index = 0; index < contours.length; index += 1) {
      final contour = contours[index];
      final area = cv.contourArea(contour).abs();
      if (area < minimumArea) continue;
      final rectangle = cv.minAreaRect(contour);
      final rectangleWidth = rectangle.size.width;
      final rectangleHeight = rectangle.size.height;
      if (rectangleWidth < 1 || rectangleHeight < 1) continue;
      final shortSide = math.min(rectangleWidth, rectangleHeight);
      final longSide = math.max(rectangleWidth, rectangleHeight);
      final aspect = shortSide / longSide;
      final extent = area / (rectangleWidth * rectangleHeight);
      const cardRatio = _cardWidth / _cardHeight;
      final aspectScore = math.max(
        0.0,
        1 - (aspect - cardRatio).abs() / cardRatio,
      );
      final score = area * extent * aspectScore;
      if (score <= bestScore) continue;
      final box = cv.boxPoints(rectangle);
      try {
        final ordered = _orderCorners([
          for (var pointIndex = 0; pointIndex < box.length; pointIndex += 1)
            _ImagePoint(box[pointIndex].x / scale, box[pointIndex].y / scale),
        ]);
        bestScore = score;
        best = ordered;
      } finally {
        box.dispose();
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
    closed.dispose();
    kernel.dispose();
    threshold.dispose();
    blurred.dispose();
    gray.dispose();
    resized?.dispose();
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
