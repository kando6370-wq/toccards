import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_ocr_text_normalizer.dart';

void main() {
  test('normalizes Latin OCR text before recognition upload', () {
    expect(
      normalizeLatinOcrText(
        '  \uFF2C\u00E9af\uFF45on  \u0131x\n'
        '\uFF12\uFF10\uFF10 \u2044 \uFF11\uFF18\uFF17 '
        '\u2014 Pok\u00E9mon\\EX  ',
      ),
      'LEAFEON IX 200/187 POKEMON/EX',
    );
  });

  test('keeps an empty OCR result empty', () {
    expect(normalizeLatinOcrText(null), '');
    expect(normalizeLatinOcrText(' \n\t '), '');
  });

  test('collapses whitespace around slash variants', () {
    expect(normalizeLatinOcrText('  TG  01 \uFF0F  102  '), 'TG 01/102');
    expect(normalizeOcrText('  TG  01 \uFF0F  102  '), 'TG 01/102');
  });

  test(
    'normalizes Japanese OCR and removes Latin letters and Arabic digits',
    () {
      expect(
        normalizeJapaneseOcrText(
          ' \uFF2C\uFF25\uFF21\uFF26\uFF25\uFF2F\uFF2E\uFF11\uFF12\uFF13 '
          '\uFF98\uFF70\uFF8C\uFF68\uFF71\u2010EX\n'
          '\u706B&\u6C34\u3002\u30DD\u30B1\u30E2\u30F3\u30AB\u30FC\u30C9 '
          '123\u2014\u9F8D ',
        ),
        '\u30EA\u30FC\u30D5\u30A3\u30A2 \u706B \u6C34 '
        '\u30DD\u30B1\u30E2\u30F3\u30AB\u30FC\u30C9 \u9F8D',
      );
    },
  );

  test('uses spaces for removed Japanese OCR characters', () {
    expect(
      normalizeJapaneseOcrText('\u706BABC\u6C34123\u98A8'),
      '\u706B \u6C34 \u98A8',
    );
  });

  test('keeps Hiragana, Katakana, Han, and the Japanese long sound mark', () {
    expect(
      normalizeJapaneseOcrText(
        '\u3072\u3089\u304C\u306A\u30FB\u30AB\u30BF\u30AB\u30CA\u30FC\u30FB\u6F22\u5B57',
      ),
      '\u3072\u3089\u304C\u306A \u30AB\u30BF\u30AB\u30CA\u30FC \u6F22\u5B57',
    );
  });

  test('drops Japanese OCR with fewer than three Japanese characters', () {
    expect(normalizeJapaneseOcrText('\u706B'), '');
    expect(normalizeJapaneseOcrText('\u706B\u6C34'), '');
    expect(
      normalizeJapaneseOcrText('\u706B\u6C34\u98A8'),
      '\u706B\u6C34\u98A8',
    );
  });

  test('merges normalized Latin and Japanese OCR without reordering', () {
    expect(
      mergeOcrText(
        latinOcrText: 'LEAFEON  EX 200/187',
        japaneseOcrText: ' \u30EA\u30FC\u30D5\u30A3\u30A2 ',
      ),
      'LEAFEON EX 200/187 \u30EA\u30FC\u30D5\u30A3\u30A2',
    );
    expect(
      mergeOcrText(latinOcrText: 'LEAFEON', japaneseOcrText: ''),
      'LEAFEON',
    );
    expect(
      mergeOcrText(
        latinOcrText: '',
        japaneseOcrText: '\u30EA\u30FC\u30D5\u30A3\u30A2',
      ),
      '\u30EA\u30FC\u30D5\u30A3\u30A2',
    );
    expect(mergeOcrText(latinOcrText: '', japaneseOcrText: ''), '');
  });
}
