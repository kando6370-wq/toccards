import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'scan_card_recognizer_contract.dart';
import 'scan_ocr_text_normalizer.dart';
import 'scan_text_recognizer_contract.dart';

ScanTextRecognizer createScanTextRecognizer() =>
    switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS => const _MlKitScanTextRecognizer(),
      _ => const _UnsupportedScanTextRecognizer(),
    };

class _MlKitScanTextRecognizer implements ScanTextRecognizer {
  const _MlKitScanTextRecognizer();

  @override
  Future<String> recognize(Uint8List cardImageBytes) async {
    final directory = await Directory.systemTemp.createTemp('kando-scan-ocr-');
    final latinRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final japaneseRecognizer = TextRecognizer(
      script: TextRecognitionScript.japanese,
    );
    try {
      final image = File('${directory.path}${Platform.pathSeparator}card.jpg');
      await image.writeAsBytes(cardImageBytes, flush: true);
      return await recognizeParallelScanOcr(
        recognizeLatin: () async {
          final text = await latinRecognizer.processImage(
            InputImage.fromFile(image),
          );
          return text.text;
        },
        recognizeJapanese: () async {
          final text = await japaneseRecognizer.processImage(
            InputImage.fromFile(image),
          );
          return text.text;
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Scan OCR failed: $error\n$stackTrace');
      rethrow;
    } finally {
      await Future.wait([
        _closeRecognizer(latinRecognizer, 'Latin'),
        _closeRecognizer(japaneseRecognizer, 'Japanese'),
      ]);
      try {
        await directory.delete(recursive: true);
      } catch (error) {
        debugPrint('Scan OCR temporary-file cleanup failed: $error');
      }
    }
  }
}

@visibleForTesting
Future<String> recognizeParallelScanOcr({
  required Future<String> Function() recognizeLatin,
  required Future<String> Function() recognizeJapanese,
}) async {
  final texts = await Future.wait([recognizeLatin(), recognizeJapanese()]);
  return mergeOcrText(
    latinOcrText: normalizeLatinOcrText(texts[0]),
    japaneseOcrText: normalizeJapaneseOcrText(texts[1]),
  );
}

Future<void> _closeRecognizer(TextRecognizer recognizer, String label) async {
  try {
    await recognizer.close();
  } catch (error) {
    debugPrint('Scan $label OCR cleanup failed: $error');
  }
}

class _UnsupportedScanTextRecognizer implements ScanTextRecognizer {
  const _UnsupportedScanTextRecognizer();

  @override
  Future<String> recognize(Uint8List cardImageBytes) {
    throw const ScanImageProcessingException(
      'On-device text recognition is unavailable on this platform.',
    );
  }
}
