import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _resources = 'android/app/src/main/res';
const _densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
const _iosIcon =
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy Android launcher artwork keeps the iOS proportions', () async {
    final ios = await _logoGeometry(_iosIcon);
    for (final density in _densities) {
      final legacy = await _logoGeometry(
        '$_resources/mipmap-$density/ic_launcher.png',
      );
      _expectSameProportions(legacy.bounds, ios.bounds, density);
    }
  });

  test(
    'adaptive launcher keeps the whole iOS artwork inside the safe area',
    () async {
      final ios = await _logoGeometry(_iosIcon);
      final xml = await File(
        '$_resources/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsString();
      final foreground = RegExp(
        r'<foreground\b[^>]*(?:/>|>.*?</foreground>)',
        dotAll: true,
      ).firstMatch(xml)!.group(0)!;
      expect(foreground, contains('@mipmap/ic_launcher_foreground'));
      final left = _inset(foreground, 'Left');
      final top = _inset(foreground, 'Top');
      final right = _inset(foreground, 'Right');
      final bottom = _inset(foreground, 'Bottom');
      // AdaptiveIconDrawable expands each layer by 25% on every edge.
      final scaleX = 1.5 * (1 - left - right);
      final scaleY = 1.5 * (1 - top - bottom);
      final offsetX = -0.25 + 1.5 * left;
      final offsetY = -0.25 + 1.5 * top;
      for (final density in _densities) {
        final logo = await _logoGeometry(
          '$_resources/mipmap-$density/ic_launcher_foreground.png',
        );
        final visibleBounds = ui.Rect.fromLTRB(
          offsetX + scaleX * logo.bounds.left,
          offsetY + scaleY * logo.bounds.top,
          offsetX + scaleX * logo.bounds.right,
          offsetY + scaleY * logo.bounds.bottom,
        );
        _expectSameProportions(visibleBounds, ios.bounds, density);
        final centerOffset = math.sqrt(
          math.pow(offsetX + scaleX / 2 - 0.5, 2) +
              math.pow(offsetY + scaleY / 2 - 0.5, 2),
        );
        expect(
          logo.radius * math.max(scaleX, scaleY) + centerOffset,
          lessThan(66 / 72 / 2),
          reason: '$density card artwork must survive the circular safe area.',
        );
      }
    },
  );
}

double _inset(String xml, String edge) {
  final value = RegExp(
    'android:inset$edge="([^"]+)"',
  ).firstMatch(xml)?.group(1);
  if (value == null) return 0;
  if (!value.endsWith('%')) {
    throw StateError('Launcher insets must scale with the icon bounds.');
  }
  return double.parse(value.substring(0, value.length - 1)) / 100;
}

void _expectSameProportions(ui.Rect actual, ui.Rect expected, String density) {
  final actualEdges = [actual.left, actual.top, actual.right, actual.bottom];
  final expectedEdges = [
    expected.left,
    expected.top,
    expected.right,
    expected.bottom,
  ];
  for (var index = 0; index < actualEdges.length; index++) {
    expect(
      actualEdges[index],
      closeTo(expectedEdges[index], 0.02),
      reason: '$density must retain the iOS artwork scale and margins.',
    );
  }
}

Future<({ui.Rect bounds, double radius})> _logoGeometry(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final image = (await codec.getNextFrame()).image;
  try {
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var left = image.width;
    var top = image.height;
    var right = 0;
    var bottom = 0;
    var radius = 0.0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        // The dark background stays below 64; retain the visible card artwork.
        if (pixels.getUint8(offset + 3) < 128 ||
            [
              0,
              1,
              2,
            ].every((channel) => pixels.getUint8(offset + channel) <= 64)) {
          continue;
        }
        left = math.min(left, x);
        top = math.min(top, y);
        right = math.max(right, x + 1);
        bottom = math.max(bottom, y + 1);
        radius = math.max(
          radius,
          math.sqrt(
            math.pow((x + 0.5) / image.width - 0.5, 2) +
                math.pow((y + 0.5) / image.height - 0.5, 2),
          ),
        );
      }
    }
    expect(
      right,
      greaterThan(left),
      reason: '$path must contain the card mark.',
    );
    return (
      bounds: ui.Rect.fromLTRB(
        left / image.width,
        top / image.height,
        right / image.width,
        bottom / image.height,
      ),
      radius: radius,
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}
