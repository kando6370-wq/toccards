import 'dart:typed_data';

class ScanCardEmbedding {
  const ScanCardEmbedding({
    required this.vector,
    required this.cardImageBytes,
    this.diagnostics = const {},
  });

  final List<double> vector;
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
  Future<ScanCardEmbedding> process(Uint8List imageBytes);
}
