import 'dart:typed_data';

import 'scan_card_recognizer_contract.dart';
import 'scan_text_recognizer_contract.dart';

ScanCardRecognizer createScanCardRecognizer({ScanTextRecognizer? textRecognizer}) =>
    const _UnsupportedScanCardRecognizer();

class _UnsupportedScanCardRecognizer implements ScanCardRecognizer {
  const _UnsupportedScanCardRecognizer();

  @override
  Future<ScanCardHashes> process(
    Uint8List imageBytes, {
    bool allowCropFallback = false,
  }) {
    throw const ScanImageProcessingException(
      'On-device card recognition is unavailable on this platform.',
    );
  }
}
