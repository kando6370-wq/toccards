import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _slashVariants = RegExp(r'[\u2044\uFF0F\\]');
final _dashVariants = RegExp(r'[\u2010\u2011\u2012\u2013\u2014\u2212]');
final _combiningMarks = RegExp(
  r'[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]+',
);
final _unsupportedOcrCharacters = RegExp(r'[^A-Z0-9/]+');
final _slashWhitespace = RegExp(r'\s*/\s*');
final _whitespace = RegExp(r'\s+');

String normalizeOcrText(String? raw) {
  final compatibilityNormalized = unorm
      .nfkc(raw ?? '')
      .replaceAll('\u0131', 'i')
      .replaceAll(_slashVariants, '/')
      .replaceAll(_dashVariants, ' ');

  return unorm
      .nfkd(compatibilityNormalized)
      .replaceAll(_combiningMarks, '')
      .toUpperCase()
      .replaceAll(_unsupportedOcrCharacters, ' ')
      .replaceAll(_slashWhitespace, '/')
      .replaceAll(_whitespace, ' ')
      .trim();
}
