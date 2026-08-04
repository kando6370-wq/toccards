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

  cv.Mat? card;
  cv.Mat? rgb;
  try {
    final cameraGuide = crop?.resolve(
      imageWidth: decoded.cols,
      imageHeight: decoded.rows,
    );
    final detection = _detectCardCorners(
      decoded,
      allowSourceImage: true,
      allowContainerRecovery: crop == null,
      cameraGuide: cameraGuide,
    );
    card = _warpCard(decoded, detection.corners);
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
      diagnostics: detection.diagnostics,
    );
  } finally {
    rgb?.dispose();
    card?.dispose();
    decoded.dispose();
  }
}

({List<_ImagePoint> corners, Map<String, double> diagnostics})
_detectCardCorners(
  cv.Mat image, {
  required bool allowSourceImage,
  required bool allowContainerRecovery,
  required ScanPixelCrop? cameraGuide,
}) {
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
  final scaledCameraGuide = cameraGuide == null
      ? null
      : _CameraGuide(
          left: cameraGuide.x * scale,
          top: cameraGuide.y * scale,
          width: cameraGuide.width * scale,
          height: cameraGuide.height * scale,
        );
  final gray = cv.cvtColor(working, cv.COLOR_BGR2GRAY);
  final clahe = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
  final enhanced = clahe.apply(gray);
  final blurred = cv.gaussianBlur(enhanced, (5, 5), 0);
  final lab = cv.cvtColor(working, cv.COLOR_BGR2Lab);
  final channels = cv.split(lab);
  final gradient = _buildGradient(channels);
  final gradientHigh = _gradientPercentile(gradient, 0.99);
  final median = _medianU8(blurred);
  final masks = <cv.Mat>[];
  for (final thresholds in [
    (
      math.max(10, (0.55 * median).floor()),
      math.min(255, (1.35 * median).floor()),
    ),
    (25, 85),
    (55, 165),
  ]) {
    final edge = cv.canny(
      blurred,
      thresholds.$1.toDouble(),
      math.max(thresholds.$2, thresholds.$1 + 1).toDouble(),
      l2gradient: true,
    );
    for (final kernelSize in const [3, 7]) {
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (
        kernelSize,
        kernelSize,
      ));
      masks.add(cv.morphologyEx(edge, cv.MORPH_CLOSE, kernel));
      kernel.dispose();
    }
    edge.dispose();
  }
  for (var index = 0; index < channels.length; index += 1) {
    final smooth = cv.gaussianBlur(channels[index], (7, 7), 0);
    final (_, normal) = cv.threshold(
      smooth,
      0,
      255,
      cv.THRESH_BINARY + cv.THRESH_OTSU,
    );
    final (_, inverse) = cv.threshold(
      smooth,
      0,
      255,
      cv.THRESH_BINARY_INV + cv.THRESH_OTSU,
    );
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (7, 7));
    masks
      ..add(cv.morphologyEx(normal, cv.MORPH_CLOSE, kernel, iterations: 2))
      ..add(cv.morphologyEx(inverse, cv.MORPH_CLOSE, kernel, iterations: 2));
    kernel.dispose();
    normal.dispose();
    inverse.dispose();
    smooth.dispose();
  }
  final candidates = <_CardCandidate>[];
  try {
    for (final mask in masks) {
      final (contours, hierarchy) = cv.findContours(
        mask,
        cv.RETR_LIST,
        cv.CHAIN_APPROX_SIMPLE,
      );
      try {
        for (var index = 0; index < contours.length; index += 1) {
          _addContourCandidates(
            contours[index],
            working,
            gradient,
            gradientHigh,
            candidates,
            allowMissingCornerRecovery: allowContainerRecovery,
          );
        }
      } finally {
        hierarchy.dispose();
        contours.dispose();
      }
    }
    candidates.sort((left, right) => right.score.compareTo(left.score));
    final deduplicated = _deduplicateCandidates(candidates);
    final sourceAspect =
        math.min(working.cols, working.rows) /
        math.max(working.cols, working.rows);
    if (allowSourceImage &&
        (math.log(sourceAspect / (_cardWidth / _cardHeight))).abs() <= 0.04) {
      final aspectError = (math.log(
        sourceAspect / (_cardWidth / _cardHeight),
      )).abs();
      deduplicated.add(
        _CardCandidate(
          [
            const _ImagePoint(0, 0),
            _ImagePoint(working.cols - 1.0, 0),
            _ImagePoint(working.cols - 1.0, working.rows - 1.0),
            _ImagePoint(0, working.rows - 1.0),
          ],
          (working.cols - 1.0) * (working.rows - 1.0),
          math.exp(-2.7 * aspectError),
          0.76 + 0.16 * math.exp(-2.7 * aspectError),
          sourceImage: true,
          diagnostics: const {'source_image': 1.0},
        ),
      );
    }
    if (deduplicated.isEmpty) {
      throw const ScanImageProcessingException(
        'Keep one card fully visible inside the frame and try again.',
      );
    }
    if (scaledCameraGuide != null) {
      var guided = _selectCameraCandidate(deduplicated, scaledCameraGuide);
      if (guided == null) {
        throw const ScanImageProcessingException(
          'Keep one card fully visible inside the frame and try again.',
        );
      }
      final enclosing = _preferEnclosingCard(
        guided,
        deduplicated,
        working.rows * working.cols,
      );
      if (enclosing != null) {
        guided = enclosing
            .withDiagnostic('camera_guide_selection')
            .withDiagnostic('camera_enclosing_card_recovery');
      }
      return (
        corners: [
          for (final point in guided.points)
            _ImagePoint(point.x / scale, point.y / scale),
        ],
        diagnostics: guided.diagnostics,
      );
    }
    deduplicated.sort((left, right) => right.score.compareTo(left.score));
    var best = deduplicated.first;
    var selectedInset = false;
    final imageArea = working.rows * working.cols;
    if (best.sourceImage) {
      final inset = deduplicated.where((candidate) {
        final ratio = candidate.area / imageArea;
        return ratio >= 0.80 &&
            ratio <= 0.985 &&
            candidate.aspectScore >= 0.90 &&
            candidate.score >= best.score - 0.12;
      }).toList()..sort((left, right) => right.score.compareTo(left.score));
      if (inset.isNotEmpty) {
        best = inset.first.withDiagnostic('inset_from_source');
        selectedInset = true;
      }
    }
    if (!selectedInset) {
      final enclosing = _preferEnclosingCard(best, deduplicated, imageArea);
      if (enclosing != null) best = enclosing;
    }
    if (allowContainerRecovery &&
        !selectedInset &&
        best.area / imageArea >= 0.55) {
      final outer = best;
      final nested = deduplicated.where((candidate) {
        if (identical(candidate, outer)) return false;
        final areaRatio = candidate.area / imageArea;
        final relativeArea = candidate.area / math.max(outer.area, 1.0);
        final containedCorners = candidate.points
            .where((point) => _contains(outer.points, point))
            .length;
        return areaRatio >= 0.12 &&
            areaRatio <= 0.70 &&
            relativeArea >= 0.20 &&
            relativeArea <= 0.85 &&
            candidate.aspectScore >= 0.70 &&
            candidate.score >= outer.score - 0.17 &&
            containedCorners >= 3;
      }).toList();
      if (nested.isNotEmpty) {
        nested.sort(
          (left, right) => (right.score + 0.20 * right.area / imageArea)
              .compareTo(left.score + 0.20 * left.area / imageArea),
        );
        best = nested.first.withDiagnostic('nested_card_surface');
      }
    }
    if (best.aspectScore < 0.70) {
      final alternatives = deduplicated.where((candidate) {
        final areaRatio = candidate.area / imageArea;
        return areaRatio >= 0.10 &&
            areaRatio <= 0.70 &&
            candidate.aspectScore >= 0.95 &&
            candidate.score >= best.score - 0.06;
      }).toList()..sort((left, right) => right.score.compareTo(left.score));
      if (alternatives.isNotEmpty) {
        final recoveredShape = alternatives.first;
        final corners = _scaleQuad(recoveredShape.points, 0.94);
        best = recoveredShape.copyWith(
          points: corners,
          area: _polygonArea(corners),
          diagnostics: {
            ...recoveredShape.diagnostics,
            'pre_inset_area_ratio': recoveredShape.area / imageArea,
            'area_ratio': _polygonArea(corners) / imageArea,
            'shape_recovery': 1.0,
          },
        );
      }
    }
    final expandedSurface = _expandTruncatedCardSurface(
      best,
      deduplicated,
      imageArea,
      working.cols,
      working.rows,
    );
    if (expandedSurface != null) best = expandedSurface;
    final panelRecovery = allowContainerRecovery
        ? _recoverFromLandscapePanel(
            best,
            deduplicated,
            working,
            gradient,
            gradientHigh,
            imageArea,
          )
        : null;
    if (panelRecovery != null) best = panelRecovery;
    final recovered = allowContainerRecovery
        ? _recoverSlabCard(
            best,
            deduplicated,
            working,
            gradient,
            gradientHigh,
            imageArea,
          )
        : null;
    if (recovered != null) best = recovered;
    final inset = _insetForeshortenedCard(best, working, imageArea);
    if (inset != null) best = inset;
    if (best.score < 0.48) {
      throw const ScanImageProcessingException(
        'Keep one card fully visible inside the frame and try again.',
      );
    }
    return (
      corners: [
        for (final point in best.points)
          _ImagePoint(point.x / scale, point.y / scale),
      ],
      diagnostics: best.diagnostics,
    );
  } finally {
    for (final mask in masks) {
      mask.dispose();
    }
    channels.dispose();
    gradient.dispose();
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
  cv.Mat gradient,
  double gradientHigh,
  List<_CardCandidate> candidates, {
  required bool allowMissingCornerRecovery,
}) {
  final imageArea = image.rows * image.cols;
  final area = cv.contourArea(contour).abs();
  if (area < imageArea * 0.025 || area > imageArea * 0.96) return;
  final perimeter = cv.arcLength(contour, true);
  if (perimeter <= 0) return;
  var added = false;
  var recoveredMissingCorner = false;
  for (final epsilon in const [0.012, 0.02, 0.03, 0.045, 0.065, 0.09]) {
    final approximation = cv.approxPolyDP(contour, perimeter * epsilon, true);
    try {
      if (allowMissingCornerRecovery &&
          !recoveredMissingCorner &&
          approximation.length == 5) {
        final recovery = _recoverMissingCorner(
          [
            for (var i = 0; i < approximation.length; i++)
              _ImagePoint(
                approximation[i].x.toDouble(),
                approximation[i].y.toDouble(),
              ),
          ],
          image.cols,
          image.rows,
        );
        if (recovery != null &&
            _addCandidate(
              recovery.points,
              image,
              gradient,
              gradientHigh,
              candidates,
            )) {
          final recovered = candidates.removeLast();
          candidates.add(
            recovered.copyWith(
              diagnostics: {
                ...recovered.diagnostics,
                'missing_corner_recovery': 1.0,
                'missing_corner_gap_ratio': recovery.gapRatio,
                'missing_corner_area_expansion_ratio': recovery.areaExpansion,
              },
            ),
          );
          recoveredMissingCorner = true;
        }
      }
      if (approximation.length != 4 || !cv.isContourConvex(approximation)) {
        continue;
      }
      final valid = _addCandidate(
        [
          for (var i = 0; i < 4; i++)
            _ImagePoint(
              approximation[i].x.toDouble(),
              approximation[i].y.toDouble(),
            ),
        ],
        image,
        gradient,
        gradientHigh,
        candidates,
      );
      if (valid) {
        added = true;
        break;
      }
    } finally {
      approximation.dispose();
    }
  }
  final rectangle = cv.minAreaRect(contour);
  final rectangleArea = rectangle.size.width * rectangle.size.height;
  if (rectangleArea <= 0 || area / rectangleArea < (added ? 0.52 : 0.68)) {
    return;
  }
  final box = cv.boxPoints(rectangle);
  try {
    _addCandidate(
      [for (var i = 0; i < box.length; i++) _ImagePoint(box[i].x, box[i].y)],
      image,
      gradient,
      gradientHigh,
      candidates,
    );
  } finally {
    box.dispose();
  }
}

({List<_ImagePoint> points, double gapRatio, double areaExpansion})?
_recoverMissingCorner(
  List<_ImagePoint> contour,
  int imageWidth,
  int imageHeight,
) {
  if (contour.length != 5) return null;
  ({List<_ImagePoint> points, double gapRatio, double areaExpansion})? best;
  final originalArea = _polygonArea(contour);
  for (var index = 0; index < contour.length; index += 1) {
    final before = contour[(index + contour.length - 1) % contour.length];
    final start = contour[index];
    final end = contour[(index + 1) % contour.length];
    final after = contour[(index + 2) % contour.length];
    final beforeLength = _distance(before, start);
    final gapLength = _distance(start, end);
    final afterLength = _distance(end, after);
    final adjacentLength = math.min(beforeLength, afterLength);
    if (adjacentLength < 24 || gapLength / adjacentLength > 0.50) continue;

    final intersection = _lineIntersection(before, start, end, after);
    if (intersection == null ||
        intersection.x < 0 ||
        intersection.y < 0 ||
        intersection.x > imageWidth - 1 ||
        intersection.y > imageHeight - 1) {
      continue;
    }
    final incomingX = start.x - before.x;
    final incomingY = start.y - before.y;
    final outgoingX = after.x - end.x;
    final outgoingY = after.y - end.y;
    if ((intersection.x - start.x) * incomingX +
                (intersection.y - start.y) * incomingY <=
            0 ||
        (intersection.x - end.x) * outgoingX +
                (intersection.y - end.y) * outgoingY >=
            0) {
      continue;
    }
    if (_distance(start, intersection) / beforeLength > 0.45 ||
        _distance(end, intersection) / afterLength > 0.45) {
      continue;
    }

    final recovered = <_ImagePoint>[
      intersection,
      for (var offset = 2; offset < contour.length; offset += 1)
        contour[(index + offset) % contour.length],
    ];
    final recoveredArea = _polygonArea(recovered);
    final areaExpansion = recoveredArea / math.max(originalArea, 1e-6);
    if (areaExpansion < 1.0 || areaExpansion > 1.12) continue;
    final gapRatio = gapLength / adjacentLength;
    if (best == null || gapRatio < best.gapRatio) {
      best = (
        points: recovered,
        gapRatio: gapRatio,
        areaExpansion: areaExpansion,
      );
    }
  }
  return best;
}

_ImagePoint? _lineIntersection(
  _ImagePoint firstStart,
  _ImagePoint firstEnd,
  _ImagePoint secondStart,
  _ImagePoint secondEnd,
) {
  final firstX = firstEnd.x - firstStart.x;
  final firstY = firstEnd.y - firstStart.y;
  final secondX = secondEnd.x - secondStart.x;
  final secondY = secondEnd.y - secondStart.y;
  final denominator = firstX * secondY - firstY * secondX;
  if (denominator.abs() < 1e-6) return null;
  final offsetX = secondStart.x - firstStart.x;
  final offsetY = secondStart.y - firstStart.y;
  final scale = (offsetX * secondY - offsetY * secondX) / denominator;
  return _ImagePoint(
    firstStart.x + scale * firstX,
    firstStart.y + scale * firstY,
  );
}

bool _addCandidate(
  List<_ImagePoint> raw,
  cv.Mat image,
  cv.Mat gradient,
  double gradientHigh,
  List<_CardCandidate> candidates,
) {
  final points = _orderCorners(raw);
  final sides = [
    for (var i = 0; i < 4; i++) _distance(points[i], points[(i + 1) % 4]),
  ];
  final shortest = sides.reduce(math.min);
  final longest = sides.reduce(math.max);
  if (shortest < 24 || shortest / math.max(longest, 1) < 0.24) return false;
  final area = _polygonArea(points);
  final areaRatio = area / (image.rows * image.cols);
  if (areaRatio < 0.025 || areaRatio > 0.97) return false;
  final width = (sides[0] + sides[2]) / 2;
  final height = (sides[1] + sides[3]) / 2;
  final aspect = math.min(width, height) / math.max(width, height);
  if (aspect < 0.32 || aspect > 0.95) return false;
  final aspectScore = math.exp(
    -2.7 * (math.log(aspect / (_cardWidth / _cardHeight))).abs(),
  );
  final vector = cv.VecPoint2f.generate(
    4,
    (i) => cv.Point2f(points[i].x, points[i].y),
  );
  final rectangle = cv.minAreaRect2f(vector);
  final rectangleArea = math.max(
    rectangle.size.width * rectangle.size.height,
    1,
  );
  vector.dispose();
  final rectangularity = math.min(1.0, area / rectangleArea);
  final boundary = _boundaryStrength(points, gradient, gradientHigh);
  final (content, border) = _appearanceScores(image, points);
  final areaScore = math.min(1.0, math.sqrt(areaRatio / 0.24));
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
  candidates.add(
    _CardCandidate(
      points,
      area,
      aspectScore,
      score,
      diagnostics: {
        'area_ratio': areaRatio,
        'aspect': aspect,
        'aspect_score': aspectScore,
        'rectangularity': rectangularity,
        'boundary_score': boundary,
        'content_score': content,
        'border_score': border,
      },
    ),
  );
  return true;
}

_CardCandidate? _recoverFromLandscapePanel(
  _CardCandidate best,
  List<_CardCandidate> candidates,
  cv.Mat image,
  cv.Mat gradient,
  double gradientHigh,
  int imageArea,
) {
  if (best.area / imageArea > 0.35) return null;
  final panel = _orderCorners(best.points);
  final panelSides = [
    for (var i = 0; i < 4; i++) _distance(panel[i], panel[(i + 1) % 4]),
  ];
  final panelWidth = (panelSides[0] + panelSides[2]) / 2;
  final panelHeight = (panelSides[1] + panelSides[3]) / 2;
  if (panelWidth <= panelHeight * 1.12) return null;

  final panelCenterY =
      panel.map((point) => point.y).reduce((a, b) => a + b) / 4;
  final frames = candidates.where((candidate) {
    if (identical(candidate, best) || candidate.area / imageArea < 0.55) {
      return false;
    }
    final frame = _orderCorners(candidate.points);
    final sides = [
      for (var i = 0; i < 4; i++) _distance(frame[i], frame[(i + 1) % 4]),
    ];
    final width = (sides[0] + sides[2]) / 2;
    final height = (sides[1] + sides[3]) / 2;
    if (height <= width * 1.12 || candidate.aspectScore < 0.75) {
      return false;
    }
    final containedCorners = panel
        .where((point) => _contains(frame, point))
        .length;
    final frameTop = frame.map((point) => point.y).reduce(math.min);
    final frameBottom = frame.map((point) => point.y).reduce(math.max);
    final relativeCenter =
        (panelCenterY - frameTop) / math.max(frameBottom - frameTop, 1.0);
    return containedCorners >= 3 && relativeCenter <= 0.45;
  }).toList()..sort((left, right) => right.area.compareTo(left.area));
  if (frames.isEmpty) return null;

  final targetHeight = panelWidth / (_cardWidth / _cardHeight);
  final extension = targetHeight / math.max(panelHeight, 1.0);
  if (extension < 1.45 || extension > 2.60) return null;
  final recoveredCorners =
      [
            panel[0],
            panel[1],
            _ImagePoint(
              panel[1].x + (panel[2].x - panel[1].x) * extension,
              panel[1].y + (panel[2].y - panel[1].y) * extension,
            ),
            _ImagePoint(
              panel[0].x + (panel[3].x - panel[0].x) * extension,
              panel[0].y + (panel[3].y - panel[0].y) * extension,
            ),
          ]
          .map(
            (point) => _ImagePoint(
              point.x.clamp(0, image.cols - 1),
              point.y.clamp(0, image.rows - 1),
            ),
          )
          .toList();
  final frame = _orderCorners(frames.first.points);
  if (recoveredCorners.where((point) => _contains(frame, point)).length < 3) {
    return null;
  }

  final recovered = <_CardCandidate>[];
  _addCandidate(recoveredCorners, image, gradient, gradientHigh, recovered);
  if (recovered.isEmpty || recovered.first.aspectScore < 0.90) return null;
  return recovered.first.copyWith(
    diagnostics: {
      ...recovered.first.diagnostics,
      'landscape_panel_recovery': 1.0,
      'pre_recovery_area_ratio': best.area / imageArea,
    },
  );
}

_CardCandidate? _recoverSlabCard(
  _CardCandidate best,
  List<_CardCandidate> candidates,
  cv.Mat image,
  cv.Mat gradient,
  double gradientHigh,
  int imageArea,
) {
  if (best.area / imageArea < 0.75) return null;
  final frames = candidates.where((candidate) {
    if (candidate.sourceImage ||
        _quadSimilarity(candidate.points, best.points) > 0.98 ||
        candidate.area / imageArea < 0.75) {
      return false;
    }
    final aspect = _observedAspect(candidate.points);
    return aspect >= 0.50 && aspect <= 0.75;
  }).toList()..sort((left, right) => right.area.compareTo(left.area));
  if (frames.isEmpty) return null;
  if (best.area / imageArea < 0.75 && best.aspectScore >= 0.80) return null;

  final frame = _orderCorners(frames.first.points);
  final frameAspect = _observedAspect(frame);
  const top = 0.285;
  const bottom = 0.92;
  final horizontalSpan = math.min(
    0.88,
    (_cardWidth / _cardHeight) / math.max(frameAspect, 1e-6) * (bottom - top),
  );
  final left = 0.5 - horizontalSpan / 2;
  final right = 0.5 + horizontalSpan / 2;
  _ImagePoint interpolate(double horizontal, double vertical) {
    final top = _ImagePoint(
      (1 - horizontal) * frame[0].x + horizontal * frame[1].x,
      (1 - horizontal) * frame[0].y + horizontal * frame[1].y,
    );
    final bottom = _ImagePoint(
      (1 - horizontal) * frame[3].x + horizontal * frame[2].x,
      (1 - horizontal) * frame[3].y + horizontal * frame[2].y,
    );
    return _ImagePoint(
      (1 - vertical) * top.x + vertical * bottom.x,
      (1 - vertical) * top.y + vertical * bottom.y,
    );
  }

  final recovered = <_CardCandidate>[];
  _addCandidate(
    [
      interpolate(left, top),
      interpolate(right, top),
      interpolate(right, bottom),
      interpolate(left, bottom),
    ],
    image,
    gradient,
    gradientHigh,
    recovered,
  );
  if (recovered.isEmpty || recovered.first.aspectScore < 0.80) return null;
  return recovered.first.copyWith(
    diagnostics: {
      ...recovered.first.diagnostics,
      'slab_card_recovery': 1.0,
      'slab_frame_area_ratio': frames.first.area / imageArea,
      'pre_recovery_area_ratio': best.area / imageArea,
    },
  );
}

_CardCandidate? _expandTruncatedCardSurface(
  _CardCandidate best,
  List<_CardCandidate> candidates,
  int imageArea,
  int imageWidth,
  int imageHeight,
) {
  final areaRatio = best.area / imageArea;
  final holders = candidates.where((candidate) {
    if (candidate.sourceImage) return false;
    final relativeArea = candidate.area / math.max(best.area, 1e-6);
    final holderAspect = candidate.diagnostics['aspect'] ?? 0.0;
    if (relativeArea < 1.15 ||
        relativeArea > 5.0 ||
        holderAspect < 0.45 ||
        holderAspect > 0.80) {
      return false;
    }
    return best.points
            .where((point) => _contains(candidate.points, point))
            .length >=
        3;
  }).toList()..sort((left, right) => left.area.compareTo(right.area));

  final nested = best.diagnostics['nested_card_surface'] == 1.0;
  final borderScore = best.diagnostics['border_score'] ?? 0.0;
  final boundaryScore = best.diagnostics['boundary_score'] ?? 0.0;
  final edgeReliability = boundaryScore / math.max(borderScore, 1e-6);
  final nestedLowContrast = nested && borderScore < 0.50 && holders.isNotEmpty;
  final weakHolderBoundary =
      !nested &&
      holders.isNotEmpty &&
      borderScore >= 0.80 &&
      edgeReliability < 0.70;
  if (!nestedLowContrast && !weakHolderBoundary) return null;

  final targetAspect = _cardWidth / _cardHeight;
  final observed = _observedAspect(best.points);
  var verticalExpansion = 0.0;
  var uniformExpansion = 0.0;
  if (observed > targetAspect * 1.02) {
    verticalExpansion = (observed / targetAspect - 1.0).clamp(0.0, 0.16);
    if (nestedLowContrast) uniformExpansion = 0.02;
  } else if (nestedLowContrast) {
    final holderGap =
        math.sqrt(holders.first.area / math.max(best.area, 1e-6)) - 1.0;
    uniformExpansion = (holderGap * 0.50).clamp(0.02, 0.08);
  } else {
    uniformExpansion = 0.03;
  }
  var expanded = _orderCorners(best.points);
  if (uniformExpansion > 0.0) {
    expanded = _scaleQuad(expanded, 1.0 + uniformExpansion);
  }
  if (verticalExpansion > 0.0) {
    final topLeft = expanded[0];
    final topRight = expanded[1];
    final bottomRight = expanded[2];
    final bottomLeft = expanded[3];
    expanded = [
      _ImagePoint(
        topLeft.x - (bottomLeft.x - topLeft.x) * verticalExpansion / 2,
        topLeft.y - (bottomLeft.y - topLeft.y) * verticalExpansion / 2,
      ),
      _ImagePoint(
        topRight.x - (bottomRight.x - topRight.x) * verticalExpansion / 2,
        topRight.y - (bottomRight.y - topRight.y) * verticalExpansion / 2,
      ),
      _ImagePoint(
        bottomRight.x + (bottomRight.x - topRight.x) * verticalExpansion / 2,
        bottomRight.y + (bottomRight.y - topRight.y) * verticalExpansion / 2,
      ),
      _ImagePoint(
        bottomLeft.x + (bottomLeft.x - topLeft.x) * verticalExpansion / 2,
        bottomLeft.y + (bottomLeft.y - topLeft.y) * verticalExpansion / 2,
      ),
    ];
  }
  final points = [
    for (final point in expanded)
      _ImagePoint(
        point.x.clamp(0.0, imageWidth - 1.0),
        point.y.clamp(0.0, imageHeight - 1.0),
      ),
  ];
  return best.copyWith(
    points: points,
    area: _polygonArea(points),
    diagnostics: {
      ...best.diagnostics,
      'pre_surface_expansion_area_ratio': areaRatio,
      'area_ratio': _polygonArea(points) / imageArea,
      'card_surface_expansion': 1.0,
      'surface_uniform_expansion_ratio': uniformExpansion,
      'surface_vertical_expansion_ratio': verticalExpansion,
    },
  );
}

_CardCandidate? _insetForeshortenedCard(
  _CardCandidate best,
  cv.Mat image,
  int imageArea,
) {
  final areaRatio = best.area / imageArea;
  if (best.aspectScore >= 0.70 ||
      (best.diagnostics['border_score'] ?? 0.0) < 0.80 ||
      (best.diagnostics['boundary_score'] ?? 0.0) < 0.70) {
    return null;
  }
  final corners = _orderCorners(_scaleQuad(best.points, 0.98));
  final preview = _warpCardToSize(image, corners, 224, 312);
  final gray = cv.cvtColor(preview, cv.COLOR_BGR2GRAY);
  final edges = cv.canny(gray, 45, 140);
  final band = math.max(4, (edges.cols * 0.05).round());
  double density(int start, int end) {
    var count = 0;
    for (var y = 0; y < edges.rows; y++) {
      for (var x = start; x < end; x++) {
        if (edges.data[y * edges.cols + x] > 0) count++;
      }
    }
    return count / math.max(1, edges.rows * (end - start));
  }

  final leftDensity = density(0, band);
  final rightDensity = density(edges.cols - band, edges.cols);
  String? insetSide;
  var edgeInset = 0.0;
  final stronger = math.max(leftDensity, rightDensity);
  final weaker = math.max(1e-6, math.min(leftDensity, rightDensity));
  if (stronger >= 0.20 && stronger >= 1.60 * weaker) {
    final insetRight = rightDensity > leftDensity;
    final referenceDensity = insetRight ? leftDensity : rightDensity;
    final targetDensity = math.max(0.25, referenceDensity * 1.15);
    for (var step = 1; step <= 12; step++) {
      final fraction = step / 100.0;
      final offset = (fraction * edges.cols).round();
      final start = insetRight ? edges.cols - offset - band : offset;
      final end = start + band;
      if (start < 0 || end > edges.cols) break;
      if (density(start, end) <= targetDensity) {
        edgeInset = fraction;
        break;
      }
    }
    if (edgeInset == 0.0) edgeInset = 0.12;
    _ImagePoint moveToward(_ImagePoint point, _ImagePoint target) =>
        _ImagePoint(
          point.x + (target.x - point.x) * edgeInset,
          point.y + (target.y - point.y) * edgeInset,
        );
    if (rightDensity > leftDensity) {
      corners[1] = moveToward(corners[1], corners[0]);
      corners[2] = moveToward(corners[2], corners[3]);
      insetSide = 'right_edge_inset';
    } else {
      corners[0] = moveToward(corners[0], corners[1]);
      corners[3] = moveToward(corners[3], corners[2]);
      insetSide = 'left_edge_inset';
    }
  }
  edges.dispose();
  gray.dispose();
  preview.dispose();
  return best.copyWith(
    points: corners,
    area: _polygonArea(corners),
    diagnostics: {
      ...best.diagnostics,
      'pre_inset_area_ratio': areaRatio,
      'area_ratio': _polygonArea(corners) / imageArea,
      'foreshortened_card_inset': 1.0,
      if (insetSide != null) insetSide: 1.0,
      if (insetSide != null) 'edge_inset_ratio': edgeInset,
    },
  );
}

List<_ImagePoint> _scaleQuad(List<_ImagePoint> points, double factor) {
  final ordered = _orderCorners(points);
  final centerX = ordered.map((point) => point.x).reduce((a, b) => a + b) / 4;
  final centerY = ordered.map((point) => point.y).reduce((a, b) => a + b) / 4;
  return [
    for (final point in ordered)
      _ImagePoint(
        centerX + (point.x - centerX) * factor,
        centerY + (point.y - centerY) * factor,
      ),
  ];
}

_CardCandidate? _preferEnclosingCard(
  _CardCandidate best,
  List<_CardCandidate> candidates,
  int imageArea,
) {
  final areaRatio = best.area / imageArea;
  if (areaRatio < 0.10 || areaRatio > 0.45 || best.aspectScore < 0.78) {
    return null;
  }
  final parents = candidates.where((candidate) {
    if (identical(candidate, best)) return false;
    final parentAreaRatio = candidate.area / imageArea;
    final scale = parentAreaRatio / math.max(areaRatio, 1e-6);
    final containedCorners = best.points
        .where((point) => _contains(candidate.points, point))
        .length;
    return scale >= 1.35 &&
        scale <= 4.50 &&
        parentAreaRatio >= 0.30 &&
        parentAreaRatio <= 0.75 &&
        candidate.aspectScore >= 0.78 &&
        candidate.score >= best.score - 0.13 &&
        containedCorners >= 3;
  }).toList()..sort((left, right) => right.area.compareTo(left.area));
  return parents.isEmpty
      ? null
      : parents.first.withDiagnostic('enclosing_card_recovery');
}

double _observedAspect(List<_ImagePoint> points) {
  final ordered = _orderCorners(points);
  final sides = [
    for (var i = 0; i < 4; i++) _distance(ordered[i], ordered[(i + 1) % 4]),
  ];
  final width = (sides[0] + sides[2]) / 2;
  final height = (sides[1] + sides[3]) / 2;
  return math.min(width, height) / math.max(width, height);
}

int _medianU8(cv.Mat mat) {
  final histogram = List<int>.filled(256, 0);
  for (final value in mat.data) {
    histogram[value]++;
  }
  final target = mat.total ~/ 2;
  var count = 0;
  for (var value = 0; value < histogram.length; value++) {
    count += histogram[value];
    if (count > target) return value;
  }
  return 0;
}

cv.Mat _buildGradient(cv.VecMat channels) {
  cv.Mat? combined;
  for (var index = 0; index < channels.length; index++) {
    final gx = cv.sobel(
      channels[index],
      cv.MatType.CV_32FC1.value,
      1,
      0,
      ksize: 3,
    );
    final gy = cv.sobel(
      channels[index],
      cv.MatType.CV_32FC1.value,
      0,
      1,
      ksize: 3,
    );
    final magnitude = cv.magnitude(gx, gy);
    gx.dispose();
    gy.dispose();
    if (combined == null) {
      combined = magnitude;
    } else {
      final maximum = cv.max(combined, magnitude);
      combined.dispose();
      magnitude.dispose();
      combined = maximum;
    }
  }
  return combined!;
}

double _gradientPercentile(cv.Mat gradient, double percentile) {
  final bytes = gradient.data;
  final values = bytes.buffer.asFloat32List(
    bytes.offsetInBytes,
    gradient.total,
  );
  final sampled = <double>[for (var i = 0; i < values.length; i += 4) values[i]]
    ..sort();
  return math.max(
    1.0,
    sampled[(sampled.length * percentile).floor().clamp(0, sampled.length - 1)],
  );
}

double _boundaryStrength(
  List<_ImagePoint> points,
  cv.Mat gradient,
  double high,
) {
  final bytes = gradient.data;
  final values = bytes.buffer.asFloat32List(
    bytes.offsetInBytes,
    gradient.total,
  );
  final edgeScores = <double>[];
  for (var edge = 0; edge < 4; edge++) {
    final start = points[edge];
    final end = points[(edge + 1) % 4];
    final length = math.max(16, _distance(start, end).floor());
    final strengths = <double>[];
    for (var step = 0; step < length; step++) {
      final t = length == 1 ? 0.0 : step / (length - 1);
      final x = (start.x + (end.x - start.x) * t).round();
      final y = (start.y + (end.y - start.y) * t).round();
      var strongest = 0.0;
      for (var offset = -2; offset <= 2; offset++) {
        final xi = (x + offset).clamp(0, gradient.cols - 1);
        final yi = (y + offset).clamp(0, gradient.rows - 1);
        strongest = math.max(strongest, values[yi * gradient.cols + xi] / high);
      }
      strengths.add(math.min(1.0, strongest));
    }
    strengths.sort();
    final upper = strengths.sublist(strengths.length ~/ 2);
    edgeScores.add(upper.reduce((a, b) => a + b) / upper.length);
  }
  return edgeScores.reduce((a, b) => a + b) / edgeScores.length;
}

(double, double) _appearanceScores(cv.Mat image, List<_ImagePoint> points) {
  final preview = _warpCardToSize(image, points, 224, 312);
  final gray = cv.cvtColor(preview, cv.COLOR_BGR2GRAY);
  final edges = cv.canny(gray, 45, 140);
  var edgeCount = 0;
  var pixelCount = 0;
  for (var y = 20; y < edges.rows - 20; y++) {
    for (var x = 15; x < edges.cols - 15; x++) {
      if (edges.data[y * edges.cols + x] > 0) edgeCount++;
      pixelCount++;
    }
  }
  final content = math.min(1.0, (edgeCount / math.max(pixelCount, 1)) / 0.16);
  final lab = cv.cvtColor(preview, cv.COLOR_BGR2Lab);
  final outer = [for (var i = 0; i < 3; i++) List<int>.filled(256, 0)];
  final inner = [for (var i = 0; i < 3; i++) List<int>.filled(256, 0)];
  var outerCount = 0;
  var innerCount = 0;
  void addRows(List<List<int>> histogram, int start, int end) {
    for (var y = start; y < end; y++) {
      for (var x = 0; x < lab.cols; x++) {
        final offset = (y * lab.cols + x) * 3;
        for (var c = 0; c < 3; c++) {
          histogram[c][lab.data[offset + c]]++;
        }
      }
    }
  }

  void addColumns(List<List<int>> histogram, int start, int end) {
    for (var y = 0; y < lab.rows; y++) {
      for (var x = start; x < end; x++) {
        final offset = (y * lab.cols + x) * 3;
        for (var c = 0; c < 3; c++) {
          histogram[c][lab.data[offset + c]]++;
        }
      }
    }
  }

  addRows(outer, 0, 8);
  addRows(outer, lab.rows - 8, lab.rows);
  addColumns(outer, 0, 8);
  addColumns(outer, lab.cols - 8, lab.cols);
  outerCount = 16 * lab.cols + 16 * lab.rows;
  addRows(inner, 12, 20);
  addRows(inner, lab.rows - 20, lab.rows - 12);
  addColumns(inner, 12, 20);
  addColumns(inner, lab.cols - 20, lab.cols - 12);
  innerCount = 16 * lab.cols + 16 * lab.rows;
  int median(List<int> histogram, int count) {
    var seen = 0;
    for (var value = 0; value < 256; value++) {
      seen += histogram[value];
      if (seen > count ~/ 2) {
        return value;
      }
    }
    return 0;
  }

  var squared = 0.0;
  for (var c = 0; c < 3; c++) {
    final difference =
        median(outer[c], outerCount) - median(inner[c], innerCount);
    squared += difference * difference;
  }
  final border = math.min(1.0, math.sqrt(squared) / 38.0);
  lab.dispose();
  edges.dispose();
  gray.dispose();
  preview.dispose();
  return (content, border);
}

List<_CardCandidate> _deduplicateCandidates(List<_CardCandidate> candidates) {
  final kept = <_CardCandidate>[];
  for (final candidate in candidates) {
    final duplicateIndex = kept.indexWhere(
      (item) => _quadSimilarity(candidate.points, item.points) > 0.82,
    );
    if (duplicateIndex >= 0) {
      final existing = kept[duplicateIndex];
      final recoversMissingCorner =
          candidate.diagnostics['missing_corner_recovery'] == 1.0;
      final existingRecoversMissingCorner =
          existing.diagnostics['missing_corner_recovery'] == 1.0;
      if (recoversMissingCorner &&
          !existingRecoversMissingCorner &&
          candidate.score >= existing.score - 0.06) {
        kept[duplicateIndex] = candidate;
      }
      continue;
    }
    kept.add(candidate);
    if (kept.length >= 30) {
      break;
    }
  }
  return kept;
}

_CardCandidate? _selectCameraCandidate(
  List<_CardCandidate> candidates,
  _CameraGuide guide,
) {
  final guideArea = guide.width * guide.height;
  final guideDiagonal = math.sqrt(
    guide.width * guide.width + guide.height * guide.height,
  );
  final guideCenter = _ImagePoint(
    guide.left + guide.width / 2,
    guide.top + guide.height / 2,
  );
  final ranked = <({double score, _CardCandidate candidate})>[];
  for (final candidate in candidates) {
    if (candidate.aspectScore < 0.70) continue;
    final bounds = _quadBounds(candidate.points);
    if ((bounds.width > bounds.height) != (guide.width > guide.height)) {
      continue;
    }
    final intersectionWidth = math.max(
      0.0,
      math.min(bounds.right, guide.right) - math.max(bounds.left, guide.left),
    );
    final intersectionHeight = math.max(
      0.0,
      math.min(bounds.bottom, guide.bottom) - math.max(bounds.top, guide.top),
    );
    final intersectionArea = intersectionWidth * intersectionHeight;
    final guideCoverage = intersectionArea / math.max(guideArea, 1.0);
    final candidateBoundsArea = bounds.width * bounds.height;
    final candidateCoverage =
        intersectionArea / math.max(candidateBoundsArea, 1.0);
    final candidateCenter = _ImagePoint(
      (bounds.left + bounds.right) / 2,
      (bounds.top + bounds.bottom) / 2,
    );
    final normalizedCenterDistance =
        _distance(candidateCenter, guideCenter) / math.max(guideDiagonal, 1.0);
    final centerScore = math.max(0.0, 1.0 - normalizedCenterDistance / 0.35);
    final relativeArea = candidate.area / math.max(guideArea, 1.0);
    if (guideCoverage < 0.45 ||
        centerScore < 0.35 ||
        relativeArea < 0.75 ||
        relativeArea > 5.0) {
      continue;
    }
    final areaScore = math.exp(-(math.log(relativeArea / 1.4)).abs());
    final guidedScore =
        0.38 * candidate.score +
        0.18 * guideCoverage +
        0.10 * candidateCoverage +
        0.12 * centerScore +
        0.12 * areaScore +
        0.10 * candidate.aspectScore;
    ranked.add((
      score: guidedScore,
      candidate: candidate.copyWith(
        diagnostics: {
          ...candidate.diagnostics,
          'camera_guide_selection': 1.0,
          'camera_guide_score': guidedScore,
          'camera_guide_coverage': guideCoverage,
          'camera_candidate_coverage': candidateCoverage,
          'camera_guide_center_score': centerScore,
          'camera_guide_area_ratio': relativeArea,
          'camera_guide_area_score': areaScore,
        },
      ),
    ));
  }
  ranked.sort((left, right) => right.score.compareTo(left.score));
  return ranked.isEmpty ? null : ranked.first.candidate;
}

({
  double left,
  double top,
  double right,
  double bottom,
  double width,
  double height,
})
_quadBounds(List<_ImagePoint> points) {
  final left = points.map((point) => point.x).reduce(math.min);
  final top = points.map((point) => point.y).reduce(math.min);
  final right = points.map((point) => point.x).reduce(math.max);
  final bottom = points.map((point) => point.y).reduce(math.max);
  return (
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    width: right - left,
    height: bottom - top,
  );
}

double _quadSimilarity(List<_ImagePoint> a, List<_ImagePoint> b) {
  double minX(List<_ImagePoint> p) => p.map((v) => v.x).reduce(math.min);
  double maxX(List<_ImagePoint> p) => p.map((v) => v.x).reduce(math.max);
  double minY(List<_ImagePoint> p) => p.map((v) => v.y).reduce(math.min);
  double maxY(List<_ImagePoint> p) => p.map((v) => v.y).reduce(math.max);
  final ax1 = minX(a), ax2 = maxX(a), ay1 = minY(a), ay2 = maxY(a);
  final bx1 = minX(b), bx2 = maxX(b), by1 = minY(b), by2 = maxY(b);
  final intersection =
      math.max(0.0, math.min(ax2, bx2) - math.max(ax1, bx1)) *
      math.max(0.0, math.min(ay2, by2) - math.max(ay1, by1));
  final union =
      (ax2 - ax1) * (ay2 - ay1) + (bx2 - bx1) * (by2 - by1) - intersection;
  return intersection / math.max(union, 1.0);
}

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
  final centerX = points.map((point) => point.x).reduce((a, b) => a + b) / 4;
  final centerY = points.map((point) => point.y).reduce((a, b) => a + b) / 4;
  final ordered = [...points]
    ..sort(
      (a, b) => math
          .atan2(a.y - centerY, a.x - centerX)
          .compareTo(math.atan2(b.y - centerY, b.x - centerX)),
    );
  final start = List.generate(4, (index) => index).reduce(
    (a, b) => ordered[a].x + ordered[a].y < ordered[b].x + ordered[b].y ? a : b,
  );
  final rotated = [for (var i = 0; i < 4; i++) ordered[(start + i) % 4]];
  final firstX = rotated[1].x - rotated[0].x;
  final firstY = rotated[1].y - rotated[0].y;
  final secondX = rotated[2].x - rotated[1].x;
  final secondY = rotated[2].y - rotated[1].y;
  if (firstX * secondY - firstY * secondX < 0) {
    return [rotated[0], rotated[3], rotated[2], rotated[1]];
  }
  return rotated;
}

cv.Mat _warpCard(cv.Mat image, List<_ImagePoint> corners) =>
    _warpCardToSize(image, corners, _cardWidth, _cardHeight);

cv.Mat _warpCardToSize(
  cv.Mat image,
  List<_ImagePoint> corners,
  int width,
  int height,
) {
  var ordered = _orderCorners(corners);
  final sides = [
    for (var i = 0; i < 4; i++) _distance(ordered[i], ordered[(i + 1) % 4]),
  ];
  if (sides[0] + sides[2] > sides[1] + sides[3]) {
    ordered = [ordered[1], ordered[2], ordered[3], ordered[0]];
  }
  final source = cv.VecPoint2f.generate(
    4,
    (index) => cv.Point2f(ordered[index].x, ordered[index].y),
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
    return cv.warpPerspective(
      image,
      transform,
      (width, height),
      flags: cv.INTER_CUBIC,
      borderMode: cv.BORDER_REPLICATE,
      borderValue: border,
    );
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

class _CameraGuide {
  const _CameraGuide({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
}

class _CardCandidate {
  const _CardCandidate(
    this.points,
    this.area,
    this.aspectScore,
    this.score, {
    this.sourceImage = false,
    this.diagnostics = const {},
  });
  final List<_ImagePoint> points;
  final double area;
  final double aspectScore;
  final double score;
  final bool sourceImage;
  final Map<String, double> diagnostics;

  _CardCandidate copyWith({
    List<_ImagePoint>? points,
    double? area,
    Map<String, double>? diagnostics,
  }) => _CardCandidate(
    points ?? this.points,
    area ?? this.area,
    aspectScore,
    score,
    sourceImage: sourceImage,
    diagnostics: diagnostics ?? this.diagnostics,
  );

  _CardCandidate withDiagnostic(String name) =>
      copyWith(diagnostics: {...diagnostics, name: 1.0});
}
