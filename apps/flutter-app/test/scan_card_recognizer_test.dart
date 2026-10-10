import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_card_recognizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const imageChannel = MethodChannel('com.cardai.tcg/scan-image-processor');
  const modelChannel = MethodChannel('com.cardai.tcg/scan-model-runtime');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  late double score;
  late bool failCorrection;
  late _FakeScanTextRecognizer textRecognizer;

  setUp(() {
    calls = [];
    score = 0.9;
    failCorrection = false;
    textRecognizer = _FakeScanTextRecognizer();
    messenger.setMockMethodCallHandler(imageChannel, (call) async {
      calls.add(call.method);
      final args = call.arguments as Map;
      if (call.method == 'prepareDetection') {
        expect(args['maximum_size'], 640);
        return {
          'source_width': 400,
          'source_height': 600,
          'resized_width': 40,
          'resized_height': 60,
          'rgb_bytes': Uint8List.fromList(
            List.generate(40 * 60 * 3, (index) => [10, 20, 30][index % 3]),
          ),
        };
      }
      if (call.method == 'prepareFallbackCard') {
        expect(args['image'], [1, 2, 3]);
        expect(args['card_width'], 745);
        expect(args['card_height'], 1043);
        return {
          'card_image_bytes': Uint8List.fromList([7, 8, 9]),
          'card_rgb_bytes': Uint8List.fromList(
            List.generate(745 * 1043 * 3, (index) => [0, 127, 255][index % 3]),
          ),
        };
      }
      if (failCorrection) {
        throw PlatformException(code: 'scan_image_processing_failed');
      }
      expect(args['corners'], [
        100.0,
        100.0,
        290.0,
        100.0,
        290.0,
        490.0,
        100.0,
        490.0,
      ]);
      expect(args['card_width'], 745);
      expect(args['card_height'], 1043);
      expect(args['jpeg_quality'], 85);
      return {
        'card_image_bytes': Uint8List.fromList([7, 8, 9]),
        'card_rgb_bytes': Uint8List.fromList(
          List.generate(745 * 1043 * 3, (index) => [0, 127, 255][index % 3]),
        ),
      };
    });
    messenger.setMockMethodCallHandler(modelChannel, (call) async {
      calls.add(call.method);
      final tensor = (call.arguments as Map)['tensor'] as Float32List;
      if (call.method == 'runDetection') {
        expect(tensor.length, 3 * 640 * 640);
        expect(tensor[0], closeTo((30 - 103.53) / 57.375, 0.00001));
        expect(tensor[640 * 640], closeTo((20 - 116.28) / 57.12, 0.00001));
        expect(
          tensor[2 * 640 * 640],
          closeTo((10 - 123.675) / 58.395, 0.00001),
        );
        expect(tensor[100], closeTo((114 - 103.53) / 57.375, 0.00001));
        final masks = Float32List(640 * 640);
        for (var y = 10; y < 50; y++) {
          for (var x = 10; x < 30; x++) {
            masks[y * 640 + x] = 1;
          }
        }
        return {
          'dets': Float32List.fromList([10, 10, 30, 50, score]),
          'dets_shape': [1, 1, 5],
          'masks': masks,
          'masks_shape': [1, 1, 640, 640],
        };
      }
      fail('The embedding model must not run for pHash recognition.');
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(imageChannel, null);
    messenger.setMockMethodCallHandler(modelChannel, null);
  });

  test(
    'the recognition pipeline hashes the corrected card without embedding inference',
    () async {
      final result = await createScanCardRecognizer(
        textRecognizer: textRecognizer,
      ).process(
        Uint8List.fromList([1, 2, 3]),
      );
      expect(result.r, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(result.g, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(result.b, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(result.cardImageBytes, [7, 8, 9]);
      expect(result.ocrText, 'LEAFEON EX\n200/187');
      expect(textRecognizer.lastBytes, [7, 8, 9]);
      expect(calls, [
        'prepareDetection',
        'runDetection',
        'rectifyCard',
      ]);
    },
  );

  test(
    'low confidence cannot proceed to hashing because hashes must describe a detected card',
    () async {
      score = 0.1;
      await expectLater(
        createScanCardRecognizer(
          textRecognizer: textRecognizer,
        ).process(Uint8List(3)),
        throwsA(isA<ScanImageProcessingException>()),
      );
      expect(calls, ['prepareDetection', 'runDetection']);
    },
  );

  test('OCR failure keeps the pHash result and omits OCR text', () async {
    textRecognizer.failure = StateError('OCR unavailable');

    final result = await createScanCardRecognizer(
      textRecognizer: textRecognizer,
    ).process(Uint8List.fromList([1, 2, 3]));

    expect(result.r, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(result.g, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(result.b, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(result.ocrText, isNull);
    expect(textRecognizer.lastBytes, [7, 8, 9]);
  });

  test('camera crop falls back to hashing the prepared crop when detection misses', () async {
    score = 0.1;
    final result = await createScanCardRecognizer(
      textRecognizer: textRecognizer,
    ).process(
      Uint8List.fromList([1, 2, 3]),
      allowCropFallback: true,
    );
    expect(result.r, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(result.g, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(result.b, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(result.cardImageBytes, [7, 8, 9]);
    expect(calls, [
      'prepareDetection',
      'runDetection',
      'prepareFallbackCard',
    ]);
  });

  test('camera crop falls back when perspective correction fails', () async {
    failCorrection = true;
    await createScanCardRecognizer(
      textRecognizer: textRecognizer,
    ).process(
      Uint8List.fromList([1, 2, 3]),
      allowCropFallback: true,
    );
    expect(calls, [
      'prepareDetection',
      'runDetection',
      'rectifyCard',
      'prepareFallbackCard',
    ]);
  });
}

class _FakeScanTextRecognizer implements ScanTextRecognizer {
  Uint8List? lastBytes;
  Object? failure;

  @override
  Future<String> recognize(Uint8List cardImageBytes) async {
    lastBytes = cardImageBytes;
    final failure = this.failure;
    if (failure != null) throw failure;
    return 'LEAFEON EX\n200/187';
  }
}
