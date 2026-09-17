import 'dart:typed_data';

class ScanCardHashes {
  const ScanCardHashes({
    required this.r,
    required this.g,
    required this.b,
    required this.cardImageBytes,
    this.diagnostics = const {},
  });

  final String r;
  final String g;
  final String b;
  final Uint8List cardImageBytes;
  final Map<String, double> diagnostics;
}

class ScanImageProcessingException implements Exception {
  const ScanImageProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ScanCardRecognizer {
  Future<ScanCardHashes> process(Uint8List imageBytes);
}
