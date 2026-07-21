import 'dart:typed_data';

class ScanImageHashes {
  const ScanImageHashes({
    required this.r,
    required this.g,
    required this.b,
    this.cardImageBytes,
  });

  final String r;
  final String g;
  final String b;
  final Uint8List? cardImageBytes;
}

class ScanImageProcessingException implements Exception {
  const ScanImageProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ScanImageHasher {
  Future<ScanImageHashes> hash(Uint8List imageBytes);
}
