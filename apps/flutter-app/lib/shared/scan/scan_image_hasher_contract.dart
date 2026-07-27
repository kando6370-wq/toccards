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

class ScanImageCrop {
  const ScanImageCrop({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.viewportAspectRatio,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double viewportAspectRatio;

  ScanPixelCrop resolve({required int imageWidth, required int imageHeight}) {
    final imageAspectRatio = imageWidth / imageHeight;
    final visibleWidth = imageAspectRatio > viewportAspectRatio
        ? imageHeight * viewportAspectRatio
        : imageWidth.toDouble();
    final visibleHeight = imageAspectRatio > viewportAspectRatio
        ? imageHeight.toDouble()
        : imageWidth / viewportAspectRatio;
    final visibleLeft = (imageWidth - visibleWidth) / 2;
    final visibleTop = (imageHeight - visibleHeight) / 2;
    final x = (visibleLeft + left * visibleWidth).round().clamp(
      0,
      imageWidth - 1,
    );
    final y = (visibleTop + top * visibleHeight).round().clamp(
      0,
      imageHeight - 1,
    );
    final cropWidth = (width * visibleWidth).round().clamp(1, imageWidth - x);
    final cropHeight = (height * visibleHeight).round().clamp(
      1,
      imageHeight - y,
    );
    return ScanPixelCrop(x: x, y: y, width: cropWidth, height: cropHeight);
  }
}

class ScanPixelCrop {
  const ScanPixelCrop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

abstract interface class ScanImageHasher {
  Future<ScanImageHashes> hash(Uint8List imageBytes, {ScanImageCrop? crop});
}
