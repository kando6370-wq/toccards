import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/scan/scan_card_number_reader.dart';

void main() {
  test(
    'extracts the collector number because identical artwork needs the printed version identifier',
    () {
      expect(extractScanCardNumber('Leafeon ex\n200 / 187 SAR'), '200/187');
      expect(extractScanCardNumber('No. O18／O66'), '018/066');
      expect(extractScanCardNumber('PROMO 397 / SM - P'), '397/SM-P');
      expect(extractScanCardNumber('Art Academy\nXY - P'), 'XY-P');
    },
  );

  test(
    'ignores ordinary text because OCR hints must not invent a card number',
    () {
      expect(extractScanCardNumber('Pikachu HP 120 Thunder Jolt 30'), isNull);
    },
  );
}
