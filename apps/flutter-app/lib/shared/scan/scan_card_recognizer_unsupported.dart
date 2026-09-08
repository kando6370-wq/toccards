import 'dart:typed_data';

import 'scan_card_recognizer_contract.dart';

ScanCardRecognizer createScanCardRecognizer() =>
    const _UnsupportedScanCardRecognizer();

class _UnsupportedScanCardRecognizer implements ScanCardRecognizer {
  const _UnsupportedScanCardRecognizer();

  @override
  Future<ScanCardEmbedding> process(Uint8List imageBytes) {
    throw const ScanImageProcessingException(
      'On-device card recognition is unavailable on this platform.',
    );
  }
}
