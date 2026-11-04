import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_text_recognizer_native.dart';

void main() {
  test('starts Latin and Japanese OCR in parallel before merging', () async {
    final latinStarted = Completer<void>();
    final japaneseStarted = Completer<void>();

    final result = recognizeParallelScanOcr(
      recognizeLatin: () async {
        latinStarted.complete();
        await japaneseStarted.future;
        return '  \uFF2C\u00E9afeon EX\n200 \uFF0F 187  ';
      },
      recognizeJapanese: () async {
        japaneseStarted.complete();
        await latinStarted.future;
        return ' \uFF98\uFF70\uFF8C\uFF68\uFF71 123 EX ';
      },
    );

    expect(await result, 'LEAFEON EX 200/187 \u30EA\u30FC\u30D5\u30A3\u30A2');
  });
}
