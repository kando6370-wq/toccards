import 'dart:typed_data';

abstract interface class ScanTextRecognizer {
  Future<String> recognize(Uint8List cardImageBytes);
}
