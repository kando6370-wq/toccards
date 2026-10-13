import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_ocr_text_normalizer.dart';

void main() {
  test('normalizes Latin OCR text before recognition upload', () {
    expect(
      normalizeOcrText(
        '  \uFF2C\u00E9af\uFF45on  \u0131x\n'
        '\uFF12\uFF10\uFF10 \u2044 \uFF11\uFF18\uFF17 '
        '\u2014 Pok\u00E9mon\\EX  ',
      ),
      'LEAFEON IX 200/187 POKEMON/EX',
    );
  });

  test('keeps an empty OCR result empty', () {
    expect(normalizeOcrText(null), '');
    expect(normalizeOcrText(' \n\t '), '');
  });

  test('collapses whitespace around slash variants', () {
    expect(normalizeOcrText('  TG  01 \uFF0F  102  '), 'TG 01/102');
  });
}
