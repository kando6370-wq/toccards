import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_card_recognizer_contract.dart';
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
    'crop maps the visible frame through BoxFit.cover before native decoding',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'cropViewfinder');
            final args = call.arguments as Map;
            expect(args['image'], [1, 2, 3]);
            expect(args['preview_width'], 1080.0);
            expect(args['preview_height'], 1920.0);
            final frame = args['frame'] as List;
            expect(frame[0], closeTo(0.2051, 0.0001));
            expect(frame[1], closeTo(213 / 844, 0.0001));
            expect(frame[2], closeTo(0.7949, 0.0001));
            expect(frame[3], closeTo(613 / 844, 0.0001));
            return Uint8List.fromList([0xff, 0xd8]);
          });

      final result = await const ScanNativeImageProcessor().cropViewfinder(
        Uint8List.fromList([1, 2, 3]),
        viewfinder: const Rect.fromLTWH(55, 213, 280, 400),
        viewport: const Size(390, 844),
        previewSize: const Size(1080, 1920),
      );
      expect(result, [0xff, 0xd8]);
    },
  );

  test(
    'invalid viewfinder cannot silently fall back to the full photo',
    () async {
      await expectLater(
        const ScanNativeImageProcessor().cropViewfinder(
          Uint8List.fromList([1, 2, 3]),
          viewfinder: const Rect.fromLTWH(0, 0, 200, 200),
          viewport: const Size(100, 100),
          previewSize: const Size(1080, 1920),
        ),
        throwsA(isA<ScanImageProcessingException>()),
      );
    },
  );

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
