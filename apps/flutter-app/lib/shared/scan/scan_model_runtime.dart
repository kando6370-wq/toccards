import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'scan_card_recognizer_contract.dart';

class ScanModelDetectionOutputs {
  const ScanModelDetectionOutputs({
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

class ScanModelRuntime {
  const ScanModelRuntime();

  static const _channel = MethodChannel('com.cardai.tcg/scan-model-runtime');

  Future<ScanModelDetectionOutputs> runDetection(Float32List tensor) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'runDetection',
        {'tensor': tensor},
      );
      if (result == null) throw const FormatException();
      final detections = result['dets'];
      final detectionShape = result['dets_shape'];
      final masks = result['masks'];
      final maskShape = result['masks_shape'];
      if (detections is! Float32List ||
          detectionShape is! List ||
          masks is! Float32List ||
          maskShape is! List) {
        throw const FormatException();
      }
      return ScanModelDetectionOutputs(
        detections: detections,
        detectionShape: _shape(detectionShape),
        masks: masks,
        maskShape: _shape(maskShape),
      );
    } on PlatformException catch (error) {
      throw ScanImageProcessingException(
        error.message ?? 'The card detector could not run on this device.',
      );
    } on FormatException {
      throw const ScanImageProcessingException(
        'The native card detector returned an invalid result.',
      );
    }
  }

  Future<Float32List> runEmbedding(Float32List tensor) async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'runEmbedding',
        {'tensor': tensor},
      );
      if (result is! Float32List || result.length != 512) {
        throw const FormatException();
      }
      return result;
    } on PlatformException catch (error) {
      throw ScanImageProcessingException(
        error.message ?? 'The card embedding model could not run on this device.',
      );
    } on FormatException {
      throw const ScanImageProcessingException(
        'The native card embedding model returned an invalid result.',
      );
    }
  }

  static List<int> _shape(List<Object?> values) {
    final shape = <int>[];
    for (final value in values) {
      if (value is! int || value <= 0) throw const FormatException();
      shape.add(value);
    }
    return shape;
  }
}
