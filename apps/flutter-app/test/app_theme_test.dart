import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/features/card_detail/card_detail_page.dart';
import 'package:kando_app/features/home/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android body, labels, and titles share the Inter app typography', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final textTheme = buildKandoTheme().textTheme;

    expect(textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(textTheme.labelLarge?.fontFamily, 'Inter');
    expect(textTheme.titleLarge?.fontFamily, 'Inter');
  });

  testWidgets(
    'Android shared copy inherits Inter while branded headings keep their font',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildKandoTheme(),
            home: const Scaffold(
              body: Column(
                children: [
                  Text('Portfolio total'),
                  TextButton(onPressed: null, child: Text('View all')),
                  Text(
                    'Top Performers',
                    style: TextStyle(fontFamily: 'Fraunces'),
                  ),
                ],
              ),
            ),
          ),
        );

        expect(_effectiveStyle(tester, 'Portfolio total').fontFamily, 'Inter');
        expect(_effectiveStyle(tester, 'View all').fontFamily, 'Inter');
        expect(
          _effectiveStyle(tester, 'Top Performers').fontFamily,
          'Fraunces',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('iOS keeps the platform typography', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final expectedBodyFamily = ThemeData(
        platform: TargetPlatform.iOS,
        useMaterial3: true,
      ).textTheme.bodyMedium?.fontFamily;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildKandoTheme(),
          home: const Scaffold(body: Text('Portfolio total')),
        ),
      );

      expect(
        _effectiveStyle(tester, 'Portfolio total').fontFamily,
        expectedBodyFamily,
      );
      expect(expectedBodyFamily, isNot('Inter'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test('${platform.name} keeps the Flutter platform typography', () {
      debugDefaultTargetPlatformOverride = platform;
      final expected = ThemeData(
        platform: platform,
        useMaterial3: true,
      ).textTheme;

      final actual = buildKandoTheme().textTheme;

      expect(actual.bodyMedium?.fontFamily, expected.bodyMedium?.fontFamily);
      expect(actual.labelLarge?.fontFamily, expected.labelLarge?.fontFamily);
      expect(actual.titleLarge?.fontFamily, expected.titleLarge?.fontFamily);
    });
  }

  test('Inter assets declare every app weight and the italic face', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final inter = manifest.cast<Map<String, dynamic>>().singleWhere(
      (family) => family['family'] == 'Inter',
    );
    final fonts = (inter['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (font) => (
            asset: font['asset'] as String,
            weight: font['weight'] as int? ?? 400,
            style: font['style'] as String? ?? 'normal',
          ),
        )
        .toSet();

    expect(fonts, {
      (asset: 'assets/fonts/Inter-Regular.ttf', weight: 400, style: 'normal'),
      (asset: 'assets/fonts/Inter-Medium.ttf', weight: 500, style: 'normal'),
      (asset: 'assets/fonts/Inter-SemiBold.ttf', weight: 600, style: 'normal'),
      (asset: 'assets/fonts/Inter-Bold.ttf', weight: 700, style: 'normal'),
      (asset: 'assets/fonts/Inter-ExtraBold.ttf', weight: 800, style: 'normal'),
      (asset: 'assets/fonts/Inter-Italic.ttf', weight: 400, style: 'italic'),
    });
  });

  test('bundled Inter uses proportional glyph widths', () {
    final narrowWidth = _measureInterText('iiii');
    final wideWidth = _measureInterText('WWWW');

    expect(narrowWidth, lessThan(wideWidth));
  });

  test('Android Home chart tooltips change only their font family', () {
    for (final scenario in [
      (isPerformance: true, isDate: true),
      (isPerformance: true, isDate: false),
      (isPerformance: false, isDate: true),
      (isPerformance: false, isDate: false),
    ]) {
      final original = homeChartTooltipTextStyle(
        isPerformance: scenario.isPerformance,
        isDate: scenario.isDate,
      );
      final android = homeChartTooltipTextStyle(
        isPerformance: scenario.isPerformance,
        isDate: scenario.isDate,
        fontFamily: 'Inter',
      );

      expect(android, original.copyWith(fontFamily: 'Inter'));
    }

    expect(
      homeChartTooltipTextStyle(isPerformance: true, isDate: false).fontFamily,
      'Geist',
    );
    expect(
      homeChartTooltipTextStyle(isPerformance: false, isDate: false).fontFamily,
      isNull,
    );
  });

  test('Android Card Detail chart rows change only their font family', () {
    final original = buildCardDetailChartTooltipRow(
      r'Market Value: $790.00',
    ).children!.cast<TextSpan>();
    final android = buildCardDetailChartTooltipRow(
      r'Market Value: $790.00',
      fontFamily: 'Inter',
    ).children!.cast<TextSpan>();

    expect(android.map((span) => span.text), original.map((span) => span.text));
    for (var index = 0; index < original.length; index++) {
      expect(
        android[index].style,
        original[index].style!.copyWith(fontFamily: 'Inter'),
      );
    }
    expect(original.first.style?.fontFamily, 'Geist');
    expect(original.last.style?.fontFamily, isNull);
  });
}

TextStyle _effectiveStyle(WidgetTester tester, String text) {
  final element = tester.element(find.text(text));
  final widget = element.widget as Text;
  return DefaultTextStyle.of(element).style.merge(widget.style);
}

double _measureInterText(String text) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  );
  try {
    painter.layout();
    return painter.width;
  } finally {
    painter.dispose();
  }
}
