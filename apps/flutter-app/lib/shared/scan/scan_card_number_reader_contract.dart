import 'dart:typed_data';

abstract interface class ScanCardNumberReader {
  Future<String?> read(Uint8List cardImageBytes);
}

String? extractScanCardNumber(String text) {
  final normalized = text.toUpperCase().replaceAll('／', '/');
  final fraction = RegExp(
    r'(?<![A-Z0-9])([0-9OIL]{1,4})\s*/\s*([0-9OIL]{1,4}|[A-Z]{1,5}\s*-\s*P)(?![A-Z0-9])',
  ).firstMatch(normalized);
  if (fraction != null) {
    return '${_normalizeDigits(fraction.group(1)!)}'
        '/${_normalizeCardNumberPart(fraction.group(2)!)}';
  }

  final promo = RegExp(
    r'(?<![A-Z0-9])([A-Z]{1,5})\s*-\s*P(?![A-Z0-9])',
  ).firstMatch(normalized);
  return promo == null ? null : '${promo.group(1)}-P';
}

String _normalizeCardNumberPart(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), '');
  return compact.endsWith('-P') ? compact : _normalizeDigits(compact);
}

String _normalizeDigits(String value) =>
    value.replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1');
