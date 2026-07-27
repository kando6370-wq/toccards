import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'scan_image_hasher_contract.dart';
import 'scan_phash.dart';

ScanImageHasher createScanImageHasher() => const _WebScanImageHasher();

class _WebScanImageHasher implements ScanImageHasher {
  const _WebScanImageHasher();

  @override
  Future<ScanImageHashes> hash(
    Uint8List imageBytes, {
    ScanImageCrop? crop,
  }) async {
    try {
      final result = await _processImage(
        base64Encode(imageBytes).toJS,
        (crop?.left ?? -1).toJS,
        (crop?.top ?? -1).toJS,
        (crop?.width ?? -1).toJS,
        (crop?.height ?? -1).toJS,
        (crop?.viewportAspectRatio ?? -1).toJS,
      ).toDart;
      final width = result.width.toDartInt;
      final height = result.height.toDartInt;
      return ScanImageHashes(
        r: encodeScanPhash(
          letterboxScanChannelPillowLanczos(
            base64Decode(result.red.toDart),
            width: width,
            height: height,
          ),
        ),
        g: encodeScanPhash(
          letterboxScanChannelPillowLanczos(
            base64Decode(result.green.toDart),
            width: width,
            height: height,
          ),
        ),
        b: encodeScanPhash(
          letterboxScanChannelPillowLanczos(
            base64Decode(result.blue.toDart),
            width: width,
            height: height,
          ),
        ),
        cardImageBytes: base64Decode(result.card.toDart),
      );
    } catch (_) {
      throw const ScanImageProcessingException(
        'Keep one card fully visible inside the frame and try again.',
      );
    }
  }
}

@JS('kandoScan.processImage')
external JSPromise<_WebScanResult> _processImage(
  JSString imageBase64,
  JSNumber cropLeft,
  JSNumber cropTop,
  JSNumber cropWidth,
  JSNumber cropHeight,
  JSNumber viewportAspectRatio,
);

extension type _WebScanResult._(JSObject _) implements JSObject {
  external JSString get red;
  external JSString get green;
  external JSString get blue;
  external JSString get card;
  external JSNumber get width;
  external JSNumber get height;
}
