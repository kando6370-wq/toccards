import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_camera.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';
import 'package:kando_app/features/scan/scan_review_repository.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';
import 'package:kando_app/shared/scan/scan_image_hasher.dart';

import '../support/mock_home_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  test('Figma scan SVG icons use Flutter-compatible fill colors', () async {
    const iconAssets = [
      'assets/scan/close.svg',
      'assets/scan/flash.svg',
      'assets/scan/search.svg',
      'assets/scan/align.svg',
      'assets/scan/gallery.svg',
      'assets/scan/done.svg',
    ];

    for (final asset in iconAssets) {
      final svg = await rootBundle.loadString(asset);
      expect(svg, isNot(contains('var(')), reason: asset);
    }
  });

  testWidgets(
    'Figma scan pre-scan keeps the photographic camera viewport full bleed',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await _pumpScanTestApp(tester);

      final background = find.byKey(const Key('scan-figma-camera-background'));
      expect(background, findsOneWidget);
      expect(tester.widget<Image>(background).fit, BoxFit.cover);
    },
  );

  testWidgets(
    'Scan uses the live camera session because preview, flash, and capture must stay in the Figma flow',
    (tester) async {
      final camera = _TestScanCameraSession();
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        recognizeResult: Future.value(
          const ScanResolution.matched(
            scanId: 'live-scan',
            cardRef: 'live-card',
            matchName: 'Live camera card',
            candidates: ['Live camera card'],
            candidateCardRefs: ['live-card'],
          ),
        ),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanCameraFactory: _TestScanCameraFactory(camera),
      );

      expect(find.byKey(const Key('scan-live-camera-preview')), findsOneWidget);
      expect(find.byKey(const Key('test-live-camera-preview')), findsOneWidget);

      await tester.tap(find.byTooltip('Turn flash on'));
      await tester.pump();
      expect(camera.flashEnabled, isTrue);
      expect(find.byTooltip('Turn flash off'), findsOneWidget);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      expect(camera.takePhotoCount, 1);
      expect(source.recognizedImages.single.fileName, 'live-camera.jpg');
      expect(
        source.recognizedImages.single.bytes,
        Uint8List.fromList([9, 8, 7]),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(camera.disposed, isTrue);
      expect(camera.flashEnabled, isFalse);
    },
  );

  testWidgets(
    'stable camera frames create only one recognition and no_match resumes streaming because frames are not audit scans',
    (tester) async {
      final recognition = Completer<ScanResolution>();
      final camera = _TestScanCameraSession();
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        recognizeResult: recognition.future,
        frameDetection: _stableFrameDetection,
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanCameraFactory: _TestScanCameraFactory(camera),
      );

      for (var index = 0; index < 16; index += 1) {
        camera.emitFrame();
        await tester.pump();
      }
      expect(source.detectFrameCount, 8);
      expect(camera.takePhotoCount, 1);
      expect(source.recognizedImages, hasLength(1));
      expect(camera.onFrame, isNull);

      recognition.complete(const ScanResolution.noMatch());
      await tester.pump();
      expect(camera.startStreamCount, 2);
      expect(camera.onFrame, isNotNull);
    },
  );

  testWidgets(
    'Scan closes flash in background and reopens the camera on resume because camera resources cannot outlive the active page',
    (tester) async {
      final first = _TestScanCameraSession();
      final factory = _TestScanCameraFactory(first);
      await _pumpScanTestApp(tester, scanCameraFactory: factory);
      await tester.tap(find.byTooltip('Turn flash on'));
      await tester.pump();
      expect(first.flashEnabled, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(first.disposed, isTrue);
      expect(first.flashEnabled, isFalse);

      final second = _TestScanCameraSession();
      factory.session = second;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(const Key('scan-live-camera-preview')), findsOneWidget);
      expect(second.disposed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(second.disposed, isTrue);
    },
  );

  testWidgets('Figma scan pre-scan renders at the 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: const ProviderScope(
          child: RepaintBoundary(
            key: Key('scan-figma-golden'),
            child: ScanPage(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('scan-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_scan_before_328_10858_390x844.png',
      ),
    );
  });

  testWidgets('Figma scan scanning renders at the 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: const ProviderScope(
          child: RepaintBoundary(
            key: Key('scan-scanning-figma-golden'),
            child: ScanPage(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Photo'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('scan-scanning-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_scan_scanning_131_19516_390x844.png',
      ),
    );
  });

  testWidgets(
    'Figma recognition replaces the scan line before returning a match',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byKey(const Key('scan-figma-recognizing-overlay')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);
      expect(find.text('CANCEL'), findsNothing);
      expect(find.byTooltip('Close Scan'), findsOneWidget);
      expect(find.byTooltip('Search Cards'), findsOneWidget);
      expect(find.text('ALIGN CARD HERE'), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsOneWidget);
      expect(find.byTooltip('Choose from Library'), findsOneWidget);
      expect(find.text('Matched'), findsNothing);
    },
  );

  testWidgets('Figma recognition renders at the 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: const ProviderScope(
          child: RepaintBoundary(
            key: Key('scan-recognizing-figma-golden'),
            child: ScanPage(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump(const Duration(seconds: 1));

    await expectLater(
      find.byKey(const Key('scan-recognizing-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_scan_recognizing_continuous_390x844.png',
      ),
    );
  });

  testWidgets(
    'Figma scan reveal restores camera controls before returning a match',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.text('Scanning...'), findsOneWidget);
      expect(find.text('ALIGN CARD HERE'), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);
      expect(find.text('Matched'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'DONE'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('Figma scan reveal renders at the 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: const ProviderScope(
          child: RepaintBoundary(
            key: Key('scan-revealing-figma-golden'),
            child: ScanPage(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1500));

    expect(tester.getTopLeft(find.byTooltip('Choose from Library')).dx, 31);
    expect(tester.getTopLeft(find.byTooltip('Choose from Library')).dy, 741);

    await expectLater(
      find.byKey(const Key('scan-revealing-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_scan_revealing_continuous_390x844.png',
      ),
    );
  });

  testWidgets(
    'Dismissing Figma scan feedback does not discard its pending result',
    (tester) async {
      final result = Completer<ScanResolution>();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(photoResult: result.future),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.byTooltip('Dismiss scan feedback'));
      await tester.pump();

      expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
      expect(find.text('Matched'), findsNothing);

      result.complete(
        const ScanResolution.matched(
          scanId: 'scan-mega',
          cardRef: 'card-mega',
          matchName: 'Mega Lucario ex',
          candidates: ['Mega Lucario ex'],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(
        find.byKey(const Key('scan-figma-complete-result')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Figma scan waits for its reveal animation before showing a completed recognition',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(
            const ScanResolution.matched(
              scanId: 'scan-mega',
              cardRef: 'card-mega',
              matchName: 'Mega Lucario ex',
              candidates: ['Mega Lucario ex'],
            ),
          ),
        ),
        tickerEnabled: false,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.text('Matched'), findsNothing);
    },
  );

  testWidgets(
    'A delayed Figma recognition remains in reveal feedback until it resolves',
    (tester) async {
      final result = Completer<ScanResolution>();
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(photoResult: result.future),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 1530));

      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.text('Matched'), findsNothing);

      result.complete(
        const ScanResolution.matched(
          scanId: 'scan-mega',
          cardRef: 'card-mega',
          matchName: 'Mega Lucario ex',
          candidates: ['Mega Lucario ex'],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('scan-figma-complete-result')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Figma scan completion renders its camera result overlay before review',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);

      expect(
        find.byKey(const Key('scan-figma-complete-background')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scan-figma-complete-result')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scan-figma-complete-count')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Scanned: 1/1. Mega Lucario ex. PSA 10. Estimated value '
          r'$16,785.28. Total $16,874.16.',
        ),
        findsOneWidget,
      );
      semanticsHandle.dispose();
      expect(find.byTooltip('Modify scan match'), findsOneWidget);
      expect(find.text('Matched'), findsNothing);
      expect(find.byTooltip('Review completed scan'), findsOneWidget);
      expect(
        find.byKey(const Key('scan-figma-complete-focus-outline')),
        findsNothing,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        find.byKey(const Key('scan-figma-complete-focus-outline')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Review your matches'), findsOneWidget);
    },
  );

  testWidgets('Figma scan completion renders at the 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: ProviderScope(
          overrides: [
            scanResultSourceProvider.overrideWithValue(
              _defaultTestScanResultSource(),
            ),
          ],
          child: const RepaintBoundary(
            key: Key('scan-completed-figma-golden'),
            child: ScanPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('scan-completed-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_scan_completed_131_19700_390x844.png',
      ),
    );
  });

  testWidgets('Figma review renders at the 390x844 baseline', (tester) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    await (FontLoader(
      'Fraunces',
    )..addFont(rootBundle.load('assets/fonts/Fraunces-Variable.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await _pumpScanTestApp(tester);
    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.byTooltip('Review completed scan'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('scan-page-test-boundary')),
      matchesGoldenFile(
        'goldens/rendered/figma_scan_review_131_19961_390x844.png',
      ),
    );
  });

  testWidgets(
    'Figma scan failure dismisses feedback without restoring the generic failure card',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(const ScanResolution.failed()),
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);

      expect(find.byKey(const Key('scan-figma-failure-toast')), findsOneWidget);
      expect(find.text('Failed'), findsNothing);

      await tester.tap(find.byTooltip('Dismiss failed scan feedback'));
      await tester.pump();

      expect(find.byKey(const Key('scan-figma-failure-toast')), findsNothing);
      expect(find.text('Failed'), findsNothing);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);

      expect(find.text('Failed'), findsNWidgets(2));
    },
  );

  testWidgets('Figma scan failure retries through the existing scan flow', (
    tester,
  ) async {
    final source = _TestScanResultSource(
      photoResult: Future.value(
        ScanResolution.failed(
          imageBytes: Uint8List.fromList([1, 2, 3]),
          imageFileName: 'failed-card.jpg',
        ),
      ),
      retryResult: Future.value(
        const ScanResolution.matched(
          scanId: 'scan-mega',
          cardRef: 'card-mega',
          matchName: 'Mega Lucario ex',
          candidates: ['Mega Lucario ex'],
        ),
      ),
    );
    await _pumpScanTestApp(tester, scanResultSource: source);

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.byTooltip('Tap to retry'));
    await tester.pump();

    expect(source.lastRetryBytes, Uint8List.fromList([1, 2, 3]));
    expect(source.lastRetryFileName, 'failed-card.jpg');
    expect(find.byKey(const Key('scan-figma-scanning-line')), findsOneWidget);

    await _completeFigmaScan(tester);
    expect(find.byKey(const Key('scan-figma-complete-result')), findsOneWidget);
  });

  testWidgets('Figma failure exposes retry feedback to semantics', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    await _pumpScanTestApp(
      tester,
      scanResultSource: _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
      ),
    );

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);

    expect(
      find.bySemanticsLabel(
        '0 of 1 cards scanned. Scan 1 failed. Tap to retry.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Tap to retry'), findsOneWidget);
    semanticsHandle.dispose();
  });

  testWidgets(
    'Figma failure returns to generic results after an earlier match is added',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(
            const ScanResolution.matched(
              scanId: 'scan-mega',
              cardRef: 'card-mega',
              matchName: 'Mega Lucario ex',
              candidates: ['Mega Lucario ex'],
            ),
          ),
          subsequentPhotoResults: [Future.value(const ScanResolution.failed())],
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Modify scan match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add this card'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);

      expect(find.byKey(const Key('scan-figma-failure-toast')), findsNothing);
      expect(find.text('Failed'), findsOneWidget);
    },
  );

  testWidgets('Figma failure retries from the right edge of its retry label', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await _pumpScanTestApp(
      tester,
      scanResultSource: _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
      ),
    );

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tapAt(const Offset(174, 675));
    await tester.pump();

    expect(find.byKey(const Key('scan-figma-scanning-line')), findsOneWidget);
  });

  testWidgets('Figma scan failure renders at the 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: ProviderScope(
          overrides: [
            scanResultSourceProvider.overrideWithValue(
              _TestScanResultSource(
                photoResult: Future.value(const ScanResolution.failed()),
              ),
            ),
          ],
          child: const RepaintBoundary(
            key: Key('scan-failed-figma-golden'),
            child: ScanPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('scan-failed-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_scan_failed_131_19795_390x844.png',
      ),
    );
  });

  testWidgets('Cancelling a Figma scan ignores its eventual recognition', (
    tester,
  ) async {
    final result = Completer<ScanResolution>();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await _pumpScanTestApp(
      tester,
      scanResultSource: _TestScanResultSource(photoResult: result.future),
    );

    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel scan'));
    await tester.pump();

    result.complete(
      const ScanResolution.matched(
        scanId: 'scan-mega',
        cardRef: 'card-mega',
        matchName: 'Mega Lucario ex',
        candidates: ['Mega Lucario ex'],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1530));

    expect(find.text('Matched'), findsNothing);
  });

  testWidgets(
    'Figma scan pre-scan uses exported icons without Material glyph fallback',
    (tester) async {
      await _pumpScanTestApp(tester);

      expect(find.byKey(const Key('scan-figma-close-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-flash-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-search-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-align-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-gallery-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-done-icon')), findsOneWidget);
    },
  );

  testWidgets('Figma scan pre-scan keeps its camera overlay and label font', (
    tester,
  ) async {
    await _pumpScanTestApp(tester);

    final overlay = find.byKey(const Key('scan-figma-camera-overlay'));
    expect(overlay, findsOneWidget);
    expect(tester.widget<ColoredBox>(overlay).color, const Color(0x1A0D0F08));
    expect(
      tester.widget<Text>(find.text('GALLERY')).style?.fontFamily,
      'Geist',
    );
    expect(tester.widget<Text>(find.text('DONE')).style?.fontFamily, 'Geist');
  });

  testWidgets(
    'Scan creates reviewable matches because scans are not saved automatically',
    (tester) async {
      final reviewRepository = _FakeScanReviewRepository();
      await _pumpScanTestApp(tester, scanReviewRepository: reviewRepository);

      expect(find.text('ALIGN CARD HERE'), findsOneWidget);
      expect(find.text('GALLERY'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsOneWidget);
      expect(find.byTooltip('Choose from Library'), findsOneWidget);
      expect(find.text('Review your matches'), findsNothing);
      expect(
        find.text(
          'Scan is coming soon. Use Search to find cards manually for now.',
        ),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();

      expect(find.byKey(const Key('scan-figma-scanning-line')), findsOneWidget);
      expect(
        find.byKey(const Key('scan-figma-scanning-line-canvas')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('scan-figma-scanning-line'))).dy,
        291,
      );
      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.text('Scanning'), findsNothing);
      expect(find.byTooltip('Take Photo'), findsOneWidget);
      expect(find.byTooltip('Choose from Library'), findsOneWidget);

      await _completeFigmaScan(tester);

      expect(
        find.byKey(const Key('scan-figma-complete-result')),
        findsOneWidget,
      );
      expect(find.byTooltip('Modify scan match'), findsOneWidget);

      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();

      expect(find.text('Adding to Main'), findsOneWidget);
      expect(find.text('Collection item'), findsOneWidget);
      expect(find.text('Portfolio'), findsNothing);
      expect(find.text('YOUR PICTURE'), findsOneWidget);
      expect(find.text('OUR MATCH'), findsOneWidget);
      expect(find.text('Top matched results:'), findsOneWidget);
      expect(find.text('Near Mint (NM)'), findsOneWidget);
      expect(find.byKey(const Key('scan-review-total')), findsOneWidget);
      expect(find.text(r'$25.00'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('scan-review-list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-review-folder-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adding to Trade').last);
      await tester.enterText(
        find.byKey(const Key('scan-review-quantity-1')),
        '2',
      );
      await tester.tap(find.byKey(const Key('scan-review-grader-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PSA').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan-review-grade-1')), findsOneWidget);
      expect(find.text(r'$200.00'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('scan-review-price-1')),
        '12.50',
      );
      await tester.enterText(
        find.byKey(const Key('scan-review-notes-1')),
        'Pulled from trade binder',
      );

      await tester.tap(find.text('Add this card'));
      await tester.pumpAndSettle();

      expect(find.text('Added to Portfolio'), findsWidgets);
      expect(find.text('Mega Lucario ex'), findsWidgets);
      expect(reviewRepository.confirmedScanIds, ['scan-mega']);
      final submitted = reviewRepository.confirmedItems.single;
      expect(submitted.folderId, 'trade');
      expect(submitted.quantity, 2);
      expect(submitted.grader, 'PSA');
      expect(submitted.condition, isNull);
      expect(submitted.grade, 10);
      expect(submitted.language, 'English');
      expect(submitted.finish, 'Holofoil');
      expect(submitted.purchasePrice, 12.5);
      expect(submitted.purchaseCurrency, 'USD');
      expect(submitted.notes, 'Pulled from trade binder');
    },
  );

  testWidgets(
    'Review keeps the match unsaved when confirmation fails because local Added state is not proof of persistence',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanReviewRepository: _FakeScanReviewRepository(
          failure: Exception('confirm failed'),
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add this card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add this card'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Added to Portfolio'), findsNothing);
    },
  );

  testWidgets(
    'Review confirms the selected candidate because users can correct the OCR top match',
    (tester) async {
      final repository = _FakeScanReviewRepository();
      await _pumpScanTestApp(tester, scanReviewRepository: repository);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('scan-review-list')),
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('scan-review-candidate-card-lucario')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add this card'));
      await tester.pumpAndSettle();

      expect(repository.confirmedItems.single.cardRef, 'card-lucario');
    },
  );

  testWidgets('Cancel discards an unfinished Figma scan', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await _pumpScanTestApp(tester);

    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel scan'));
    await tester.pump();

    expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);
    expect(find.byTooltip('Take Photo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Matched'), findsNothing);
  });

  testWidgets('Figma scan accepts concurrent capture requests', (tester) async {
    await _pumpScanTestApp(tester);

    await tester.tap(find.byTooltip('Take Photo'));
    await tester.tap(find.byTooltip('Choose from Library'));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byKey(const Key('scan-figma-recognizing-overlay')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);
    expect(find.text('CANCEL'), findsNothing);
    expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
    expect(find.byKey(const Key('scan-active-item-2')), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
    expect(find.byTooltip('Choose from Library'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1530));
    expect(find.text('Mega Lucario ex'), findsOneWidget);
    expect(find.text('No Match Found'), findsOneWidget);
  });

  testWidgets(
    'Gallery creates one Scanning item per selected image because batch imports must remain independently reviewable',
    (tester) async {
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        libraryResults: [
          for (var index = 0; index < 3; index += 1)
            Future.value(
              ScanResolution.matched(
                scanId: 'gallery-scan-$index',
                cardRef: 'gallery-card-$index',
                matchName: 'Gallery card $index',
                candidates: ['Gallery card $index'],
                candidateCardRefs: ['gallery-card-$index'],
              ),
            ),
        ],
      );
      await _pumpScanTestApp(tester, scanResultSource: source);

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pump();

      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-active-item-2')), findsOneWidget);
      expect(find.byKey(const Key('scan-active-item-3')), findsOneWidget);
      expect(find.text('Scanned: 0/3'), findsOneWidget);
    },
  );

  testWidgets(
    'No Match scan offers Search Manually because unmatched cards cannot enter review',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Choose from Library'));
      await _completeFigmaScan(tester);

      expect(find.text('No Match Found'), findsOneWidget);
      expect(find.text('Search Manually'), findsOneWidget);
      final noMatchDone = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'DONE'),
      );
      expect(noMatchDone.onPressed, isNull);

      await tester.tap(find.text('Search Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Search cards, sets, or characters'), findsOneWidget);
      expect(find.text('Squirtle'), findsOneWidget);
    },
  );

  testWidgets('Scan keeps capture controls available across multiple results', (
    tester,
  ) async {
    final repository = _FakeScanReviewRepository();
    await _pumpScanTestApp(tester, scanReviewRepository: repository);

    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump();
    expect(find.byKey(const Key('scan-figma-scanning-line')), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);

    await _completeFigmaScan(tester);

    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump();
    expect(find.byTooltip('Take Photo'), findsOneWidget);

    await _completeFigmaScan(tester);

    await tester.tap(find.byTooltip('Choose from Library'));
    await tester.pump();
    expect(find.byTooltip('Choose from Library'), findsOneWidget);

    await _completeFigmaScan(tester);

    expect(find.text('Mega Lucario ex'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('No Match Found'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Delete'), findsWidgets);
    expect(find.text('Search Manually'), findsOneWidget);

    final doneWithMatched = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'DONE'),
    );
    expect(doneWithMatched.onPressed, isNotNull);

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();

    expect(find.text('Review your matches'), findsOneWidget);
    expect(find.text('Mega Lucario ex'), findsWidgets);
    expect(find.byKey(const Key('scan-review-item-1')), findsOneWidget);
    expect(find.byKey(const Key('scan-review-item-4')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('scan-review-quantity-1')),
      '2',
    );
    await tester.tap(find.byKey(const Key('scan-review-item-4')));
    await tester.pumpAndSettle();
    expect(find.text('Charizard ex'), findsWidgets);
    expect(find.text('Failed'), findsNothing);
    expect(find.text('No Match Found'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('scan-review-quantity-4')),
      '3',
    );

    expect(find.text('ADD ALL CARDS'), findsOneWidget);

    await tester.tap(find.text('ADD ALL CARDS'));
    await tester.pumpAndSettle();

    expect(find.text('Added 2 cards to Portfolio'), findsOneWidget);
    expect(find.text('Mega Lucario ex'), findsWidgets);
    expect(find.text('Charizard ex'), findsWidgets);
    expect(repository.confirmedItems.map((item) => item.quantity), [2, 3]);
  });

  testWidgets('Scan camera chrome can exit and open manual Search', (
    tester,
  ) async {
    await _pumpScanTestApp(tester);
    await tester.tap(find.byTooltip('Close Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);

    await _pumpScanTestApp(tester);
    await tester.tap(find.byTooltip('Search Cards'));
    await tester.pumpAndSettle();
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets(
    'Scan asks before discarding an unmatched portfolio result because scan results are not auto-saved',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(
            const ScanResolution.matched(
              scanId: 'scan-unsaved',
              cardRef: 'card-unsaved',
              matchName: 'Unsaved card',
              candidates: ['Unsaved card'],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);

      await tester.tap(find.byTooltip('Close Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Exit scan result?'), findsOneWidget);
      expect(
        find.text('Your scanned card has not been collected yet.'),
        findsOneWidget,
      );

      await tester.tap(find.text('NO, STAY HERE'));
      await tester.pumpAndSettle();
      expect(find.text('Exit scan result?'), findsNothing);

      await tester.tap(find.byTooltip('Close Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Exit scan result?'), findsOneWidget);
      await tester.tap(find.text('EXIT'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling the image picker leaves no failed or unsaved scan result',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(const ScanResolution.cancelled()),
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();

      expect(find.text('Failed'), findsNothing);
      await tester.tap(find.byTooltip('Close Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Exit scan result?'), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
    },
  );
}

Future<void> _completeFigmaScan(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 1530));
}

Future<void> _pumpScanTestApp(
  WidgetTester tester, {
  ScanResultSource? scanResultSource,
  ScanReviewRepository? scanReviewRepository,
  ScanCameraFactory scanCameraFactory = const _DisabledScanCameraFactory(),
  bool tickerEnabled = true,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._searchOverrides(),
        homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        scanReviewRepositoryProvider.overrideWithValue(
          scanReviewRepository ?? _FakeScanReviewRepository(),
        ),
        scanResultSourceProvider.overrideWithValue(
          scanResultSource ?? _defaultTestScanResultSource(),
        ),
        scanCameraFactoryProvider.overrideWithValue(scanCameraFactory),
      ],
      child: TickerMode(
        enabled: tickerEnabled,
        child: const _ScanTestAppWithRoutes(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeScanReviewRepository implements ScanReviewRepository {
  _FakeScanReviewRepository({this.failure});

  final Exception? failure;
  final List<String> confirmedScanIds = [];
  final List<ScanCollectionItemInput> confirmedItems = [];

  @override
  Future<ScanReviewTarget> loadTarget({String? preferredFolderId}) async {
    return const ScanReviewTarget(
      folderId: 'main',
      folderName: 'Main',
      folders: [
        ScanReviewFolder(id: 'main', name: 'Main'),
        ScanReviewFolder(id: 'trade', name: 'Trade'),
      ],
    );
  }

  @override
  Future<Map<String, ScanReviewCard>> loadCards(List<String> cardRefs) async {
    return {
      for (final cardRef in cardRefs.toSet())
        cardRef: ScanReviewCard(
          cardRef: cardRef,
          name: switch (cardRef) {
            'card-charizard' => 'Charizard ex',
            'card-lucario' => 'Lucario ex',
            'card-riolu' => 'Riolu Promo',
            'card-charmander' => 'Charmander Promo',
            'card-charmeleon' => 'Charmeleon',
            _ => 'Mega Lucario ex',
          },
          setName: 'Test Set',
          cardNumber: '001',
          game: 'Pokemon',
          imageUrl: null,
          language: 'English',
          finish: 'Holofoil',
          prices: const [
            ScanReviewPrice(
              grader: 'Raw',
              grade: null,
              condition: 'Near Mint',
              price: 25,
            ),
            ScanReviewPrice(
              grader: 'PSA',
              grade: 10,
              condition: null,
              price: 100,
            ),
          ],
        ),
    };
  }

  @override
  Future<ScanConfirmationDto> addToPortfolio({
    required String scanId,
    required ScanCollectionItemInput item,
  }) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    confirmedScanIds.add(scanId);
    confirmedItems.add(item);
    return ScanConfirmationDto(
      scanId: scanId,
      collectionItemId: 'item-$scanId',
      cardRef: item.cardRef,
      folderId: item.folderId,
    );
  }
}

ScanResultSource _defaultTestScanResultSource() {
  return _TestScanResultSource(
    photoResult: Future.value(
      const ScanResolution.matched(
        scanId: 'scan-mega',
        cardRef: 'card-mega',
        matchName: 'Mega Lucario ex',
        candidates: ['Mega Lucario ex', 'Lucario ex', 'Riolu Promo'],
        candidateCardRefs: ['card-mega', 'card-lucario', 'card-riolu'],
      ),
    ),
    subsequentPhotoResults: [
      Future.value(const ScanResolution.failed()),
      Future.value(
        const ScanResolution.matched(
          scanId: 'scan-charizard',
          cardRef: 'card-charizard',
          matchName: 'Charizard ex',
          candidates: ['Charizard ex', 'Charmander Promo', 'Charmeleon'],
          candidateCardRefs: [
            'card-charizard',
            'card-charmander',
            'card-charmeleon',
          ],
        ),
      ),
    ],
  );
}

class _TestScanResultSource implements ScanResultSource {
  _TestScanResultSource({
    required Future<ScanResolution> photoResult,
    List<Future<ScanResolution>> subsequentPhotoResults = const [],
    Future<ScanResolution>? libraryResult,
    List<Future<ScanResolution>>? libraryResults,
    Future<ScanResolution>? recognizeResult,
    Future<ScanResolution>? retryResult,
    this.frameDetection,
  }) : _photoResults = [photoResult, ...subsequentPhotoResults],
       _libraryResults =
           libraryResults ??
           [libraryResult ?? Future.value(const ScanResolution.noMatch())],
       _recognizeResult = recognizeResult ?? photoResult,
       _retryResult =
           retryResult ?? Future.value(const ScanResolution.failed());

  final List<Future<ScanResolution>> _photoResults;
  final List<Future<ScanResolution>> _libraryResults;
  final Future<ScanResolution> _recognizeResult;
  final Future<ScanResolution> _retryResult;
  final ScanFrameDetection? frameDetection;
  var detectFrameCount = 0;
  var _nextPhotoResult = 0;
  Uint8List? lastRetryBytes;
  String? lastRetryFileName;
  final recognizedImages = <ScanImage>[];

  @override
  Future<ScanFrameDetection?> detectFrame(ScanCameraFrame frame) async {
    detectFrameCount += 1;
    return frameDetection;
  }

  @override
  Future<List<Future<ScanResolution>>> library() async => _libraryResults;

  @override
  Future<ScanResolution> photo() {
    final resultIndex = _nextPhotoResult < _photoResults.length
        ? _nextPhotoResult
        : _photoResults.length - 1;
    _nextPhotoResult += 1;
    return _photoResults[resultIndex];
  }

  @override
  Future<ScanResolution> recognize(ScanImage image) {
    recognizedImages.add(image);
    return _recognizeResult;
  }

  @override
  Future<ScanResolution> retry({Uint8List? imageBytes, String? fileName}) {
    lastRetryBytes = imageBytes;
    lastRetryFileName = fileName;
    return _retryResult;
  }
}

class _DisabledScanCameraFactory implements ScanCameraFactory {
  const _DisabledScanCameraFactory();

  @override
  Future<ScanCameraSession?> open() async => null;
}

class _TestScanCameraFactory implements ScanCameraFactory {
  _TestScanCameraFactory(this.session);

  _TestScanCameraSession session;

  @override
  Future<ScanCameraSession?> open() async => session;
}

class _TestScanCameraSession implements ScanCameraSession {
  var _flashEnabled = false;
  var takePhotoCount = 0;
  var disposed = false;
  var startStreamCount = 0;
  var stopStreamCount = 0;
  void Function(ScanCameraFrame frame)? onFrame;

  @override
  bool get flashEnabled => _flashEnabled;

  @override
  Widget buildPreview() {
    return const ColoredBox(
      key: Key('test-live-camera-preview'),
      color: Colors.black,
    );
  }

  @override
  Future<ScanImage> takePhoto() async {
    takePhotoCount += 1;
    return ScanImage(
      bytes: Uint8List.fromList([9, 8, 7]),
      fileName: 'live-camera.jpg',
    );
  }

  @override
  Future<void> startImageStream(
    void Function(ScanCameraFrame frame) onFrame,
  ) async {
    startStreamCount += 1;
    this.onFrame = onFrame;
  }

  @override
  Future<void> stopImageStream() async {
    stopStreamCount += 1;
    onFrame = null;
  }

  void emitFrame() {
    onFrame?.call(
      ScanCameraFrame(
        width: 1280,
        height: 720,
        format: ScanFrameFormat.jpeg,
        planes: [
          ScanFramePlane(
            bytes: Uint8List.fromList([1]),
            bytesPerRow: 1,
            bytesPerPixel: 1,
          ),
        ],
      ),
    );
  }

  @override
  Future<bool> toggleFlash() async {
    _flashEnabled = !_flashEnabled;
    return _flashEnabled;
  }

  @override
  Future<void> dispose() async {
    _flashEnabled = false;
    disposed = true;
  }
}

const _stableFrameDetection = ScanFrameDetection(
  width: 1280,
  height: 720,
  corners: [
    ScanImagePoint(400, 100),
    ScanImagePoint(700, 100),
    ScanImagePoint(700, 520),
    ScanImagePoint(400, 520),
  ],
);

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}

class _ScanTestAppWithRoutes extends StatelessWidget {
  const _ScanTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      theme: buildKandoTheme(),
      routerConfig: GoRouter(
        initialLocation: '/scan',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => const CollectionPage(),
          ),
          GoRoute(
            path: '/scan',
            builder: (context, state) => const RepaintBoundary(
              key: Key('scan-page-test-boundary'),
              child: ScanPage(),
            ),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
    );
  }
}
