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
  Future<ScanImageHashes> hash(Uint8List imageBytes, {ScanImageCrop? crop}) {
    final result = Completer<ScanImageHashes>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await _runHashIsolate(imageBytes, crop));
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

Future<ScanImageHashes> _runHashIsolate(
  Uint8List imageBytes,
  ScanImageCrop? crop,
) {
  return Isolate.run(() => _hashImage(imageBytes, crop));
}

ScanImageHashes _hashImage(Uint8List imageBytes, ScanImageCrop? crop) {
  final decoded = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
  if (decoded.isEmpty) {
    decoded.dispose();
    throw const ScanImageProcessingException('The selected image is invalid.');
  }

  cv.Mat? cropped;
  cv.Mat? card;
  cv.Mat? rgb;
  try {
    final source = crop == null
        ? decoded
        : (cropped = _cropImage(decoded, crop));
    final corners = _detectCardCorners(source);
    card = _warpCard(source, corners);
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
    cropped?.dispose();
    decoded.dispose();
  }
}

cv.Mat _cropImage(cv.Mat image, ScanImageCrop crop) {
  final resolved = crop.resolve(
    imageWidth: image.cols,
    imageHeight: image.rows,
  );
  final rectangle = cv.Rect(
    resolved.x,
    resolved.y,
    resolved.width,
    resolved.height,
  );
  try {
    return image.region(rectangle);
  } finally {
    rectangle.dispose();
  }
}

List<_ImagePoint> _detectCardCorners(cv.Mat image) {
  const maximumDimension = 1600;
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
  final clahe = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
  final enhanced = clahe.apply(gray);
  final blurred = cv.gaussianBlur(enhanced, (5, 5), 0);
  final lab = cv.cvtColor(working, cv.COLOR_BGR2Lab);
  final channels = cv.split(lab);
  final masks = <cv.Mat>[
    cv.adaptiveThreshold(
      blurred,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      31,
      5,
    ),
    cv.canny(blurred, 25, 85),
    cv.canny(blurred, 55, 165),
  ];
  for (var index = 0; index < channels.length; index += 1) {
    final (_, normal) = cv.threshold(
      channels[index],
      0,
      255,
      cv.THRESH_BINARY + cv.THRESH_OTSU,
    );
    final (_, inverse) = cv.threshold(
      channels[index],
      0,
      255,
      cv.THRESH_BINARY_INV + cv.THRESH_OTSU,
    );
    masks
      ..add(normal)
      ..add(inverse);
  }
  final candidates = <_CardCandidate>[];
  try {
    for (final mask in masks) {
      for (final kernelSize in const [3, 7]) {
        final kernel = cv.getStructuringElement(cv.MORPH_RECT, (
          kernelSize,
          kernelSize,
        ));
        final closed = cv.morphologyEx(mask, cv.MORPH_CLOSE, kernel);
        final (contours, hierarchy) = cv.findContours(
          closed,
          cv.RETR_LIST,
          cv.CHAIN_APPROX_SIMPLE,
        );
        try {
          for (var index = 0; index < contours.length; index += 1) {
            _addContourCandidates(
              contours[index],
              working,
              lab,
              gray,
              candidates,
            );
          }
        } finally {
          hierarchy.dispose();
          contours.dispose();
          closed.dispose();
          kernel.dispose();
        }
      }
    }
    final sourceAspect =
        math.min(working.cols, working.rows) /
        math.max(working.cols, working.rows);
    if ((math.log(sourceAspect / (_cardWidth / _cardHeight))).abs() <= 0.04) {
      _addCandidate(
        [
          const _ImagePoint(0, 0),
          _ImagePoint(working.cols - 1.0, 0),
          _ImagePoint(working.cols - 1.0, working.rows - 1.0),
          _ImagePoint(0, working.rows - 1.0),
        ],
        working,
        lab,
        gray,
        candidates,
        allowFullImage: true,
      );
    }
    if (candidates.isEmpty) {
      throw const ScanImageProcessingException(
        'Keep one card fully visible inside the frame and try again.',
      );
    }
    candidates.sort((left, right) => right.score.compareTo(left.score));
    var best = candidates.first;
    final imageArea = working.rows * working.cols;
    if (best.area / imageArea > 0.985) {
      final inset = candidates.where((candidate) {
        final ratio = candidate.area / imageArea;
        return ratio >= 0.80 &&
            ratio <= 0.985 &&
            candidate.aspectScore >= 0.78 &&
            candidate.score >= best.score - 0.08;
      }).toList()..sort((left, right) => right.score.compareTo(left.score));
      if (inset.isNotEmpty) best = inset.first;
    }
    for (final parent in candidates.skip(1)) {
      final ratio = parent.area / best.area;
      if (ratio >= 1.35 &&
          ratio <= 4.5 &&
          parent.aspectScore >= 0.78 &&
          parent.score >= best.score - 0.13 &&
          best.points
                  .where((point) => _contains(parent.points, point))
                  .length >=
              3) {
        best = parent;
        break;
      }
    }
    return [
      for (final point in best.points)
        _ImagePoint(point.x / scale, point.y / scale),
    ];
  } finally {
    for (final mask in masks) {
      mask.dispose();
    }
    channels.dispose();
    lab.dispose();
    blurred.dispose();
    enhanced.dispose();
    clahe.dispose();
    gray.dispose();
    resized?.dispose();
  }
}

void _addContourCandidates(
  cv.VecPoint contour,
  cv.Mat image,
  cv.Mat lab,
  cv.Mat gray,
  List<_CardCandidate> candidates,
) {
  final imageArea = image.rows * image.cols;
  final area = cv.contourArea(contour).abs();
  if (area < imageArea * 0.025 || area > imageArea * 0.96) return;
  final perimeter = cv.arcLength(contour, true);
  if (perimeter <= 0) return;
  var added = false;
  for (final epsilon in const [0.012, 0.02, 0.03, 0.045, 0.065, 0.09]) {
    final approximation = cv.approxPolyDP(contour, perimeter * epsilon, true);
    try {
      if (approximation.length != 4 || !cv.isContourConvex(approximation)) {
        continue;
      }
      _addCandidate(
        [
          for (var i = 0; i < 4; i++)
            _ImagePoint(
              approximation[i].x.toDouble(),
              approximation[i].y.toDouble(),
            ),
        ],
        image,
        lab,
        gray,
        candidates,
      );
      added = true;
      break;
    } finally {
      approximation.dispose();
    }
  }
  if (added) return;
  final rectangle = cv.minAreaRect(contour);
  final box = cv.boxPoints(rectangle);
  try {
    _addCandidate(
      [for (var i = 0; i < box.length; i++) _ImagePoint(box[i].x, box[i].y)],
      image,
      lab,
      gray,
      candidates,
    );
  } finally {
    box.dispose();
  }
}

void _addCandidate(
  List<_ImagePoint> raw,
  cv.Mat image,
  cv.Mat lab,
  cv.Mat gray,
  List<_CardCandidate> candidates, {
  bool allowFullImage = false,
}) {
  final points = _orderCorners(raw);
  final widths = [
    _distance(points[0], points[1]),
    _distance(points[3], points[2]),
  ];
  final heights = [
    _distance(points[0], points[3]),
    _distance(points[1], points[2]),
  ];
  final shortSide = math.min(widths.reduce(math.max), heights.reduce(math.max));
  final longSide = math.max(widths.reduce(math.max), heights.reduce(math.max));
  if (shortSide < 24 || longSide / shortSide > 2.4) return;
  final area = _polygonArea(points);
  final areaRatio = area / (image.rows * image.cols);
  if (areaRatio < 0.025 || (!allowFullImage && areaRatio > 0.97)) return;
  final aspect = shortSide / longSide;
  final aspectScore = math.exp(
    -4.0 * (math.log(aspect / (_cardWidth / _cardHeight))).abs(),
  );
  final rectangleArea = shortSide * longSide;
  final rectangularity = math.min(1.0, area / rectangleArea);
  final boundary = _edgeContrast(points, lab);
  final content = _contentRichness(points, gray);
  final border = _borderContrast(points, lab);
  final areaScore = math.min(1.0, areaRatio / 0.45);
  final touching = points
      .where(
        (p) =>
            p.x < 3 || p.y < 3 || p.x > image.cols - 4 || p.y > image.rows - 4,
      )
      .length;
  final score =
      0.31 * boundary +
      0.23 * aspectScore +
      0.14 * rectangularity +
      0.13 * areaScore +
      0.11 * content +
      0.08 * border -
      0.07 * (touching / 4);
  if (candidates.any(
    (candidate) => _cornerDistance(candidate.points, points) < 10,
  )) {
    return;
  }
  candidates.add(_CardCandidate(points, area, aspectScore, score));
}

double _edgeContrast(List<_ImagePoint> points, cv.Mat lab) =>
    _sampleBorder(points, lab, 2.0);
double _borderContrast(List<_ImagePoint> points, cv.Mat lab) =>
    _sampleBorder(points, lab, 7.0);

double _sampleBorder(List<_ImagePoint> points, cv.Mat lab, double offset) {
  var total = 0.0;
  var count = 0;
  for (var edge = 0; edge < 4; edge++) {
    final a = points[edge];
    final b = points[(edge + 1) % 4];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) continue;
    final nx = -dy / length;
    final ny = dx / length;
    for (var step = 1; step < 16; step++) {
      final x = a.x + dx * step / 16;
      final y = a.y + dy * step / 16;
      total += _labDistance(
        lab,
        x + nx * offset,
        y + ny * offset,
        x - nx * offset,
        y - ny * offset,
      );
      count++;
    }
  }
  return count == 0 ? 0 : math.min(1.0, total / count / 70);
}

double _labDistance(cv.Mat mat, double ax, double ay, double bx, double by) {
  int clampX(double x) => x.round().clamp(0, mat.cols - 1);
  int clampY(double y) => y.round().clamp(0, mat.rows - 1);
  final ai = (clampY(ay) * mat.cols + clampX(ax)) * 3;
  final bi = (clampY(by) * mat.cols + clampX(bx)) * 3;
  var sum = 0.0;
  for (var channel = 0; channel < 3; channel++) {
    final difference = mat.data[ai + channel] - mat.data[bi + channel];
    sum += difference * difference;
  }
  return math.sqrt(sum);
}

double _contentRichness(List<_ImagePoint> points, cv.Mat gray) {
  var total = 0.0;
  var count = 0;
  for (var yStep = 2; yStep < 18; yStep++) {
    for (var xStep = 2; xStep < 14; xStep++) {
      final top = _lerp(points[0], points[1], xStep / 16);
      final bottom = _lerp(points[3], points[2], xStep / 16);
      final point = _lerp(top, bottom, yStep / 20);
      final x = point.x.round().clamp(1, gray.cols - 2);
      final y = point.y.round().clamp(1, gray.rows - 2);
      final index = y * gray.cols + x;
      total +=
          (gray.data[index + 1] - gray.data[index - 1]).abs() +
          (gray.data[index + gray.cols] - gray.data[index - gray.cols]).abs();
      count++;
    }
  }
  return count == 0 ? 0 : math.min(1.0, total / count / 80);
}

_ImagePoint _lerp(_ImagePoint a, _ImagePoint b, double t) =>
    _ImagePoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
double _polygonArea(List<_ImagePoint> points) =>
    ((points[0].x * points[1].y +
                points[1].x * points[2].y +
                points[2].x * points[3].y +
                points[3].x * points[0].y) -
            (points[1].x * points[0].y +
                points[2].x * points[1].y +
                points[3].x * points[2].y +
                points[0].x * points[3].y))
        .abs() /
    2;
double _cornerDistance(List<_ImagePoint> a, List<_ImagePoint> b) =>
    List.generate(4, (i) => _distance(a[i], b[i])).reduce((x, y) => x + y) / 4;
bool _contains(List<_ImagePoint> polygon, _ImagePoint point) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % 4];
    final cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x);
    if (cross.abs() < 1e-6) continue;
    final current = cross > 0 ? 1 : -1;
    if (sign != 0 && current != sign) return false;
    sign = current;
  }
  return true;
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
      flags: cv.INTER_CUBIC,
      borderMode: cv.BORDER_REPLICATE,
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

class _CardCandidate {
  const _CardCandidate(this.points, this.area, this.aspectScore, this.score);
  final List<_ImagePoint> points;
  final double area;
  final double aspectScore;
  final double score;
}
