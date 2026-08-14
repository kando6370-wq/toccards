import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'scan_card_number_reader_contract.dart';

const _disableMlKitOcr = bool.fromEnvironment('DISABLE_MLKIT_OCR');

ScanCardNumberReader createScanCardNumberReader() =>
    switch (defaultTargetPlatform) {
      TargetPlatform.android => const _MlKitScanCardNumberReader(),
      TargetPlatform.iOS when !_disableMlKitOcr =>
        const _MlKitScanCardNumberReader(),
      _ => const _UnsupportedScanCardNumberReader(),
    };

class _MlKitScanCardNumberReader implements ScanCardNumberReader {
  const _MlKitScanCardNumberReader();

  @override
  Future<String?> read(Uint8List cardImageBytes) async {
    final directory = await Directory.systemTemp.createTemp('kando-scan-ocr-');
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final image = File('${directory.path}${Platform.pathSeparator}card.jpg');
      await image.writeAsBytes(cardImageBytes, flush: true);
      final text = await recognizer.processImage(InputImage.fromFile(image));
      return extractScanCardNumber(text.text);
    } catch (error, stackTrace) {
      debugPrint('Card number OCR failed: $error\n$stackTrace');
      return null;
    } finally {
      try {
        await recognizer.close();
      } catch (error) {
        debugPrint('Card number OCR cleanup failed: $error');
      }
      try {
        await directory.delete(recursive: true);
      } catch (error) {
        debugPrint('Card number OCR temporary-file cleanup failed: $error');
      }
    }
  }
}

class _UnsupportedScanCardNumberReader implements ScanCardNumberReader {
  const _UnsupportedScanCardNumberReader();

  @override
  Future<String?> read(_) async => null;
}
