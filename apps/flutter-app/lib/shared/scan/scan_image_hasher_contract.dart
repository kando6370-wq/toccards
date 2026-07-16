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

enum ScanFrameFormat { bgra8888, yuv420, jpeg }

class ScanFramePlane {
  const ScanFramePlane({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class ScanCameraFrame {
  const ScanCameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
  });

  final int width;
  final int height;
  final ScanFrameFormat format;
  final List<ScanFramePlane> planes;
}

class ScanImagePoint {
  const ScanImagePoint(this.x, this.y);

  final double x;
  final double y;
}

class ScanFrameDetection {
  const ScanFrameDetection({
    required this.width,
    required this.height,
    required this.corners,
  });

  final int width;
  final int height;
  final List<ScanImagePoint> corners;
}

class ScanImageProcessingException implements Exception {
  const ScanImageProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ScanImageHasher {
  Future<ScanImageHashes> hash(Uint8List imageBytes);
  Future<ScanFrameDetection?> detectFrame(ScanCameraFrame frame);
}
