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
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';
import 'package:kando_app/features/scan/scan_review_repository.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';

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
        'goldens/rendered/figma_scan_scanning_328_10705_390x844.png',
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
      expect(find.byTooltip('Close Scan'), findsNothing);
      expect(find.byTooltip('Search Cards'), findsNothing);
      expect(find.text('ALIGN CARD HERE'), findsNothing);
      expect(find.byTooltip('Take Photo'), findsNothing);
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
        'goldens/rendered/figma_scan_recognizing_328_13609_390x844.png',
      ),
    );
  });

  testWidgets(
    'Figma scan reveal restores camera controls before returning a match',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.byKey(const Key('scan-figma-revealing-toast')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scan-figma-revealing-toast-glow')),
        findsOneWidget,
      );
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
        'goldens/rendered/figma_scan_revealing_328_13645_390x844.png',
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
      await tester.tap(find.byKey(const Key('scan-figma-revealing-dismiss')));
      await tester.pump();

      expect(find.byKey(const Key('scan-figma-revealing-toast')), findsNothing);
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

      expect(
        find.byKey(const Key('scan-figma-revealing-toast')),
        findsOneWidget,
      );
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

      expect(
        find.byKey(const Key('scan-figma-revealing-toast')),
        findsOneWidget,
      );
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
      expect(find.text('Review Your Matches'), findsOneWidget);
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
    await _pumpScanTestApp(
      tester,
      scanResultSource: _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        retryResult: Future.value(
          const ScanResolution.matched(
            scanId: 'scan-mega',
            cardRef: 'card-mega',
            matchName: 'Mega Lucario ex',
            candidates: ['Mega Lucario ex'],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.byTooltip('Tap to retry'));
    await tester.pump();

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
    await tester.tap(find.text('CANCEL'));
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
      expect(find.text('Review Your Matches'), findsNothing);
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
        221,
      );
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('Scanning'), findsNothing);
      expect(find.byTooltip('Take Photo'), findsNothing);
      expect(find.byTooltip('Choose from Library'), findsNothing);

      await _completeFigmaScan(tester);

      expect(
        find.byKey(const Key('scan-figma-complete-result')),
        findsOneWidget,
      );
      expect(find.byTooltip('Modify scan match'), findsOneWidget);

      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();

      expect(find.text('Adding to Main'), findsOneWidget);
      expect(find.text('Collection Item'), findsOneWidget);
      expect(find.text('Portfolio'), findsNothing);
      expect(find.text('Your Picture'), findsOneWidget);
      expect(find.text('Our Match'), findsOneWidget);
      expect(find.text('Top matched results'), findsOneWidget);
      expect(find.text('Near Mint (NM)'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add this card'));
      await tester.pumpAndSettle();

      expect(find.text('Added to Portfolio'), findsWidgets);
      expect(find.text('Mega Lucario ex'), findsWidgets);
      expect(reviewRepository.confirmedScanIds, ['scan-mega']);
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
      await tester.drag(find.byType(ListView), const Offset(0, -500));
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

  testWidgets('Cancel discards an unfinished Figma scan', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await _pumpScanTestApp(tester);

    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump();
    await tester.tap(find.text('CANCEL'));
    await tester.pump();

    expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);
    expect(find.byTooltip('Take Photo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Matched'), findsNothing);
  });

  testWidgets('A pending Figma scan ignores reentrant capture requests', (
    tester,
  ) async {
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

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1530));
    expect(find.byKey(const Key('scan-figma-complete-result')), findsOneWidget);
    expect(find.text('No Match Found'), findsNothing);
  });

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

  testWidgets(
    'Scan completes each capture before accepting the next Figma scan',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      expect(find.byKey(const Key('scan-figma-scanning-line')), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsNothing);

      await _completeFigmaScan(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      expect(find.byTooltip('Take Photo'), findsNothing);

      await _completeFigmaScan(tester);

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pump();
      expect(find.byTooltip('Choose from Library'), findsNothing);

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

      expect(find.text('Review Your Matches'), findsOneWidget);
      expect(find.text('Mega Lucario ex'), findsWidgets);
      expect(find.text('Charizard ex'), findsWidgets);
      expect(find.text('Failed'), findsNothing);
      expect(find.text('No Match Found'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Add all cards'), findsOneWidget);

      await tester.tap(find.text('Add all cards'));
      await tester.pumpAndSettle();

      expect(find.text('Added 2 cards to Portfolio'), findsOneWidget);
      expect(find.text('Mega Lucario ex'), findsWidgets);
      expect(find.text('Charizard ex'), findsWidgets);
    },
  );

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

  @override
  Future<ScanReviewTarget> loadTarget({String? preferredFolderId}) async {
    return const ScanReviewTarget(folderId: 'main', folderName: 'Main');
  }

  @override
  Future<ScanConfirmationDto> addToPortfolio({
    required ScanReviewTarget target,
    required String scanId,
    required String cardRef,
  }) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    confirmedScanIds.add(scanId);
    return ScanConfirmationDto(
      scanId: scanId,
      collectionItemId: 'item-$scanId',
      cardRef: cardRef,
      folderId: target.folderId,
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
    Future<ScanResolution>? retryResult,
  }) : _photoResults = [photoResult, ...subsequentPhotoResults],
       _libraryResult =
           libraryResult ?? Future.value(const ScanResolution.noMatch()),
       _retryResult =
           retryResult ?? Future.value(const ScanResolution.failed());

  final List<Future<ScanResolution>> _photoResults;
  final Future<ScanResolution> _libraryResult;
  final Future<ScanResolution> _retryResult;
  var _nextPhotoResult = 0;

  @override
  Future<ScanResolution> library() => _libraryResult;

  @override
  Future<ScanResolution> photo() {
    final resultIndex = _nextPhotoResult < _photoResults.length
        ? _nextPhotoResult
        : _photoResults.length - 1;
    _nextPhotoResult += 1;
    return _photoResults[resultIndex];
  }

  @override
  Future<ScanResolution> retry() => _retryResult;
}

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
      routerConfig: GoRouter(
        initialLocation: '/scan',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => const CollectionPage(),
          ),
          GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
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
