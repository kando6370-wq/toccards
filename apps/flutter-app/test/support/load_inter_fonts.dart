import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

Future<void> loadInterFonts() async {
  final loader = FontLoader('Inter');
  for (final name in [
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
    'Italic',
  ]) {
    loader.addFont(rootBundle.load('assets/fonts/Inter-$name.ttf'));
  }
  await loader.load();
  double measure(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontFamily: 'Inter', fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    try {
      return painter.width;
    } finally {
      painter.dispose();
    }
  }

  if (measure('iiii') >= measure('WWWW')) {
    throw StateError('Inter must load before any widget uses the font family.');
  }
}
