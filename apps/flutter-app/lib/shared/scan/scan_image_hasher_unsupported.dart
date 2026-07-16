import 'dart:typed_data';

import 'scan_image_hasher_contract.dart';

ScanImageHasher createScanImageHasher() => const _UnsupportedScanImageHasher();

class _UnsupportedScanImageHasher implements ScanImageHasher {
  const _UnsupportedScanImageHasher();

  @override
  Future<ScanImageHashes> hash(Uint8List imageBytes) {
    throw const ScanImageProcessingException(
      'Card recognition is not supported on this platform.',
    );
  }

  @override
  Future<ScanFrameDetection?> detectFrame(ScanCameraFrame frame) {
    throw const ScanImageProcessingException(
      'Card detection is not supported on this platform.',
    );
  }
}
