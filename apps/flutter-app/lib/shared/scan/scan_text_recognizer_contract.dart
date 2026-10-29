import 'dart:typed_data';

abstract interface class ScanTextRecognizer {
  /// Returns the normalized Latin and Japanese OCR text for scan upload.
  Future<String> recognize(Uint8List cardImageBytes);
}
