import 'dart:typed_data';

import 'scan_card_recognizer_contract.dart';
import 'scan_text_recognizer_contract.dart';

ScanTextRecognizer createScanTextRecognizer() =>
    const _UnsupportedScanTextRecognizer();

class _UnsupportedScanTextRecognizer implements ScanTextRecognizer {
  const _UnsupportedScanTextRecognizer();

  @override
  Future<String> recognize(Uint8List cardImageBytes) {
    throw const ScanImageProcessingException(
      'On-device text recognition is unavailable on this platform.',
    );
  }
}
