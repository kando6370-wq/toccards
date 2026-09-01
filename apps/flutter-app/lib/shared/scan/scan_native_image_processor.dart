import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'scan_card_recognizer_contract.dart';
import 'scan_mask_geometry.dart';

class ScanNativePreparedImage {
  const ScanNativePreparedImage({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.resizedWidth,
    required this.resizedHeight,
    required this.rgbBytes,
  });

  final int sourceWidth;
  final int sourceHeight;
  final int resizedWidth;
  final int resizedHeight;
  final Uint8List rgbBytes;
}

class ScanNativeRectifiedCard {
  const ScanNativeRectifiedCard({
    required this.cardImageBytes,
    required this.embeddingRgbBytes,
  });

  final Uint8List cardImageBytes;
  final Uint8List embeddingRgbBytes;
}

class ScanNativeImageProcessor {
  const ScanNativeImageProcessor();

  static const _channel = MethodChannel('com.cardai.tcg/scan-image-processor');

  Future<ScanNativePreparedImage> prepareDetection(
    Uint8List imageBytes, {
    required int maximumSize,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'prepareDetection',
        {'image': imageBytes, 'maximum_size': maximumSize},
      );
      if (result == null) throw const FormatException();
      final sourceWidth = result['source_width'];
      final sourceHeight = result['source_height'];
      final resizedWidth = result['resized_width'];
      final resizedHeight = result['resized_height'];
      final rgbBytes = result['rgb_bytes'];
      if (sourceWidth is! int ||
          sourceHeight is! int ||
          resizedWidth is! int ||
          resizedHeight is! int ||
          rgbBytes is! Uint8List ||
          sourceWidth <= 0 ||
          sourceHeight <= 0 ||
          resizedWidth <= 0 ||
          resizedHeight <= 0 ||
          rgbBytes.length != resizedWidth * resizedHeight * 3) {
        throw const FormatException();
      }
      return ScanNativePreparedImage(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        resizedWidth: resizedWidth,
        resizedHeight: resizedHeight,
        rgbBytes: rgbBytes,
      );
    } on PlatformException catch (error) {
      throw ScanImageProcessingException(
        error.message ?? 'The selected image could not be decoded.',
      );
    } on FormatException {
      throw const ScanImageProcessingException(
        'The native image processor returned an invalid result.',
      );
    }
  }

  Future<ScanNativeRectifiedCard> rectifyCard(
    Uint8List imageBytes,
    List<ScanImagePoint> corners, {
    required int cardWidth,
    required int cardHeight,
    required int embeddingSize,
  }) async {
    if (corners.length != 4 ||
        corners.any((point) => !point.x.isFinite || !point.y.isFinite)) {
      throw const ScanImageProcessingException(
        'The detected card corners are invalid.',
      );
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'rectifyCard',
        {
          'image': imageBytes,
          'corners': [for (final point in corners) point.x, point.y],
          'card_width': cardWidth,
          'card_height': cardHeight,
          'embedding_size': embeddingSize,
          'jpeg_quality': 85,
        },
      );
      if (result == null) throw const FormatException();
      final cardImageBytes = result['card_image_bytes'];
      final embeddingRgbBytes = result['embedding_rgb_bytes'];
      if (cardImageBytes is! Uint8List ||
          cardImageBytes.isEmpty ||
          embeddingRgbBytes is! Uint8List ||
          embeddingRgbBytes.length != embeddingSize * embeddingSize * 3) {
        throw const FormatException();
      }
      return ScanNativeRectifiedCard(
        cardImageBytes: cardImageBytes,
        embeddingRgbBytes: embeddingRgbBytes,
      );
    } on PlatformException catch (error) {
      throw ScanImageProcessingException(
        error.message ?? 'The card image could not be corrected.',
      );
    } on FormatException {
      throw const ScanImageProcessingException(
        'The native image processor returned an invalid result.',
      );
    }
  }
}
