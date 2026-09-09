import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_mask_geometry.dart';
import 'package:kando_app/shared/scan/scan_native_image_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.cardai.tcg/scan-image-processor');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'rectifyCard sends four corners as alternating x and y values',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'rectifyCard');
            expect(call.arguments, {
              'image': Uint8List.fromList([1, 2, 3]),
              'corners': [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
              'card_width': 10,
              'card_height': 14,
              'embedding_size': 2,
              'jpeg_quality': 85,
            });
            return {
              'card_image_bytes': Uint8List.fromList([0xff]),
              'embedding_rgb_bytes': Uint8List(2 * 2 * 3),
            };
          });

      final result = await const ScanNativeImageProcessor().rectifyCard(
        Uint8List.fromList([1, 2, 3]),
        const [
          ScanImagePoint(1, 2),
          ScanImagePoint(3, 4),
          ScanImagePoint(5, 6),
          ScanImagePoint(7, 8),
        ],
        cardWidth: 10,
        cardHeight: 14,
        embeddingSize: 2,
      );

      expect(result.cardImageBytes, [0xff]);
      expect(result.embeddingRgbBytes, hasLength(12));
    },
  );
}
