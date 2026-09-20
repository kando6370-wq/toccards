import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'scan_card_recognizer_contract.dart';
import 'scan_mask_geometry.dart';
import 'scan_model_runtime.dart';
import 'scan_native_image_processor.dart';
import 'scan_phash.dart';

const _detectionInputSize = 640;
const _cardWidth = 745;
const _cardHeight = 1043;
const _scoreThreshold = 0.35;
const _maskThreshold = 0.5;
const _minimumCardAreaFraction = 0.025;
const _landscapeEdgeRatioThreshold = 1.15;
const _detectionMean = [103.53, 116.28, 123.675];
const _detectionStd = [57.375, 57.12, 58.395];

ScanCardRecognizer createScanCardRecognizer() => _NativeScanCardRecognizer();

class _NativeScanCardRecognizer implements ScanCardRecognizer {
  final ScanModelRuntime _runtime = const ScanModelRuntime();
  final ScanNativeImageProcessor _imageProcessor =
      const ScanNativeImageProcessor();
  Future<void> _tail = Future.value();

  @override
  Future<ScanCardHashes> process(Uint8List imageBytes) {
    final result = Completer<ScanCardHashes>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await _process(imageBytes));
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<ScanCardHashes> _process(Uint8List imageBytes) async {
    try {
      final totalTimer = Stopwatch()..start();
      final detectionTimer = Stopwatch()..start();
      final nativeImage = await _imageProcessor.prepareDetection(
        imageBytes,
        maximumSize: _detectionInputSize,
      );
      final prepared = await Isolate.run(() => _prepareDetection(nativeImage));
      final detectionOutputs = await _runDetection(prepared.tensor);
      final selected = await Isolate.run(
        () => _extractCardGeometry(prepared, detectionOutputs),
      );
      final rectified = await _imageProcessor.rectifyCard(
        imageBytes,
        selected.points,
        cardWidth: _cardWidth,
        cardHeight: _cardHeight,
      );
      detectionTimer.stop();

      final hashTimer = Stopwatch()..start();
      final hashes = await Isolate.run(
        () => hashScanCardRgb(
          rectified.cardRgbBytes,
          width: _cardWidth,
          height: _cardHeight,
        ),
      );
      hashTimer.stop();
      totalTimer.stop();

      return ScanCardHashes(
        r: hashes.r,
        g: hashes.g,
        b: hashes.b,
        cardImageBytes: rectified.cardImageBytes,
        diagnostics: {
          'detection_score': selected.score,
          'card_area_ratio': selected.areaRatio,
          'quad_min_area_rect': selected.usedMinimumAreaRectangle ? 1.0 : 0.0,
          'detection_ms': detectionTimer.elapsedMilliseconds.toDouble(),
          'hash_ms': hashTimer.elapsedMilliseconds.toDouble(),
          'total_ms': totalTimer.elapsedMilliseconds.toDouble(),
        },
      );
    } on ScanImageProcessingException {
      rethrow;
    } on Object {
      throw const ScanImageProcessingException(
        'The card image could not be processed on this device.',
      );
    }
  }

  Future<_DetectionOutputs> _runDetection(Float32List tensor) async {
    final outputs = await _runtime.runDetection(tensor);
    return _DetectionOutputs(
      detections: outputs.detections,
      detectionShape: outputs.detectionShape,
      masks: outputs.masks,
      maskShape: outputs.maskShape,
    );
  }
}

_PreparedDetection _prepareDetection(ScanNativePreparedImage image) {
  final planeSize = _detectionInputSize * _detectionInputSize;
  final tensor = Float32List(planeSize * 3);
  for (var channel = 0; channel < 3; channel += 1) {
    final padding = (114 - _detectionMean[channel]) / _detectionStd[channel];
    tensor.fillRange(channel * planeSize, (channel + 1) * planeSize, padding);
  }
  for (var y = 0; y < image.resizedHeight; y += 1) {
    for (var x = 0; x < image.resizedWidth; x += 1) {
      final sourceOffset = (y * image.resizedWidth + x) * 3;
      final targetOffset = y * _detectionInputSize + x;
      for (var channel = 0; channel < 3; channel += 1) {
        final rgbChannel = 2 - channel;
        tensor[channel * planeSize + targetOffset] =
            (image.rgbBytes[sourceOffset + rgbChannel] -
                _detectionMean[channel]) /
            _detectionStd[channel];
      }
    }
  }
  return _PreparedDetection(
    tensor: tensor,
    sourceWidth: image.sourceWidth,
    sourceHeight: image.sourceHeight,
    resizedWidth: image.resizedWidth,
    resizedHeight: image.resizedHeight,
  );
}

_SelectedCard _extractCardGeometry(
  _PreparedDetection prepared,
  _DetectionOutputs outputs,
) {
  if (outputs.detectionShape.length < 2 ||
      outputs.maskShape.length < 3 ||
      outputs.detectionShape.last < 5) {
    throw const ScanImageProcessingException(
      'The card detector returned an invalid result.',
    );
  }
  final detectionStride = outputs.detectionShape.last;
  final detectionCount =
      outputs.detectionShape[outputs.detectionShape.length - 2];
  final maskRows = outputs.maskShape[outputs.maskShape.length - 2];
  final maskCols = outputs.maskShape.last;
  final maskStride = maskRows * maskCols;
  if (outputs.detections.length < detectionCount * detectionStride ||
      outputs.masks.length < detectionCount * maskStride ||
      prepared.resizedWidth > maskCols ||
      prepared.resizedHeight > maskRows) {
    throw const ScanImageProcessingException(
      'The card detector returned an invalid result.',
    );
  }

  final candidateIndexes = <int>[];
  for (var index = 0; index < detectionCount; index += 1) {
    if (outputs.detections[index * detectionStride + 4] >= _scoreThreshold) {
      candidateIndexes.add(index);
    }
  }
  candidateIndexes.sort((left, right) {
    final leftScore = outputs.detections[left * detectionStride + 4];
    final rightScore = outputs.detections[right * detectionStride + 4];
    return rightScore.compareTo(leftScore);
  });

  for (final index in candidateIndexes) {
    final fit = fitScanMaskQuad(
      outputs.masks,
      maskOffset: index * maskStride,
      maskRows: maskRows,
      maskCols: maskCols,
      resizedWidth: prepared.resizedWidth,
      resizedHeight: prepared.resizedHeight,
      sourceWidth: prepared.sourceWidth,
      sourceHeight: prepared.sourceHeight,
      threshold: _maskThreshold,
    );
    if (fit == null || fit.areaRatio < _minimumCardAreaFraction) continue;
    var points = orderScanCorners(fit.points);
    final sides = [
      for (var side = 0; side < 4; side += 1)
        _distance(points[side], points[(side + 1) % 4]),
    ];
    if (sides[0] + sides[2] >
        (sides[1] + sides[3]) * _landscapeEdgeRatioThreshold) {
      points = [points[1], points[2], points[3], points[0]];
    }
    return _SelectedCard(
      points: points,
      score: outputs.detections[index * detectionStride + 4],
      areaRatio: fit.areaRatio,
      usedMinimumAreaRectangle: fit.usedMinimumAreaRectangle,
    );
  }
  throw const ScanImageProcessingException(
    'Keep one card fully visible inside the frame and try again.',
  );
}

double _distance(ScanImagePoint left, ScanImagePoint right) {
  final dx = left.x - right.x;
  final dy = left.y - right.y;
  return math.sqrt(dx * dx + dy * dy);
}

class _PreparedDetection {
  const _PreparedDetection({
    required this.tensor,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.resizedWidth,
    required this.resizedHeight,
  });

  final Float32List tensor;
  final int sourceWidth;
  final int sourceHeight;
  final int resizedWidth;
  final int resizedHeight;
}

class _DetectionOutputs {
  const _DetectionOutputs({
    required this.detections,
    required this.detectionShape,
    required this.masks,
    required this.maskShape,
  });

  final Float32List detections;
  final List<int> detectionShape;
  final Float32List masks;
  final List<int> maskShape;
}

class _SelectedCard {
  const _SelectedCard({
    required this.points,
    required this.score,
    required this.areaRatio,
    required this.usedMinimumAreaRectangle,
  });

  final List<ScanImagePoint> points;
  final double score;
  final double areaRatio;
  final bool usedMinimumAreaRectangle;
}
