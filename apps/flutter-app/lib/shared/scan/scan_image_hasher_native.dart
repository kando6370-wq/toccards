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

  @override
  Future<ScanFrameDetection?> detectFrame(ScanCameraFrame frame) {
    return Isolate.run(() => _detectCameraFrame(frame));
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
      cardImageBytes: cardImageBytes,
    );
  } finally {
    canvas?.dispose();
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

ScanFrameDetection? _detectCameraFrame(ScanCameraFrame frame) {
  final image = _cameraFrameToBgr(frame);
  try {
    final corners = _detectCardCorners(image);
    return ScanFrameDetection(
      width: frame.width,
      height: frame.height,
      corners: [for (final point in corners) ScanImagePoint(point.x, point.y)],
    );
  } on ScanImageProcessingException {
    return null;
  } finally {
    image.dispose();
  }
}

cv.Mat _cameraFrameToBgr(ScanCameraFrame frame) {
  if (frame.format == ScanFrameFormat.jpeg && frame.planes.isNotEmpty) {
    return cv.imdecode(frame.planes.first.bytes, cv.IMREAD_COLOR);
  }
  final bgr = Uint8List(frame.width * frame.height * 3);
  if (frame.format == ScanFrameFormat.bgra8888 && frame.planes.length == 1) {
    final plane = frame.planes.first;
    for (var y = 0; y < frame.height; y += 1) {
      for (var x = 0; x < frame.width; x += 1) {
        final source = y * plane.bytesPerRow + x * plane.bytesPerPixel;
        final target = (y * frame.width + x) * 3;
        bgr[target] = plane.bytes[source];
        bgr[target + 1] = plane.bytes[source + 1];
        bgr[target + 2] = plane.bytes[source + 2];
      }
    }
    return cv.Mat.fromList(frame.height, frame.width, cv.MatType.CV_8UC3, bgr);
  }
  if (frame.format != ScanFrameFormat.yuv420 || frame.planes.length < 3) {
    throw const ScanImageProcessingException(
      'Unsupported camera frame format.',
    );
  }
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  for (var y = 0; y < frame.height; y += 1) {
    for (var x = 0; x < frame.width; x += 1) {
      final luminance = yPlane
          .bytes[y * yPlane.bytesPerRow + x * yPlane.bytesPerPixel]
          .toDouble();
      final chromaX = x ~/ 2;
      final chromaY = y ~/ 2;
      final u =
          uPlane
              .bytes[chromaY * uPlane.bytesPerRow +
                  chromaX * uPlane.bytesPerPixel]
              .toDouble() -
          128;
      final v =
          vPlane
              .bytes[chromaY * vPlane.bytesPerRow +
                  chromaX * vPlane.bytesPerPixel]
              .toDouble() -
          128;
      final target = (y * frame.width + x) * 3;
      bgr[target] = (luminance + 1.772 * u).round().clamp(0, 255);
      bgr[target + 1] = (luminance - 0.344136 * u - 0.714136 * v).round().clamp(
        0,
        255,
      );
      bgr[target + 2] = (luminance + 1.402 * v).round().clamp(0, 255);
    }
  }
  return cv.Mat.fromList(frame.height, frame.width, cv.MatType.CV_8UC3, bgr);
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
