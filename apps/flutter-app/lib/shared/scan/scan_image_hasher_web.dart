import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'scan_image_hasher_contract.dart';
import 'scan_phash.dart';

ScanImageHasher createScanImageHasher() => const _WebScanImageHasher();

class _WebScanImageHasher implements ScanImageHasher {
  const _WebScanImageHasher();

  @override
  Future<ScanImageHashes> hash(Uint8List imageBytes) async {
    try {
      final result = await _processImage(base64Encode(imageBytes).toJS).toDart;
      return ScanImageHashes(
        r: encodeScanPhash(base64Decode(result.red.toDart)),
        g: encodeScanPhash(base64Decode(result.green.toDart)),
        b: encodeScanPhash(base64Decode(result.blue.toDart)),
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
external JSPromise<_WebScanResult> _processImage(JSString imageBase64);

extension type _WebScanResult._(JSObject _) implements JSObject {
  external JSString get red;
  external JSString get green;
  external JSString get blue;
  external JSString get card;
}
