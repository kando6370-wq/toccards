import 'package:dio/dio.dart';
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

  testWidgets('test environment button opens the debug overlay', (
    tester,
  ) async {
    configureAppDebugOverlay();
    if (!AppConfig.isTestEnvironment) return;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: buildAppDebugOverlay(const SizedBox.expand())),
      ),
    );

    final overlayState = tester.state<DebugOverlayState>(
      find.byType(DebugOverlay),
    );
    expect(overlayState.isVisible, isFalse);
    expect(find.byKey(const Key('app-debug-overlay-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-debug-overlay-button')));

    expect(overlayState.isVisible, isTrue);
  });
}
