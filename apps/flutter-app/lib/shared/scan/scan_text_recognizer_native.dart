import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'scan_card_recognizer_contract.dart';
import 'scan_text_recognizer_contract.dart';

ScanTextRecognizer createScanTextRecognizer() => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS =>
    const _MlKitScanTextRecognizer(),
  _ => const _UnsupportedScanTextRecognizer(),
};

class _MlKitScanTextRecognizer implements ScanTextRecognizer {
  const _MlKitScanTextRecognizer();

  @override
  Future<String> recognize(Uint8List cardImageBytes) async {
    final directory = await Directory.systemTemp.createTemp('kando-scan-ocr-');
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final image = File('${directory.path}${Platform.pathSeparator}card.jpg');
      await image.writeAsBytes(cardImageBytes, flush: true);
      final text = await recognizer.processImage(InputImage.fromFile(image));
      return text.text.trim();
    } catch (error, stackTrace) {
      debugPrint('Scan OCR failed: $error\n$stackTrace');
      rethrow;
    } finally {
      try {
        await recognizer.close();
      } catch (error) {
        debugPrint('Scan OCR cleanup failed: $error');
      }
      try {
        await directory.delete(recursive: true);
      } catch (error) {
        debugPrint('Scan OCR temporary-file cleanup failed: $error');
      }
    }
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
