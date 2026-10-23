import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_debug_overlay/flutter_debug_overlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_environment.dart';
import 'package:kando_app/shared/debug/app_debug_overlay.dart';

void main() {
  test('debug overlay is enabled only for test environment builds', () {
    configureAppDebugOverlay();

    expect(DebugOverlay.enabled, AppConfig.isTestEnvironment);

    const child = SizedBox(key: Key('app-child'));
    final root = buildAppDebugOverlay(child);
    if (AppConfig.isTestEnvironment) {
      expect(root, isA<AppDebugOverlay>());
    } else {
      expect(identical(root, child), isTrue);
    }

    final dio = Dio();
    final initialInterceptorCount = dio.interceptors.length;
    addAppDebugHttpLogging(dio);
    expect(
      dio.interceptors.length,
      initialInterceptorCount + (AppConfig.isTestEnvironment ? 1 : 0),
    );
  });

  testWidgets('test environment uses the default two-finger detector', (
    tester,
  ) async {
    configureAppDebugOverlay();
    if (!AppConfig.isTestEnvironment) return;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildAppDebugOverlay(
            const ColoredBox(color: Colors.black, child: SizedBox.expand()),
          ),
        ),
      ),
    );

    final overlayState = tester.state<DebugOverlayState>(
      find.byType(DebugOverlay),
    );
    expect(overlayState.isVisible, isFalse);
    expect(find.byType(DebugDetector), findsOneWidget);
    expect(find.byKey(const Key('app-debug-overlay-button')), findsNothing);

    final firstFinger = await tester.startGesture(const Offset(100, 100));
    final secondFinger = await tester.startGesture(const Offset(140, 100));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));

    expect(overlayState.isVisible, isTrue);
    await firstFinger.up();
    await secondFinger.up();
  });
}
