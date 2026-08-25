import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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
import 'package:kando_app/features/scan/scan_permissions.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';
import 'package:kando_app/features/scan/scan_review_repository.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/features/subscription/scan_quota_controller.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/mock_home_repository.dart';
import '../support/mock_search_repository.dart';

const _transparentPngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

const _exhaustedQuota = ScanQuotaDto(
  access: ScanQuotaAccess.free,
  limit: 10,
  reserved: 0,
  consumed: 10,
  remaining: 0,
  unlimited: false,
);

const _availableQuota = ScanQuotaDto(
  access: ScanQuotaAccess.free,
  limit: 10,
  reserved: 0,
  consumed: 0,
  remaining: 10,
  unlimited: false,
);

const _unlimitedQuota = ScanQuotaDto(
  access: ScanQuotaAccess.premium,
  limit: 10,
  reserved: 0,
  consumed: 2,
  remaining: 8,
  unlimited: true,
);

void main() {
  testWidgets(
    'free scanning shows the configured allowance because upgrade urgency depends on the remaining count',
    (tester) async {
      await _pumpScanTestApp(tester);

      expect(find.text('10 scans remaining'), findsOneWidget);
      expect(find.text('Tap to get unlimited scans'), findsOneWidget);
    },
  );

  testWidgets(
    'the quota prompt stays tappable so free users can open the paywall',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62);
      addTearDown(tester.view.reset);
      await _pumpScanTestApp(tester);

      final quotaPrompt = tester.getRect(
        find.byKey(const Key('scan-free-quota-pill')),
      );

      await tester.tapAt(quotaPrompt.center);
      await tester.pumpAndSettle();

      expect(find.text('Subscription'), findsOneWidget);
    },
  );

  testWidgets(
    'a completed free scan consumes one allowance so the displayed limit stays truthful',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();

      expect(find.text('9 scans remaining'), findsOneWidget);
    },
  );

  testWidgets(
    'the Free quota prompt stays visible through scanning and follows the settled server count',
    (tester) async {
      final pending = Completer<ScanResolution>();
      final quotaController = _TestScanQuotaController(_availableQuota);
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(photoResult: pending.future),
        scanQuotaController: quotaController,
      );

      expect(find.text('10 scans remaining'), findsOneWidget);
      expect(find.text('Tap to get unlimited scans'), findsOneWidget);

      await tester.tap(find.byTooltip('Take Photo'));
      quotaController.applyServerQuota(
        const ScanQuotaDto(
          access: ScanQuotaAccess.free,
          limit: 10,
          reserved: 1,
          consumed: 0,
          remaining: 9,
          unlimited: false,
        ),
      );
      await tester.pump();
      expect(find.text('9 scans remaining'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('9 scans remaining'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('9 scans remaining'), findsOneWidget);

      pending.complete(
        const ScanResolution.noMatch(
          quota: ScanQuotaDto(
            access: ScanQuotaAccess.free,
            limit: 10,
            reserved: 0,
            consumed: 1,
            remaining: 9,
            unlimited: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1530));

      expect(find.text('9 scans remaining'), findsOneWidget);
      expect(find.text('Tap to get unlimited scans'), findsOneWidget);
    },
  );

  testWidgets(
    'an exhausted free allowance opens the paywall without starting recognition',
    (tester) async {
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuota: _exhaustedQuota,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pumpAndSettle();

      expect(source.photoCallCount, 0);
      expect(find.text('Subscription'), findsOneWidget);
    },
  );

  testWidgets(
    'unlocking Premium after an exhausted Capture returns to Scan without starting the camera action',
    (tester) async {
      final subscription = _SynchronizingScanSubscriptionController(
        premiumState: AppPremiumState.free,
      );
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuota: _exhaustedQuota,
        subscriptionController: () => subscription,
        subscriptionResult: SubscriptionPaywallResult.premiumUnlocked,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('subscription-test-result')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-page-test-boundary')), findsOneWidget);
      expect(source.photoCallCount, 0);
      expect(subscription.synchronizeCount, 1);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'unlocking Premium after an exhausted Gallery returns to Scan without reopening the picker',
    (tester) async {
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuota: _exhaustedQuota,
        subscriptionResult: SubscriptionPaywallResult.premiumUnlocked,
      );

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('subscription-test-result')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-page-test-boundary')), findsOneWidget);
      expect(source.libraryCallCount, 0);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'Pro scanning stays unlimited and does not consume the free allowance',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        subscriptionController: _ProScanSubscriptionController.new,
      );

      expect(find.byKey(const Key('scan-free-quota-pill')), findsNothing);
      expect(find.text('Unlimited scans'), findsOneWidget);
      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();

      expect(find.byKey(const Key('scan-free-quota-pill')), findsNothing);
    },
  );

  testWidgets(
    'server Unlimited hides Free quota while local entitlement catches up',
    (tester) async {
      await _pumpScanTestApp(tester, scanQuota: _unlimitedQuota);

      expect(find.byKey(const Key('scan-free-quota-pill')), findsNothing);
    },
  );

  testWidgets(
    'Premium becoming Free refreshes the original quota so the Free prompt follows entitlement state',
    (tester) async {
      const restoredFreeQuota = ScanQuotaDto(
        access: ScanQuotaAccess.free,
        limit: 10,
        reserved: 0,
        consumed: 3,
        remaining: 7,
        unlimited: false,
      );
      final subscription = _MutableScanSubscriptionController();
      final quotaController = _TestScanQuotaController(
        _unlimitedQuota,
        refreshQuotas: const [_unlimitedQuota, restoredFreeQuota],
      );
      await _pumpScanTestApp(
        tester,
        scanQuotaController: quotaController,
        subscriptionController: () => subscription,
      );

      expect(find.byKey(const Key('scan-free-quota-pill')), findsNothing);
      subscription.setPremiumState(AppPremiumState.free);
      await tester.pump();
      await tester.pump();

      expect(find.text('7 scans remaining'), findsOneWidget);
      expect(find.text('Tap to get unlimited scans'), findsOneWidget);
    },
  );

  testWidgets(
    'stale local Free refreshes once before recognition can spend quota',
    (tester) async {
      final subscription = _StaleFreeScanSubscriptionController();
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        subscriptionController: () => subscription,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();

      expect(subscription.refreshCount, 1);
      expect(source.photoCallCount, 1);
    },
  );

  testWidgets(
    'unknown entitlement resolved as Premium starts scanning without a free paywall',
    (tester) async {
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuota: _exhaustedQuota,
        subscriptionController: () =>
            _ResolvingScanSubscriptionController(AppPremiumState.premium),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();

      expect(source.photoCallCount, 1);
      expect(find.text('Subscription'), findsNothing);
    },
  );

  testWidgets(
    'unknown entitlement resolved as Free opens the paywall before recognition',
    (tester) async {
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuota: _exhaustedQuota,
        subscriptionController: () =>
            _ResolvingScanSubscriptionController(AppPremiumState.free),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pumpAndSettle();

      expect(source.photoCallCount, 0);
      expect(find.text('Subscription'), findsOneWidget);
    },
  );

  testWidgets(
    'unknown entitlement refresh failure neither scans nor shows a free paywall',
    (tester) async {
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuota: _exhaustedQuota,
        subscriptionController: () =>
            _ResolvingScanSubscriptionController(AppPremiumState.unknown),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pumpAndSettle();

      expect(source.photoCallCount, 0);
      expect(find.text('Subscription'), findsNothing);
      expect(
        find.text('Unable to verify Premium access. Please try again.'),
        findsOneWidget,
      );
      await tester.pump(kandoTopToastDuration);
    },
  );

  testWidgets('Scan requests camera access before opening the camera', (
    tester,
  ) async {
    final permissions = _TestScanPermissionGateway(
      camera: ScanPermissionResult.denied,
    );
    final cameraFactory = _TestScanCameraFactory(_TestScanCameraSession());

    await _pumpScanTestApp(
      tester,
      scanCameraFactory: cameraFactory,
      permissions: permissions,
    );

    expect(permissions.cameraRequests, 1);
    expect(cameraFactory.openCount, 0);
    expect(find.byKey(const Key('scan-live-camera-preview')), findsNothing);
    expect(find.byKey(const Key('scan-figma-camera-background')), findsNothing);
  });

  testWidgets('Gallery access is requested only when import is tapped', (
    tester,
  ) async {
    final permissions = _TestScanPermissionGateway(
      gallery: ScanPermissionResult.denied,
    );
    final source = _TestScanResultSource(
      photoResult: Future.value(const ScanResolution.failed()),
    );
    await _pumpScanTestApp(
      tester,
      scanResultSource: source,
      permissions: permissions,
    );

    expect(permissions.galleryRequests, 0);
    await tester.tap(find.byTooltip('Choose from Library'));
    await tester.pump();

    expect(permissions.galleryRequests, 1);
    expect(source.libraryCallCount, 0);
  });

  testWidgets(
    'Android uses its platform dialog when the OS can no longer show a permission request',
    (tester) async {
      final permissions = _TestScanPermissionGateway(
        camera: ScanPermissionResult.permanentlyDenied,
      );

      await _pumpScanTestApp(tester, permissions: permissions);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      final permissionTheme = tester.widget<Theme>(
        find.byKey(const Key('scan-permission-material-theme')),
      );
      expect(permissionTheme.data.brightness, Brightness.light);
      expect(
        permissionTheme.data.colorScheme.primary,
        isNot(buildKandoTheme().colorScheme.primary),
      );
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(permissions.settingsRequests, 1);
    },
  );

  testWidgets(
    'iOS uses its platform dialog when the OS can no longer show a permission request',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final permissions = _TestScanPermissionGateway(
          camera: ScanPermissionResult.permanentlyDenied,
        );

        await _pumpScanTestApp(tester, permissions: permissions);
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoAlertDialog), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        final permissionTheme = tester.widget<CupertinoTheme>(
          find.byKey(const Key('scan-permission-cupertino-theme')),
        );
        expect(permissionTheme.data.brightness, Brightness.light);
        expect(permissionTheme.data.primaryColor, CupertinoColors.systemBlue);
        await tester.tap(find.text('Open Settings'));
        await tester.pumpAndSettle();
        expect(permissions.settingsRequests, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test('Figma scan SVG icons use Flutter-compatible fill colors', () async {
    const iconAssets = [
      'assets/scan/close.svg',
      'assets/scan/flash.svg',
      'assets/scan/search.svg',
      'assets/scan/align.svg',
      'assets/scan/gallery.svg',
      'assets/scan/done.svg',
      'assets/scan/pro_badge.svg',
    ];

    for (final asset in iconAssets) {
      final svg = await rootBundle.loadString(asset);
      expect(svg, isNot(contains('var(')), reason: asset);
    }
  });

  testWidgets('Scan without a live preview renders no fallback background', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await _pumpScanTestApp(tester);

    expect(find.byKey(const Key('scan-camera-idle-background')), findsNothing);
    expect(
      find.byKey(const Key('scan-camera-revealing-background')),
      findsNothing,
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'Scan animates capture feedback before freezing the live frame because taking a photo must be perceptible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final camera = _TestScanCameraSession();
      final croppedBytes = Uint8List.fromList(_transparentPngBytes);
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        recognizeResult: Future.value(
          ScanResolution.matched(
            scanId: 'live-scan',
            cardRef: 'live-card',
            matchName: 'Live camera card',
            candidates: ['Live camera card'],
            candidateCardRefs: ['live-card'],
            displayImageBytes: croppedBytes,
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
      expect(camera.takePhotoCount, 0);
      expect(find.byKey(const Key('scan-figma-scanning-line')), findsOneWidget);
      final scanningLine = find.byKey(
        const Key('scan-figma-scanning-line-canvas'),
      );
      expect(tester.getSize(scanningLine), const Size(280, 4));
      final start = tester.getTopLeft(scanningLine).dy;
      await tester.pump(const Duration(milliseconds: 250));
      expect(camera.takePhotoCount, 0);
      expect(tester.getTopLeft(scanningLine).dy, greaterThan(start));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 1));
      expect(camera.takePhotoCount, 1);
      expect(source.recognizedImages.single.fileName, 'live-camera.jpg');
      expect(
        source.recognizedImages.single.bytes,
        Uint8List.fromList(_transparentPngBytes),
      );
      final pendingItem = find.byKey(const Key('scan-active-item-1'));
      expect(
        find.descendant(of: pendingItem, matching: find.byType(Image)),
        findsOneWidget,
      );
      final pendingImage = tester.widget<Image>(
        find.descendant(of: pendingItem, matching: find.byType(Image)),
      );
      expect((pendingImage.image as MemoryImage).bytes, same(croppedBytes));
      expect(
        find.byKey(const Key('scan-recognition-progress')),
        findsOneWidget,
      );
      final crop = source.recognizedImages.single.recognitionCrop!;
      expect(crop.left, closeTo(55 / 390, 0.0001));
      expect(crop.top, closeTo(213 / 844, 0.0001));
      expect(crop.width, closeTo(280 / 390, 0.0001));
      expect(crop.height, closeTo(400 / 844, 0.0001));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(camera.disposed, isTrue);
      expect(camera.flashEnabled, isFalse);
    },
  );

  testWidgets(
    'Camera recognition uses the yellow viewfinder because the captured image must match what the user framed',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        recognizeResult: Future.value(const ScanResolution.noMatch()),
      );
      final camera = _TestScanCameraSession();
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanCameraFactory: _TestScanCameraFactory(camera),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 501));

      final viewfinder = tester.getRect(
        find.byKey(const Key('scan-figma-viewfinder')),
      );
      final crop = source.recognizedImages.single.recognitionCrop!;
      expect(crop.left, closeTo(viewfinder.left / 360, 0.0001));
      expect(crop.top, closeTo(viewfinder.top / 800, 0.0001));
      expect(crop.left + crop.width, closeTo(viewfinder.right / 360, 0.0001));
      expect(crop.top + crop.height, closeTo(viewfinder.bottom / 800, 0.0001));
    },
  );

  testWidgets(
    'iPhone 8 keeps one adaptive viewfinder clear of the top and bottom controls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 667);
      tester.view.padding = const FakeViewPadding(top: 20);
      addTearDown(tester.view.reset);
      final pending = Completer<ScanResolution>();
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        recognizeResult: pending.future,
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanCameraFactory: _TestScanCameraFactory(_TestScanCameraSession()),
      );

      final viewfinder = tester.getRect(
        find.byKey(const Key('scan-figma-viewfinder')),
      );
      final quota = tester.getRect(
        find.byKey(const Key('scan-free-quota-pill')),
      );
      final shutter = tester.getRect(find.byTooltip('Take Photo'));

      expect(viewfinder.top, closeTo(168, 0.01));
      expect(viewfinder.width, closeTo(261.1, 0.01));
      expect(viewfinder.height, closeTo(373, 0.01));
      expect(viewfinder.width / viewfinder.height, closeTo(0.7, 0.0001));
      expect(viewfinder.top, greaterThanOrEqualTo(quota.bottom + 16));
      expect(viewfinder.bottom, lessThanOrEqualTo(shutter.top - 16));

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.getRect(find.byKey(const Key('scan-figma-scanning-line'))),
        viewfinder,
      );

      await tester.pump(const Duration(milliseconds: 750));
      final crop = source.recognizedImages.single.recognitionCrop!;
      expect(crop.left, closeTo(viewfinder.left / 375, 0.0001));
      expect(crop.top, closeTo(viewfinder.top / 667, 0.0001));
      expect(crop.width, closeTo(viewfinder.width / 375, 0.0001));
      expect(crop.height, closeTo(viewfinder.height / 667, 0.0001));
      expect(
        tester.getRect(find.byKey(const Key('scan-figma-overlay-viewfinder'))),
        viewfinder,
      );

      pending.complete(const ScanResolution.noMatch());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'compact Android keeps the adaptive viewfinder inside both safe areas',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await _pumpScanTestApp(tester);

      final viewfinder = tester.getRect(
        find.byKey(const Key('scan-figma-viewfinder')),
      );
      final quota = tester.getRect(
        find.byKey(const Key('scan-free-quota-pill')),
      );
      final shutter = tester.getRect(find.byTooltip('Take Photo'));

      expect(viewfinder.left, closeTo(68.7, 0.01));
      expect(viewfinder.top, closeTo(172, 0.01));
      expect(viewfinder.width, closeTo(222.6, 0.01));
      expect(viewfinder.height, closeTo(318, 0.01));
      expect(viewfinder.top, greaterThanOrEqualTo(quota.bottom + 16));
      expect(viewfinder.bottom, lessThanOrEqualTo(shutter.top - 16));
    },
  );

  testWidgets(
    'capture uses the latest adaptive geometry when the viewport changes during feedback',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        recognizeResult: Future.value(const ScanResolution.noMatch()),
      );
      final camera = _TestScanCameraSession();
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanCameraFactory: _TestScanCameraFactory(camera),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(milliseconds: 250));
      tester.view.physicalSize = const Size(375, 667);
      tester.view.padding = const FakeViewPadding(top: 20);
      await tester.pump(const Duration(milliseconds: 501));

      expect(camera.takePhotoCount, 1);
      expect(source.recognizedImages, hasLength(1));
      final viewfinder = tester.getRect(
        find.byKey(const Key('scan-figma-viewfinder')),
      );
      final crop = source.recognizedImages.single.recognitionCrop!;
      expect(crop.left, closeTo(viewfinder.left / 375, 0.0001));
      expect(crop.top, closeTo(viewfinder.top / 667, 0.0001));
      expect(crop.width, closeTo(viewfinder.width / 375, 0.0001));
      expect(crop.height, closeTo(viewfinder.height / 667, 0.0001));
    },
  );

  testWidgets(
    'Opening the camera does not recognize anything until the shutter is pressed',
    (tester) async {
      final camera = _TestScanCameraSession();
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        recognizeResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanCameraFactory: _TestScanCameraFactory(camera),
      );

      await tester.pump(const Duration(seconds: 5));

      expect(camera.takePhotoCount, 0);
      expect(source.recognizedImages, isEmpty);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();

      expect(camera.takePhotoCount, 0);
      await tester.pump(const Duration(milliseconds: 501));
      expect(camera.takePhotoCount, 1);
      expect(source.recognizedImages, hasLength(1));
    },
  );
  testWidgets(
    'Scan pauses in background and resumes the same preview without a black frame',
    (tester) async {
      final first = _TestScanCameraSession();
      final factory = _TestScanCameraFactory(first);
      await _pumpScanTestApp(tester, scanCameraFactory: factory);
      await tester.tap(find.byTooltip('Turn flash on'));
      await tester.pump();
      expect(first.flashEnabled, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(first.pausePreviewCount, 1);
      expect(first.disposed, isFalse);
      expect(first.flashEnabled, isFalse);
      expect(find.byKey(const Key('scan-live-camera-preview')), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(first.resumePreviewCount, 1);
      expect(factory.openCount, 1);
      expect(find.byKey(const Key('scan-live-camera-preview')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(first.disposed, isTrue);
    },
  );

  testWidgets(
    'Scan keeps the opening camera across transient inactivity because permission and gallery sheets must not reveal a fallback image',
    (tester) async {
      final first = _TestScanCameraSession();
      final second = _TestScanCameraSession();
      final factory = _PermissionDelayedScanCameraFactory(second);
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanCameraFactory: factory,
      );

      expect(
        find.byKey(const Key('scan-camera-opening-background')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('scan-figma-camera-background')),
        findsNothing,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      expect(source.photoCallCount, 0);

      factory.firstOpen.complete(first);
      await tester.pump();
      await tester.pump();

      expect(first.disposed, isFalse);
      expect(factory.openCount, 1);
      expect(find.byKey(const Key('scan-live-camera-preview')), findsOneWidget);
      expect(find.byKey(const Key('test-live-camera-preview')), findsOneWidget);
      expect(second.disposed, isFalse);
    },
  );

  testWidgets(
    'Gallery return warms a new camera behind a stable placeholder because importing must not flash the resumed preview',
    (tester) async {
      final first = _TestScanCameraSession();
      final second = _TestScanCameraSession();
      final factory = _TestScanCameraFactory(first);
      final galleryGate = Completer<void>();
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        libraryGate: galleryGate.future,
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanCameraFactory: factory,
      );

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pump();

      expect(first.disposed, isTrue);
      expect(
        find.byKey(const Key('scan-camera-opening-background')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('scan-figma-camera-background')),
        findsNothing,
      );
      expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);

      factory.session = second;
      galleryGate.complete();
      await tester.pump();
      await tester.pump();
      expect(factory.openCount, 2);
      expect(find.byKey(const Key('scan-live-camera-preview')), findsNothing);
      expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);

      await tester.pump(const Duration(milliseconds: 499));
      expect(find.byKey(const Key('scan-live-camera-preview')), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const Key('scan-live-camera-preview')), findsOneWidget);
    },
  );

  testWidgets(
    'Recognition mask matches the visible viewfinder on narrow screens because detected cards must stay inside the targeting frame',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);

      await _pumpScanTestApp(tester);
      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(seconds: 1));

      final visible = tester.getRect(
        find.byKey(const Key('scan-figma-viewfinder')),
      );
      final mask = tester.getRect(
        find.byKey(const Key('scan-figma-overlay-viewfinder')),
      );
      expect(mask, visible);
    },
  );

  testWidgets('Figma scan pre-scan renders at the 390x844 baseline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: ProviderScope(
          overrides: _scanGoldenOverrides(),
          child: const RepaintBoundary(
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
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: ProviderScope(
          overrides: _scanGoldenOverrides(),
          child: const RepaintBoundary(
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

  testWidgets(
    'Scan controls stay mounted while recognition advances to reveal',
    (tester) async {
      final pending = Completer<ScanResolution>();
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(photoResult: pending.future),
      );

      final initialTopBar = tester.renderObject(
        find.byKey(const Key('scan-figma-top-bar')),
      );
      final initialDoneAction = tester.renderObject(
        find.byKey(const Key('scan-done-action')),
      );
      final initialGalleryRect = tester.getRect(
        find.byTooltip('Choose from Library'),
      );
      final initialDoneRect = tester.getRect(
        find.byKey(const Key('scan-done-action')),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(seconds: 1));

      expect(
        tester.renderObject(find.byKey(const Key('scan-figma-top-bar'))),
        same(initialTopBar),
      );
      expect(
        tester.renderObject(find.byKey(const Key('scan-done-action'))),
        same(initialDoneAction),
      );
      expect(
        tester.getRect(find.byTooltip('Choose from Library')),
        initialGalleryRect,
      );
      expect(
        tester.getRect(find.byKey(const Key('scan-done-action'))),
        initialDoneRect,
      );

      await tester.pump(const Duration(seconds: 1));

      expect(
        tester.renderObject(find.byKey(const Key('scan-figma-top-bar'))),
        same(initialTopBar),
        reason: 'Reveal must not remount and replay the top controls.',
      );
      expect(
        tester.renderObject(find.byKey(const Key('scan-done-action'))),
        same(initialDoneAction),
        reason: 'Reveal must not remount and replay the bottom controls.',
      );
      expect(
        tester.getRect(find.byTooltip('Choose from Library')),
        initialGalleryRect,
        reason: 'Reveal must not move the Gallery action.',
      );
      expect(
        tester.getRect(find.byKey(const Key('scan-done-action'))),
        initialDoneRect,
        reason: 'Reveal must not move the Done action.',
      );

      pending.complete(const ScanResolution.failed());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1530));
      await tester.pump();

      expect(
        tester.getRect(find.byTooltip('Choose from Library')),
        initialGalleryRect,
        reason: 'Recognition completion must not move the Gallery action.',
      );
      expect(
        tester.getRect(find.byKey(const Key('scan-done-action'))),
        initialDoneRect,
        reason: 'Recognition completion must not move the Done action.',
      );
    },
  );

  testWidgets('Figma recognition renders at the 390x844 baseline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: ProviderScope(
          overrides: _scanGoldenOverrides(),
          child: const RepaintBoundary(
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
      expect(find.byKey(const Key('scan-delete-item-1')), findsOneWidget);
      expect(find.text('ALIGN CARD HERE'), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);
      expect(find.text('Matched'), findsNothing);
      expect(
        tester.widget<InkWell>(find.byKey(const Key('scan-done-action'))).onTap,
        isNull,
      );
    },
  );

  testWidgets(
    'Scanning progress paints inside its bounds so no edge is clipped',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump(const Duration(seconds: 2));

      final progress = tester.widget<CircularProgressIndicator>(
        find.byKey(const Key('scan-recognition-progress')),
      );
      expect(progress.strokeAlign, CircularProgressIndicator.strokeAlignInside);
    },
  );

  testWidgets('Figma scan reveal renders at the 390x844 baseline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: ProviderScope(
          overrides: _scanGoldenOverrides(),
          child: const RepaintBoundary(
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

    expect(tester.getTopLeft(find.byTooltip('Choose from Library')).dx, 28);
    expect(tester.getTopLeft(find.byTooltip('Choose from Library')).dy, 750);

    await expectLater(
      find.byKey(const Key('scan-revealing-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_scan_revealing_continuous_390x844.png',
      ),
    );
  });

  testWidgets('Deleting revealing scan feedback discards its pending result', (
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
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byKey(const Key('scan-delete-item-1')));
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
    expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
  });

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

      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
    },
  );

  testWidgets(
    'A matched card uses the real-time result rail, enables Done, and keeps its price in review',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);

      await tester.pump();
      expect(find.byKey(const Key('scan-figma-result-rail')), findsOneWidget);
      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.text(r'$25.00'), findsWidgets);
      expect(find.text(r'Total: $25.00'), findsOneWidget);

      ProviderScope.containerOf(tester.element(find.byType(ScanPage)))
          .read(selectedCurrencyProvider.notifier)
          .select(AppCurrency.eur.withUsdRate(0.91));
      await tester.pump();

      expect(find.text('€22.75'), findsOneWidget);
      expect(find.text('Total: €22.75'), findsOneWidget);
      expect(
        tester
            .widget<Container>(
              find.byKey(const Key('scan-figma-done-background')),
            )
            .decoration,
        isA<BoxDecoration>().having(
          (decoration) => decoration.color,
          'highlight color',
          const Color(0xFFF0FE6F),
        ),
      );

      final galleryButton = tester.getRect(
        find.byTooltip('Choose from Library'),
      );
      final doneButton = tester.getRect(
        find.byKey(const Key('scan-figma-done-background')),
      );
      expect(doneButton.size, galleryButton.size);
      expect(doneButton.top, galleryButton.top);

      await tester.tap(find.byKey(const Key('scan-figma-done-background')));
      await tester.pumpAndSettle();
      expect(find.text('Review your matches'), findsOneWidget);
      expect(find.text('€22.75'), findsOneWidget);
    },
  );

  testWidgets(
    'Single matched card hides bulk actions because only one card can be saved',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review scan result'));
      await tester.pumpAndSettle();

      expect(find.text('Add this card'), findsOneWidget);
      expect(find.byKey(const Key('scan-review-delete-one')), findsOneWidget);
      expect(find.text('ADD ALL CARDS'), findsNothing);
      expect(find.text('DELETE ALL CARDS'), findsNothing);
    },
  );

  testWidgets(
    'Multiple matched cards keep bulk actions because the batch applies to more than one card',
    (tester) async {
      final source = _TestScanResultSource(
        photoResult: Future.value(
          const ScanResolution.matched(
            scanId: 'scan-one',
            cardRef: 'card-mega',
            matchName: 'Mega Lucario ex',
            candidates: ['Mega Lucario ex'],
          ),
        ),
        subsequentPhotoResults: [
          Future.value(
            const ScanResolution.matched(
              scanId: 'scan-two',
              cardRef: 'card-charizard',
              matchName: 'Charizard ex',
              candidates: ['Charizard ex'],
            ),
          ),
        ],
      );
      await _pumpScanTestApp(tester, scanResultSource: source);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();

      expect(find.text('ADD ALL CARDS'), findsOneWidget);
      expect(find.text('DELETE ALL CARDS'), findsOneWidget);
    },
  );

  testWidgets(
    'Each scan shows its complete market price because the total must equal the visible item prices',
    (tester) async {
      final source = _TestScanResultSource(
        photoResult: Future.value(
          const ScanResolution.matched(
            scanId: 'scan-one',
            cardRef: 'card-mega',
            matchName: 'Escape Artist',
            candidates: ['Escape Artist'],
          ),
        ),
        subsequentPhotoResults: [
          Future.value(
            const ScanResolution.matched(
              scanId: 'scan-two',
              cardRef: 'card-mega',
              matchName: 'Escape Artist',
              candidates: ['Escape Artist'],
            ),
          ),
        ],
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanReviewRepository: _FakeScanReviewRepository(rawPrice: 0.21),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.pump();

      expect(find.text(r'$0.21'), findsNWidgets(2));
      expect(find.text(r'Total: $0.42'), findsOneWidget);
      expect(find.byKey(const Key('scan-item-price-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-item-price-2')), findsOneWidget);
    },
  );

  testWidgets('Figma review renders at the 390x844 baseline', (tester) async {
    await (FontLoader('Fraunces')..addFont(
          rootBundle.load('assets/fonts/Baskerville-BaskervilleSemiBold.ttf'),
        ))
        .load();
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
    'Review collapses back to the same scan session because editing a match must not exit or discard prior scans',
    (tester) async {
      tester.view.padding = const FakeViewPadding(top: 44);
      addTearDown(tester.view.resetPadding);
      final source = _TestScanResultSource(
        photoResult: Future.value(
          const ScanResolution.matched(
            scanId: 'scan-one',
            cardRef: 'card-mega',
            matchName: 'Mega Lucario ex',
            candidates: ['Mega Lucario ex'],
          ),
        ),
        subsequentPhotoResults: [
          Future.value(
            const ScanResolution.matched(
              scanId: 'scan-two',
              cardRef: 'card-mega',
              matchName: 'Mega Lucario ex',
              candidates: ['Mega Lucario ex'],
            ),
          ),
        ],
      );
      await _pumpScanTestApp(tester, scanResultSource: source);
      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();

      final collapseArea = tester.getRect(
        find.byKey(const Key('scan-review-collapse-area')),
      );
      final safeTop = MediaQuery.paddingOf(
        tester.element(find.byType(ScanPage)),
      ).top;
      expect(collapseArea.height, safeTop + 24);

      await tester.tap(find.byKey(const Key('scan-review-collapse-area')));
      await tester.pumpAndSettle();

      expect(find.text('Review your matches'), findsNothing);
      expect(find.text('Exit scan result?'), findsNothing);
      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsOneWidget);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-active-item-2')), findsOneWidget);
    },
  );

  testWidgets(
    'Review close only collapses editing because Exit scan result belongs to the scan-page close action',
    (tester) async {
      await _pumpScanTestApp(tester);
      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back to Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Exit scan result?'), findsNothing);

      await tester.tap(find.byTooltip('Close Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Exit scan result?'), findsOneWidget);
    },
  );

  testWidgets(
    'A failed single scan uses the same result rail as real-time scanning',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(const ScanResolution.failed()),
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);

      expect(find.byKey(const Key('scan-figma-result-rail')), findsOneWidget);
      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Tap to retry'), findsOneWidget);
      expect(find.byKey(const Key('scan-delete-item-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-delete-item-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
    },
  );

  testWidgets('Figma scan failure retries through the existing scan flow', (
    tester,
  ) async {
    final source = _TestScanResultSource(
      photoResult: Future.value(
        ScanResolution.failed(
          imageBytes: Uint8List.fromList(_transparentPngBytes),
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
    await tester.tap(find.byTooltip('Retry scan'));
    await tester.pump();

    expect(source.lastRetryBytes, Uint8List.fromList(_transparentPngBytes));
    expect(source.lastRetryFileName, 'failed-card.jpg');
    expect(find.text('Scanning...'), findsOneWidget);
    expect(find.byKey(const Key('scan-recognition-progress')), findsOneWidget);

    await _completeFigmaScan(tester);
    expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
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
      await tester.tap(find.byTooltip('Review scan result'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add this card'));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('kando-centered-success-toast')),
        findsOneWidget,
      );
      expect(find.text(portfolioCardAddedToastText), findsOneWidget);
      expect(find.text('Review your matches'), findsOneWidget);

      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pumpAndSettle();
      expect(find.text('Review your matches'), findsNothing);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);

      expect(find.byKey(const Key('scan-figma-failure-toast')), findsNothing);
      expect(find.text('Failed'), findsOneWidget);
    },
  );

  testWidgets('Cancelling a Figma scan ignores its eventual recognition', (
    tester,
  ) async {
    final result = Completer<ScanResolution>();
    final analytics = _AnalyticsRecorder();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await _pumpScanTestApp(
      tester,
      scanResultSource: _TestScanResultSource(photoResult: result.future),
      analytics: analytics.client,
    );

    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan-delete-item-1')));
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
    await tester.tap(find.byTooltip('Close Scan'));
    await tester.pumpAndSettle();

    expect(analytics.count(AnalyticsEvent.cancelClick), 1);
    expect(analytics.count(AnalyticsEvent.deleteClick), 0);
    expect(analytics.count(AnalyticsEvent.scanResults), 1);
    expect(
      analytics.propertiesFor(AnalyticsEvent.scanResults).single,
      containsPair(AnalyticsProperty.scanResults, AnalyticsValue.scanFailed),
    );
  });

  testWidgets(
    'Figma scan pre-scan uses exported icons without Material glyph fallback',
    (tester) async {
      tester.view.padding = const FakeViewPadding(top: 37);
      addTearDown(tester.view.resetPadding);
      await _pumpScanTestApp(tester);

      expect(find.byKey(const Key('scan-figma-close-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-flash-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-search-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-align-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-gallery-icon')), findsOneWidget);
      expect(find.byKey(const Key('scan-figma-done-icon')), findsOneWidget);

      final topBand = tester.getRect(
        find.byKey(const Key('scan-figma-top-safe-band')),
      );
      final topControls = tester.getRect(
        find.byKey(const Key('scan-figma-top-controls')),
      );
      final topBar = tester.getRect(
        find.byKey(const Key('scan-figma-top-bar')),
      );
      final closeButton = tester.getRect(
        find.byKey(const Key('scan-figma-close-button')),
      );
      final flashButton = tester.getRect(
        find.byKey(const Key('scan-figma-flash-button')),
      );
      final searchButton = tester.getRect(
        find.byKey(const Key('scan-figma-search-button')),
      );
      final quotaPillFinder = find.byKey(const Key('scan-free-quota-pill'));
      final quotaPill = tester.getRect(quotaPillFinder);
      final quotaBadge = tester.getRect(
        find.byKey(const Key('scan-free-quota-pro-badge')),
      );
      final quotaCopy = tester.getRect(
        find.byKey(const Key('scan-free-quota-copy')),
      );
      final safeTop = MediaQuery.paddingOf(
        tester.element(find.byType(ScanPage)),
      ).top;
      expect(topBand.height, safeTop);
      expect(topControls.top, topBand.bottom + 10);
      expect(topBar.height, 32);
      expect(closeButton.size, const Size(30, 30));
      expect(flashButton.size, const Size(25, 25));
      expect(searchButton.size, const Size(30, 30));
      expect(closeButton.center.dy, topBar.center.dy);
      expect(flashButton.center.dy, topBar.center.dy);
      expect(searchButton.center.dy, topBar.center.dy);
      expect(quotaPill.height, 48);
      expect(quotaPill.width, 209);
      expect(quotaBadge.size, const Size(24, 24));
      expect(quotaBadge.left, quotaPill.left + 8);
      expect(quotaBadge.center.dy, quotaPill.center.dy);
      expect(quotaCopy.left, quotaBadge.right + 8);
      expect(quotaCopy.width, 161);
      expect(quotaCopy.height, 32);
      expect(quotaCopy.right, quotaPill.right - 8);
      final quotaDecoration =
          tester.widget<DecoratedBox>(quotaPillFinder).decoration
              as BoxDecoration;
      expect(quotaDecoration.color, const Color(0xFF222222));
      expect(quotaDecoration.borderRadius, BorderRadius.circular(12));
      expect(quotaDecoration.boxShadow, const [
        BoxShadow(
          color: Color(0x40000000),
          offset: Offset(0, 23.585),
          blurRadius: 23.585,
        ),
      ]);
      final quotaTitle = tester.widget<Text>(find.text('10 scans remaining'));
      final quotaSubtitle = tester.widget<Text>(
        find.text('Tap to get unlimited scans'),
      );
      for (final text in [quotaTitle, quotaSubtitle]) {
        expect(text.style?.color, const Color(0xFFE4E3D3));
        expect(text.style?.fontSize, 13);
        expect(text.style?.height, 16 / 13);
        expect(text.style?.letterSpacing, 0);
      }
      expect(
        find.descendant(
          of: quotaPillFinder,
          matching: find.byIcon(Icons.arrow_upward_rounded),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Figma scan pre-scan keeps its camera overlay and platform label font',
    (tester) async {
      await _pumpScanTestApp(tester);

      final overlay = find.byKey(const Key('scan-figma-camera-overlay'));
      expect(overlay, findsOneWidget);
      expect(tester.widget<ColoredBox>(overlay).color, const Color(0x1A0D0F08));
      expect(
        tester.widget<Text>(find.text('GALLERY')).style?.fontFamily,
        isNull,
      );
      expect(tester.widget<Text>(find.text('DONE')).style?.fontFamily, isNull);
    },
  );

  testWidgets(
    'Scan creates reviewable matches because scans are not saved automatically',
    (tester) async {
      final reviewRepository = _FakeScanReviewRepository();
      await _pumpScanTestApp(
        tester,
        scanReviewRepository: reviewRepository,
        scanCameraFactory: _TestScanCameraFactory(_TestScanCameraSession()),
      );

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
        tester.getTopLeft(find.byKey(const Key('scan-figma-viewfinder'))).dy,
      );
      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.text('Scanning'), findsNothing);
      expect(find.byTooltip('Take Photo'), findsOneWidget);
      expect(find.byTooltip('Choose from Library'), findsOneWidget);

      await _completeFigmaScan(tester);

      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.byTooltip('Review scan result'), findsOneWidget);

      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();

      expect(find.text('Adding to Main'), findsOneWidget);
      expect(find.text('Collection item'), findsOneWidget);
      final collectionTitleRect = tester.getRect(find.text('Collection item'));
      final folderTriggerRect = tester.getRect(
        find.byKey(const Key('scan-review-folder-1')),
      );
      expect(
        collectionTitleRect.right,
        lessThanOrEqualTo(folderTriggerRect.left),
      );
      expect(find.text('Portfolio'), findsNothing);
      expect(find.text('YOUR PICTURE'), findsOneWidget);
      expect(find.text('OUR MATCH'), findsOneWidget);
      expect(find.text('Top matched results:'), findsOneWidget);
      expect(find.text('Near Mint (NM)'), findsOneWidget);
      expect(find.byKey(const Key('scan-review-total')), findsOneWidget);
      expect(find.text(r'$25.00'), findsWidgets);

      await tester.drag(
        find.byKey(const Key('scan-review-list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-review-folder-1')));
      await tester.pumpAndSettle();
      expect(find.text('Add scanned cards to'), findsOneWidget);
      expect(
        find.byKey(const Key('scan-review-folder-sheet-handle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scan-review-folder-selected-indicator')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('scan-review-folder-option-trade')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add scanned cards to'), findsNothing);
      expect(find.text('Adding to Trade'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('scan-review-quantity-1')),
        '2',
      );
      await tester.pump();
      final gradedState = find.byKey(const Key('scan-review-state-graded-1'));
      await tester.ensureVisible(gradedState);
      await tester.pumpAndSettle();
      await tester.tap(gradedState);
      await tester.pumpAndSettle();
      final gradeField = find.byKey(const Key('scan-review-grade-1'));
      await tester.ensureVisible(gradeField);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('scan-review-choice-sheet-handle')),
        findsNothing,
      );
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
      await tester.pump();
      await tester.pump();

      expect(find.text(portfolioCardAddedToastText), findsOneWidget);
      expect(find.text('Review your matches'), findsOneWidget);

      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('scan-active-item-1')),
        findsNothing,
        reason: 'A confirmed scan must leave the pending results rail.',
      );
      expect(find.text('ADDED'), findsNothing);
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
    'Scan review only offers languages and finishes available for the matched card',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanReviewRepository: _FakeScanReviewRepository(
          availableLanguages: const ['English', 'Japanese'],
          availableFinishes: const ['Holofoil', 'Normal'],
        ),
        scanCameraFactory: _TestScanCameraFactory(_TestScanCameraSession()),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('scan-review-list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('scan-review-list')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();

      final languageField = find.byKey(const Key('scan-review-language-1'));
      await tester.ensureVisible(languageField);
      await tester.pumpAndSettle();
      await tester.tap(languageField);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('scan-review-choice-option-English')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scan-review-choice-option-Japanese')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scan-review-choice-option-Chinese')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('scan-review-choice-option-English')),
      );
      await tester.pumpAndSettle();

      final finishGroup = find.byKey(const Key('scan-review-finish-1'));
      expect(
        find.descendant(of: finishGroup, matching: find.text('Holofoil')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: finishGroup, matching: find.text('Normal')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: finishGroup, matching: find.text('Foil')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Review waits for editable data and keeps the captured image in its thumbnail',
    (tester) async {
      final target = Completer<ScanReviewTarget>();
      final repository = _DelayedScanReviewRepository(target.future);
      final croppedBytes = Uint8List.fromList(_transparentPngBytes);
      final source = _TestScanResultSource(
        photoResult: Future.value(
          ScanResolution.matched(
            scanId: 'scan-local-image',
            cardRef: 'card-mega',
            matchName: 'Mega Lucario ex',
            candidates: const ['Mega Lucario ex'],
            imageBytes: Uint8List.fromList(_transparentPngBytes),
            displayImageBytes: croppedBytes,
          ),
        ),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanReviewRepository: repository,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pump();

      expect(find.byKey(const Key('scan-review-loading')), findsOneWidget);
      expect(find.text('Review your matches'), findsNothing);
      tester
          .widget<InkWell>(find.byKey(const Key('scan-done-action')))
          .onTap!();
      await tester.pump();
      expect(repository.loadTargetCount, 1);

      target.complete(_FakeScanReviewRepository.target);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-review-loading')), findsNothing);
      expect(find.text('Review your matches'), findsOneWidget);
      final thumbnailImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('scan-review-item-1')),
          matching: find.byType(Image),
        ),
      );
      expect(thumbnailImage.image, isA<MemoryImage>());
      expect((thumbnailImage.image as MemoryImage).bytes, same(croppedBytes));
    },
  );

  testWidgets(
    'Review clears loading and keeps the scan when current card data is missing',
    (tester) async {
      final repository = _MissingCurrentScanReviewRepository();
      await _pumpScanTestApp(tester, scanReviewRepository: repository);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pump();
      await tester.pump();

      expect(repository.loadTargetCount, 1);
      expect(find.byKey(const Key('scan-review-loading')), findsNothing);
      expect(find.text('Review your matches'), findsNothing);
      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.byKey(const Key('kando-floating-toast')), findsNothing);

      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pump();
      await tester.pump();
      expect(repository.loadTargetCount, 2);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('kando-top-toast')),
          matching: find.byTooltip('Close'),
        ),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'Review treats an already confirmed scan as added because confirmation is idempotent',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanReviewRepository: _FakeScanReviewRepository(
          failure: const ScanApiException(
            'Scan is already confirmed.',
            code: 'CONFLICT',
          ),
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add this card'));
      await tester.pump();
      await tester.pump();

      expect(find.text(portfolioCardAddedToastText), findsOneWidget);
      expect(find.text('Review your matches'), findsOneWidget);

      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('scan-active-item-1')),
        findsNothing,
        reason: 'An idempotent confirmation is still a completed scan.',
      );
      expect(find.text('ADDED'), findsNothing);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Review form dismisses the keyboard when tapping outside fields',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('scan-review-quantity-1')),
        '2',
      );
      await tester.pump();

      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.text('Top matched results:'), warnIfMissed: false);
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  testWidgets('Review inline selection does not restore focus to Quantity', (
    tester,
  ) async {
    await _pumpScanTestApp(tester);

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.byTooltip('Review completed scan'));
    await tester.pumpAndSettle();

    final quantityFinder = find.byKey(const Key('scan-review-quantity-1'));
    final quantityTextField = find.descendant(
      of: quantityFinder,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(quantityTextField).autofocus, isFalse);

    await tester.enterText(quantityFinder, '2');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    final gradedFinder = find.byKey(const Key('scan-review-state-graded-1'));
    await tester.ensureVisible(gradedFinder);
    await tester.pumpAndSettle();
    await tester.tap(gradedFinder);
    await tester.pumpAndSettle();
    final gradeFinder = find.byKey(const Key('scan-review-grade-1'));
    await tester.ensureVisible(gradeFinder);
    await tester.tap(
      find.descendant(of: gradeFinder, matching: find.text('10')),
    );
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      find.byKey(const Key('scan-review-choice-sheet-handle')),
      findsNothing,
    );
    expect(find.byKey(const Key('scan-review-grade-1')), findsOneWidget);
  });

  testWidgets('Review card state exposes the matching grade or condition', (
    tester,
  ) async {
    await _pumpScanTestApp(tester);

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.byTooltip('Review completed scan'));
    await tester.pumpAndSettle();

    final gradedFinder = find.byKey(const Key('scan-review-state-graded-1'));
    await tester.ensureVisible(gradedFinder);
    await tester.pumpAndSettle();
    await tester.tap(gradedFinder);
    await tester.pumpAndSettle();

    expect(find.text('GRADE'), findsWidgets);
    final gradeGroup = find.byKey(const Key('scan-review-grade-1'));
    await tester.ensureVisible(gradeGroup);
    await tester.pumpAndSettle();
    final gradeNine = find.descendant(of: gradeGroup, matching: find.text('9'));
    await tester.tap(gradeNine);
    await tester.pumpAndSettle();
    final selectedGrade = tester.widget<OutlinedButton>(
      find.ancestor(of: gradeNine, matching: find.byType(OutlinedButton)).first,
    );
    expect(
      selectedGrade.style?.foregroundColor?.resolve(const {}),
      const Color(0xFFF0FE6F),
    );
    expect(
      find.byKey(const Key('scan-review-choice-sheet-handle')),
      findsNothing,
    );

    final rawState = find.byKey(const Key('scan-review-state-raw-1'));
    await tester.ensureVisible(rawState);
    await tester.pumpAndSettle();
    await tester.tap(rawState);
    await tester.pumpAndSettle();

    expect(find.text('CONDITION'), findsOneWidget);
    await tester.tap(find.text('Lightly Played (LP)'));
    await tester.pumpAndSettle();

    expect(find.text('Lightly Played (LP)'), findsOneWidget);
    expect(find.text('Lightly Played (LP)'), findsOneWidget);
  });

  testWidgets(
    'Scan review keeps its target and does not offer a portfolio choice',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();

      expect(find.text('Adding to Main'), findsOneWidget);
      expect(find.text('PORTFOLIO'), findsNothing);
      expect(find.byKey(const Key('scan-review-quantity-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-review-finish-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-review-state-raw-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-review-language-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-review-price-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-review-notes-1')), findsOneWidget);
    },
  );

  testWidgets(
    'Review Notes matches the reference and stays above the keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      await _pumpScanTestApp(tester);
      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Review completed scan'));
      await tester.pumpAndSettle();

      final notesFinder = find.byKey(const Key('scan-review-notes-1'));
      final notesLabelFinder = find.byKey(
        const Key('scan-review-notes-label-1'),
      );
      await tester.ensureVisible(notesFinder);
      await tester.pumpAndSettle();

      final notesTextFieldFinder = find.descendant(
        of: notesFinder,
        matching: find.byType(TextField),
      );
      final notesTextField = tester.widget<TextField>(notesTextFieldFinder);
      final notesLabel = tester.widget<Text>(notesLabelFinder);
      final notesBorder =
          notesTextField.decoration?.enabledBorder as OutlineInputBorder?;
      expect(notesLabel.style?.fontFamily, 'Fraunces');
      expect(notesLabel.style?.fontSize, 14);
      expect(notesTextField.decoration?.labelText, isNull);
      expect(notesTextField.decoration?.fillColor, const Color(0xFF10110C));
      expect(notesBorder?.borderSide.color, const Color(0xFF464835));
      expect(notesTextField.decoration?.counterText, '');
      expect(notesTextField.minLines, 5);
      expect(notesTextField.maxLines, 8);
      expect(
        tester.getBottomLeft(notesLabelFinder).dy,
        lessThan(tester.getTopLeft(notesFinder).dy),
      );

      await tester.tap(notesFinder);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.byKey(const Key('scan-review-add-one')), findsNothing);
      expect(tester.getBottomRight(notesFinder).dy, lessThanOrEqualTo(514));
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
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.byKey(const Key('kando-floating-toast')), findsNothing);
      expect(find.text('Added to Portfolio'), findsNothing);
      await tester.pump(kandoTopToastDuration);
      await tester.pump();
    },
  );

  testWidgets('Add this card shows loading while confirmation is pending', (
    tester,
  ) async {
    final repository = _BlockingScanReviewRepository();
    await _pumpScanTestApp(tester, scanReviewRepository: repository);

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.byTooltip('Review completed scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-review-add-one')));
    await tester.pump();

    expect(repository.confirmationCount, 1);
    expect(
      find.byKey(const Key('scan-review-add-one-loading')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scan-review-add-all-loading')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('scan-review-add-one')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('scan-review-add-all')), findsNothing);
    expect(find.text('Add this card'), findsOneWidget);

    repository.completeNextConfirmation();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('scan-review-add-one-loading')), findsNothing);
    expect(find.text(portfolioCardAddedToastText), findsOneWidget);
    await tester.pump(kandoCenteredSuccessToastDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('Add all cards shows loading until every card is confirmed', (
    tester,
  ) async {
    final repository = _BlockingScanReviewRepository();
    final source = _TestScanResultSource(
      photoResult: Future.value(
        const ScanResolution.matched(
          scanId: 'scan-one',
          cardRef: 'card-mega',
          matchName: 'Mega Lucario ex',
          candidates: ['Mega Lucario ex'],
          candidateCardRefs: ['card-mega'],
        ),
      ),
      subsequentPhotoResults: [
        Future.value(
          const ScanResolution.matched(
            scanId: 'scan-two',
            cardRef: 'card-charizard',
            matchName: 'Charizard ex',
            candidates: ['Charizard ex'],
            candidateCardRefs: ['card-charizard'],
          ),
        ),
      ],
    );
    await _pumpScanTestApp(
      tester,
      scanReviewRepository: repository,
      scanResultSource: source,
    );

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-review-add-all')));
    await tester.pump();

    expect(repository.confirmationCount, 1);
    expect(
      find.byKey(const Key('scan-review-add-all-loading')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scan-review-add-one-loading')), findsNothing);

    repository.completeNextConfirmation();
    await tester.pump();
    await tester.pump();
    expect(repository.confirmationCount, 2);
    expect(
      find.byKey(const Key('scan-review-add-all-loading')),
      findsOneWidget,
    );

    repository.completeNextConfirmation();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('scan-review-add-all-loading')), findsNothing);
    expect(find.text(portfolioCardsAddedToastText(2)), findsOneWidget);
    await tester.pump(kandoCenteredSuccessToastDuration);
    await tester.pumpAndSettle();
  });

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
      await tester.pump();
      await tester.pump();

      expect(find.text(portfolioCardAddedToastText), findsOneWidget);
      expect(find.text('Review your matches'), findsOneWidget);

      await tester.pump(kandoCenteredSuccessToastDuration);
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
    await tester.tap(find.byKey(const Key('scan-delete-item-1')));
    await tester.pump();

    expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);
    expect(find.byTooltip('Take Photo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Matched'), findsNothing);
  });

  testWidgets(
    'deleting Processing keeps its request alive so the final quota settles without restoring the card',
    (tester) async {
      final pending = Completer<ScanResolution>();
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(
            const ScanResolution.matched(
              scanId: 'kept-scan',
              cardRef: 'kept-card',
              matchName: 'Kept card',
              candidates: ['Kept card'],
            ),
          ),
          subsequentPhotoResults: [pending.future],
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      expect(
        tester.widget<InkWell>(find.byKey(const Key('scan-done-action'))).onTap,
        isNull,
      );
      await tester.tap(find.byKey(const Key('scan-delete-item-2')));
      await tester.pump();

      expect(
        tester.widget<InkWell>(find.byKey(const Key('scan-done-action'))).onTap,
        isNotNull,
        reason: 'Deleted Processing must leave the visible processing count.',
      );

      pending.complete(
        const ScanResolution.matched(
          scanId: 'deleted-scan',
          cardRef: 'deleted-card',
          matchName: 'Deleted card',
          candidates: ['Deleted card'],
          quota: ScanQuotaDto(
            access: ScanQuotaAccess.free,
            limit: 10,
            reserved: 0,
            consumed: 1,
            remaining: 9,
            unlimited: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-active-item-2')), findsNothing);
      expect(find.text('Deleted card'), findsNothing);
      expect(find.text('9 scans remaining'), findsOneWidget);
    },
  );

  testWidgets(
    'deleting an in-flight camera scan allows another capture while the old request settles',
    (tester) async {
      final first = Completer<ScanResolution>();
      final second = Completer<ScanResolution>();
      final third = Completer<ScanResolution>();
      final camera = _TestScanCameraSession();
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(const ScanResolution.failed()),
          recognizeResult: first.future,
          subsequentRecognizeResults: [second.future, third.future],
        ),
        scanCameraFactory: _TestScanCameraFactory(camera),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1));
      expect(camera.takePhotoCount, 1);

      await tester.tap(find.byKey(const Key('scan-delete-item-1')));
      await tester.pump();
      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        camera.takePhotoCount,
        2,
        reason: 'Deleting the Processing item must release its local gate.',
      );
      expect(find.byKey(const Key('scan-active-item-2')), findsOneWidget);

      first.complete(const ScanResolution.failed());
      await tester.pump();
      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        camera.takePhotoCount,
        2,
        reason: 'The deleted request must not unlock the newer capture.',
      );
      expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
      expect(find.byKey(const Key('scan-active-item-2')), findsOneWidget);
    },
  );

  testWidgets(
    'a deleted Processing failure refreshes returned quota and resumes an existing Waiting item',
    (tester) async {
      final pending = Completer<ScanResolution>();
      final bytes = Uint8List.fromList(_transparentPngBytes);
      final quotaController = _TestScanQuotaController(
        _availableQuota,
        refreshQuotas: const [
          _availableQuota,
          ScanQuotaDto(
            access: ScanQuotaAccess.free,
            limit: 10,
            reserved: 0,
            consumed: 9,
            remaining: 1,
            unlimited: false,
          ),
        ],
      );
      final source = _TestScanResultSource(
        photoResult: pending.future,
        libraryImages: [ScanImage(bytes: bytes, fileName: 'waiting.png')],
        libraryResults: [
          Future.value(
            ScanResolution.quotaExhausted(
              imageBytes: bytes,
              displayImageBytes: bytes,
              imageFileName: 'waiting.png',
              quota: _exhaustedQuota,
            ),
          ),
        ],
        retryResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuotaController: quotaController,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Subscription'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tap(find.byKey(const Key('scan-delete-item-1')));
      await tester.pump();

      pending.complete(const ScanResolution.failed());
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
      expect(source.lastRetryFileName, 'waiting.png');
    },
  );

  testWidgets(
    'a visible Processing failure refreshes returned quota and resumes the earliest Waiting item',
    (tester) async {
      final pending = Completer<ScanResolution>();
      final bytes = Uint8List.fromList(_transparentPngBytes);
      final quotaController = _TestScanQuotaController(
        _availableQuota,
        refreshQuotas: const [
          _availableQuota,
          ScanQuotaDto(
            access: ScanQuotaAccess.free,
            limit: 10,
            reserved: 0,
            consumed: 9,
            remaining: 1,
            unlimited: false,
          ),
        ],
      );
      final source = _TestScanResultSource(
        photoResult: pending.future,
        libraryImages: [ScanImage(bytes: bytes, fileName: 'waiting.png')],
        libraryResults: [
          Future.value(
            ScanResolution.quotaExhausted(
              imageBytes: bytes,
              displayImageBytes: bytes,
              imageFileName: 'waiting.png',
              quota: _exhaustedQuota,
            ),
          ),
        ],
        retryResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuotaController: quotaController,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Subscription'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();

      pending.complete(const ScanResolution.failed());
      await _completeFigmaScan(tester);

      expect(find.text('Failed'), findsOneWidget);
      expect(source.lastRetryFileName, 'waiting.png');
    },
  );

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
    'Capture refuses an eleventh item because Waiting and results share the ten-card queue limit',
    (tester) async {
      final pending = Completer<ScanResolution>();
      final source = _TestScanResultSource(photoResult: pending.future);
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        subscriptionController: _ProScanSubscriptionController.new,
      );

      for (var index = 0; index < 11; index += 1) {
        await tester.tap(find.byTooltip('Take Photo'));
        await tester.pump();
      }

      expect(source.photoCallCount, 10);
      expect(find.text('Scanned: 0/10'), findsOneWidget);
      expect(find.text('Scan queue is full'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'Done stays disabled while another scan is processing because review must use a settled queue',
    (tester) async {
      final pendingLibrary = Completer<ScanResolution>();
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
          libraryResults: [pendingLibrary.future],
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.tap(find.byTooltip('Choose from Library'));
      await _completeFigmaScan(tester);

      expect(find.byKey(const Key('scan-active-item-1')), findsOneWidget);
      expect(find.byKey(const Key('scan-active-item-2')), findsOneWidget);
      expect(
        tester.widget<InkWell>(find.byKey(const Key('scan-done-action'))).onTap,
        isNull,
      );
      final decoration =
          tester
                  .widget<Container>(
                    find.byKey(const Key('scan-figma-done-background')),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, isNot(const Color(0xFFF0FE6F)));

      pendingLibrary.complete(const ScanResolution.noMatch());
      await _completeFigmaScan(tester);
      expect(
        tester.widget<InkWell>(find.byKey(const Key('scan-done-action'))).onTap,
        isNotNull,
      );
    },
  );

  testWidgets(
    'a server quota rejection removes a single capture because no queued image can be resumed',
    (tester) async {
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(
            ScanResolution.quotaExhausted(
              imageBytes: Uint8List.fromList(_transparentPngBytes),
              displayImageBytes: Uint8List.fromList(_transparentPngBytes),
              imageFileName: 'capture.png',
              quota: _exhaustedQuota,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pumpAndSettle();

      expect(find.text('Subscription'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
    },
  );

  testWidgets(
    'gallery quota overflow preserves selected images as Waiting in queue order',
    (tester) async {
      final bytes = Uint8List.fromList(_transparentPngBytes);
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(const ScanResolution.failed()),
          libraryImages: [
            ScanImage(bytes: bytes, fileName: 'first.png'),
            ScanImage(bytes: bytes, fileName: 'second.png'),
          ],
          libraryResults: [
            Future.value(
              ScanResolution.noMatch(
                imageBytes: bytes,
                imageFileName: 'first.png',
                quota: _exhaustedQuota,
              ),
            ),
            Future.value(
              ScanResolution.quotaExhausted(
                imageBytes: bytes,
                displayImageBytes: bytes,
                imageFileName: 'second.png',
                quota: _exhaustedQuota,
              ),
            ),
          ],
        ),
      );

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pumpAndSettle();
      expect(find.text('Subscription'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final waitingItem = find.byKey(const Key('scan-active-item-2'));
      expect(waitingItem, findsOneWidget);
      expect(
        find.descendant(
          of: waitingItem,
          matching: find.text('Waiting to scan'),
        ),
        findsNWidgets(2),
      );
    },
  );

  testWidgets(
    'Waiting delete removes only that item without opening the paywall',
    (tester) async {
      final bytes = Uint8List.fromList(_transparentPngBytes);
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(const ScanResolution.failed()),
          libraryImages: [ScanImage(bytes: bytes, fileName: 'waiting.png')],
          libraryResults: [
            Future.value(
              ScanResolution.quotaExhausted(
                imageBytes: bytes,
                displayImageBytes: bytes,
                imageFileName: 'waiting.png',
                quota: _exhaustedQuota,
              ),
            ),
          ],
        ),
      );

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-delete-item-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
      expect(find.text('Subscription'), findsNothing);
    },
  );

  testWidgets('Waiting card body opens the functional paywall', (tester) async {
    final bytes = Uint8List.fromList(_transparentPngBytes);
    final source = _TestScanResultSource(
      photoResult: Future.value(const ScanResolution.failed()),
      libraryImages: [ScanImage(bytes: bytes, fileName: 'waiting.png')],
      libraryResults: [
        Future.value(
          ScanResolution.quotaExhausted(
            imageBytes: bytes,
            displayImageBytes: bytes,
            imageFileName: 'waiting.png',
            quota: _exhaustedQuota,
          ),
        ),
      ],
    );
    await _pumpScanTestApp(tester, scanResultSource: source);

    await tester.tap(find.byTooltip('Choose from Library'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unlock unlimited scans'));
    await tester.pumpAndSettle();

    expect(find.text('Subscription'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(source.lastRetryFileName, isNull);
  });

  testWidgets(
    'Waiting Premium success resumes the queued image after server quota confirms unlimited',
    (tester) async {
      final bytes = Uint8List.fromList(_transparentPngBytes);
      final quotaController = _TestScanQuotaController(
        _availableQuota,
        refreshQuotas: const [
          _availableQuota,
          ScanQuotaDto(
            access: ScanQuotaAccess.premium,
            limit: 10,
            reserved: 0,
            consumed: 10,
            remaining: 0,
            unlimited: true,
          ),
        ],
      );
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        libraryImages: [ScanImage(bytes: bytes, fileName: 'waiting.png')],
        libraryResults: [
          Future.value(
            ScanResolution.quotaExhausted(
              imageBytes: bytes,
              displayImageBytes: bytes,
              imageFileName: 'waiting.png',
              quota: _exhaustedQuota,
            ),
          ),
        ],
        retryResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuotaController: quotaController,
        subscriptionResult: SubscriptionPaywallResult.premiumUnlocked,
      );

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('subscription-test-result')));
      await tester.pumpAndSettle();

      expect(source.lastRetryFileName, 'waiting.png');
      expect(quotaController.state.unlimited, isTrue);
    },
  );

  testWidgets(
    'Failed retry becomes Waiting when the latest server quota is exhausted',
    (tester) async {
      final bytes = Uint8List.fromList(_transparentPngBytes);
      final source = _TestScanResultSource(
        photoResult: Future.value(
          ScanResolution.failed(
            imageBytes: bytes,
            imageFileName: 'failed.png',
            quota: _exhaustedQuota,
          ),
        ),
      );
      await _pumpScanTestApp(tester, scanResultSource: source);

      await tester.tap(find.byTooltip('Take Photo'));
      await _completeFigmaScan(tester);
      await tester.tap(find.byTooltip('Retry scan'));
      await tester.pumpAndSettle();

      expect(source.lastRetryFileName, isNull);
      expect(find.text('Subscription'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unlock unlimited scans'), findsOneWidget);
    },
  );

  testWidgets(
    'Matched plus Waiting enables Done because Waiting is not Processing',
    (tester) async {
      final bytes = Uint8List.fromList(_transparentPngBytes);
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(const ScanResolution.failed()),
          libraryImages: [
            ScanImage(bytes: bytes, fileName: 'matched.png'),
            ScanImage(bytes: bytes, fileName: 'waiting.png'),
          ],
          libraryResults: [
            Future.value(
              const ScanResolution.matched(
                scanId: 'matched',
                cardRef: 'card-mega',
                matchName: 'Mega Lucario ex',
                candidates: ['Mega Lucario ex'],
              ),
            ),
            Future.value(
              ScanResolution.quotaExhausted(
                imageBytes: bytes,
                displayImageBytes: bytes,
                imageFileName: 'waiting.png',
                quota: _exhaustedQuota,
              ),
            ),
          ],
        ),
      );

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await _completeFigmaScan(tester);

      expect(
        tester.widget<InkWell>(find.byKey(const Key('scan-done-action'))).onTap,
        isNotNull,
      );
    },
  );

  testWidgets(
    'entitlement synchronization preserves the image without showing a free paywall',
    (tester) async {
      final bytes = Uint8List.fromList(_transparentPngBytes);
      await _pumpScanTestApp(
        tester,
        scanResultSource: _TestScanResultSource(
          photoResult: Future.value(
            ScanResolution.entitlementSyncRequired(
              imageBytes: bytes,
              displayImageBytes: bytes,
              imageFileName: 'premium.png',
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pumpAndSettle();

      expect(find.text('Premium Syncing'), findsOneWidget);
      expect(find.text('Syncing Premium'), findsOneWidget);
      expect(find.text('No Match Found'), findsNothing);
      expect(find.text('Subscription'), findsNothing);
      expect(find.text('Failed'), findsNothing);
    },
  );

  testWidgets(
    'Waiting resumes only after the server confirms unlimited Premium',
    (tester) async {
      final bytes = Uint8List.fromList(_transparentPngBytes);
      final quotaController = _TestScanQuotaController(
        _exhaustedQuota,
        refreshQuotas: const [
          _exhaustedQuota,
          _exhaustedQuota,
          ScanQuotaDto(
            access: ScanQuotaAccess.premium,
            limit: 10,
            reserved: 0,
            consumed: 10,
            remaining: 0,
            unlimited: true,
          ),
        ],
      );
      final source = _TestScanResultSource(
        photoResult: Future.value(
          ScanResolution.entitlementSyncRequired(
            imageBytes: bytes,
            displayImageBytes: bytes,
            imageFileName: 'premium.png',
          ),
        ),
        retryResult: Future.value(const ScanResolution.noMatch()),
      );
      final subscription = _SynchronizingScanSubscriptionController();
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuotaController: quotaController,
        subscriptionController: () => subscription,
      );

      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pump();
      expect(source.lastRetryFileName, isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(source.lastRetryFileName, 'premium.png');
      expect(quotaController.state.unlimited, isTrue);
      expect(subscription.synchronizeCount, 1);
    },
  );

  testWidgets(
    'concurrent Premium sync items share one entitlement synchronization',
    (tester) async {
      final bytes = Uint8List.fromList(_transparentPngBytes);
      final synchronization = Completer<bool>();
      final subscription = _SynchronizingScanSubscriptionController(
        onSynchronize: () => synchronization.future,
      );
      final quotaController = _TestScanQuotaController(
        _exhaustedQuota,
        refreshQuotas: const [_exhaustedQuota, _unlimitedQuota],
      );
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        libraryImages: [
          ScanImage(bytes: bytes, fileName: 'premium-1.png'),
          ScanImage(bytes: bytes, fileName: 'premium-2.png'),
        ],
        libraryResults: [
          for (var index = 1; index <= 2; index += 1)
            Future.value(
              ScanResolution.entitlementSyncRequired(
                imageBytes: bytes,
                displayImageBytes: bytes,
                imageFileName: 'premium-$index.png',
              ),
            ),
        ],
        retryResult: Future.value(const ScanResolution.noMatch()),
      );
      await _pumpScanTestApp(
        tester,
        scanResultSource: source,
        scanQuotaController: quotaController,
        subscriptionController: () => subscription,
      );

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Premium Syncing'), findsNWidgets(2));
      expect(subscription.synchronizeCount, 1);

      synchronization.complete(true);
      await tester.pump();
      await tester.pump();

      expect(quotaController.state.unlimited, isTrue);
      expect(source.retryCallCount, 2);
    },
  );

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
    'Gallery shows the selected thumbnail immediately without shutter feedback because recognition must not hide the uploaded image',
    (tester) async {
      final pending = Completer<ScanResolution>();
      final galleryBytes = Uint8List.fromList(_transparentPngBytes);
      final source = _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.failed()),
        libraryResults: [pending.future],
        libraryImages: [
          ScanImage(bytes: galleryBytes, fileName: 'gallery-card.png'),
        ],
      );
      await _pumpScanTestApp(tester, scanResultSource: source);

      await tester.tap(find.byTooltip('Choose from Library'));
      await tester.pump();

      final item = find.byKey(const Key('scan-active-item-1'));
      expect(
        find.descendant(of: item, matching: find.byType(Image)),
        findsOneWidget,
      );
      final galleryImage = tester.widget<Image>(
        find.descendant(of: item, matching: find.byType(Image)),
      );
      expect(
        (galleryImage.image as MemoryImage).bytes,
        same(galleryBytes),
        reason: 'Gallery previews must keep the selected original image.',
      );
      expect(
        find.byKey(const Key('scan-recognition-progress')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scan-delete-item-1')),
        findsOneWidget,
        reason: 'Every scan state must retain its delete control.',
      );
      expect(find.byKey(const Key('scan-figma-scanning-line')), findsNothing);
      expect(
        find.byKey(const Key('scan-figma-camera-overlay')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const Key('scan-figma-recognizing-overlay')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('scan-figma-camera-overlay')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const Key('scan-figma-revealing-overlay')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('scan-figma-camera-overlay')),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const Key('scan-figma-result-rail'))).bottom,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('Take Photo')).top),
      );
    },
  );

  testWidgets('Deleting a matched scan removes it without opening Review', (
    tester,
  ) async {
    await _pumpScanTestApp(tester);

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);

    expect(find.byTooltip('Review scan result'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-delete-item-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
    expect(find.text('Review your matches'), findsNothing);
  });

  testWidgets('Deleting a no-match scan removes it without opening Search', (
    tester,
  ) async {
    final analytics = _AnalyticsRecorder();
    await _pumpScanTestApp(
      tester,
      scanResultSource: _TestScanResultSource(
        photoResult: Future.value(const ScanResolution.noMatch()),
      ),
      analytics: analytics.client,
    );

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);

    expect(find.text('No Match Found'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-delete-item-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
    expect(find.text('Search cards, sets, or characters'), findsNothing);
    expect(analytics.count(AnalyticsEvent.deleteClick), 1);
  });

  testWidgets(
    'No Match scan offers Search Manually because unmatched cards cannot enter review',
    (tester) async {
      final analytics = _AnalyticsRecorder();
      await _pumpScanTestApp(tester, analytics: analytics.client);

      await tester.tap(find.byTooltip('Choose from Library'));
      await _completeFigmaScan(tester);

      expect(find.text('No Match Found'), findsOneWidget);
      expect(find.text('Search Manually'), findsOneWidget);
      final noMatchDone = tester.widget<InkWell>(
        find.byKey(const Key('scan-done-action')),
      );
      expect(noMatchDone.onTap, isNull);

      await tester.tap(find.text('Search Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Search cards, sets, or characters'), findsOneWidget);
      expect(find.text('Squirtle'), findsOneWidget);
      expect(find.byTooltip('Back to Scan'), findsOneWidget);
      expect(find.text('No Match Found', skipOffstage: false), findsOneWidget);

      await tester.tap(find.byTooltip('Back to Scan'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Take Photo'), findsOneWidget);
      expect(find.text('No Match Found'), findsNothing);
      expect(analytics.count(AnalyticsEvent.deleteClick), 0);
    },
  );

  testWidgets('Add click reports analytics even when review validation fails', (
    tester,
  ) async {
    final analytics = _AnalyticsRecorder();
    await _pumpScanTestApp(tester, analytics: analytics.client);

    await tester.tap(find.byTooltip('Take Photo'));
    await _completeFigmaScan(tester);
    await tester.tap(find.byTooltip('Review completed scan'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scan-review-quantity-1')),
      '0',
    );
    await tester.tap(find.text('Add this card'));
    await tester.pump();

    expect(analytics.count(AnalyticsEvent.collectionItemAddClick), 1);
    expect(analytics.count(AnalyticsEvent.scanResults), 1);
    expect(find.byKey(const Key('scan-review-form-error')), findsOneWidget);
    final toast = find.byKey(const Key('kando-top-toast'));
    expect(toast, findsOneWidget);
    expect(
      find.descendant(
        of: toast,
        matching: find.text('Quantity must be a whole number of 1 or more.'),
      ),
      findsOneWidget,
    );
    await tester.pump(kandoTopToastDuration);
    await tester.pump();
  });

  testWidgets('Scan keeps capture controls available across multiple results', (
    tester,
  ) async {
    final repository = _FakeScanReviewRepository();
    await _pumpScanTestApp(tester, scanReviewRepository: repository);

    await tester.tap(find.byTooltip('Take Photo'));
    await tester.pump();
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
    expect(find.text('Tap to retry'), findsOneWidget);
    expect(
      find.byTooltip('Delete scan result'),
      findsNWidgets(3),
      reason: 'Every scan result must retain its delete control.',
    );
    expect(find.text('Search Manually'), findsOneWidget);
    expect(find.text('Scan Results'), findsNothing);

    final resultRail = tester.getRect(
      find.byKey(const Key('scan-figma-result-rail')),
    );
    final firstResult = tester.getRect(
      find.byKey(const Key('scan-active-item-1')),
    );
    final secondResult = tester.getRect(
      find.byKey(const Key('scan-active-item-2')),
    );
    expect(resultRail.height, 82);
    expect(firstResult.height, 82);
    expect(secondResult.height, 82);
    expect(secondResult.left, lessThan(firstResult.left));
    expect(secondResult.top, firstResult.top);

    final doneWithMatched = tester.widget<InkWell>(
      find.byKey(const Key('scan-done-action')),
    );
    expect(doneWithMatched.onTap, isNotNull);

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
    expect(
      find.text('No Match Found'),
      findsNothing,
      reason: 'No Match scans have no card metadata to edit during batch save.',
    );

    await tester.enterText(
      find.byKey(const Key('scan-review-quantity-4')),
      '3',
    );

    expect(find.text('ADD ALL CARDS'), findsOneWidget);

    await tester.tap(find.text('ADD ALL CARDS'));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('kando-centered-success-toast')),
      findsOneWidget,
    );
    expect(find.text(portfolioCardsAddedToastText(2)), findsOneWidget);
    expect(find.text('Review your matches'), findsOneWidget);

    await tester.pump(kandoCenteredSuccessToastDuration);
    await tester.pumpAndSettle();
    expect(find.text('Review your matches'), findsNothing);

    expect(find.byKey(const Key('scan-active-item-1')), findsNothing);
    expect(find.byKey(const Key('scan-active-item-4')), findsNothing);
    expect(find.text('ADDED'), findsNothing);
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
  ScanPermissionGateway permissions = const _GrantedScanPermissionGateway(),
  AppAnalytics? analytics,
  ScanQuotaDto? scanQuota,
  _TestScanQuotaController? scanQuotaController,
  SubscriptionController Function()? subscriptionController,
  SubscriptionPaywallResult? subscriptionResult,
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
        scanPermissionGatewayProvider.overrideWithValue(permissions),
        scanQuotaControllerProvider.overrideWith(
          () =>
              scanQuotaController ??
              _TestScanQuotaController(scanQuota ?? _availableQuota),
        ),
        subscriptionControllerProvider.overrideWith(
          subscriptionController ?? _FreeScanSubscriptionController.new,
        ),
        if (analytics != null) analyticsProvider.overrideWithValue(analytics),
      ],
      child: TickerMode(
        enabled: tickerEnabled,
        child: _ScanTestAppWithRoutes(subscriptionResult: subscriptionResult),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

_scanGoldenOverrides() {
  return [
    scanPermissionGatewayProvider.overrideWithValue(
      const _GrantedScanPermissionGateway(),
    ),
    scanCameraFactoryProvider.overrideWithValue(
      const _DisabledScanCameraFactory(),
    ),
    scanResultSourceProvider.overrideWithValue(_defaultTestScanResultSource()),
    scanReviewRepositoryProvider.overrideWithValue(_FakeScanReviewRepository()),
    scanQuotaControllerProvider.overrideWith(
      () => _TestScanQuotaController(_availableQuota),
    ),
    subscriptionControllerProvider.overrideWith(
      _FreeScanSubscriptionController.new,
    ),
  ];
}

class _AnalyticsRecorder {
  _AnalyticsRecorder() {
    client = AppAnalytics.recording((event, properties) {
      events.add((event: event, properties: properties));
    });
  }

  late final AppAnalytics client;
  final events = <({String event, Map<String, Object?> properties})>[];

  int count(String event) {
    return events.where((record) => record.event == event).length;
  }

  List<Map<String, Object?>> propertiesFor(String event) {
    return [
      for (final record in events)
        if (record.event == event) record.properties,
    ];
  }
}

class _ProScanSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() => const SubscriptionState(isPro: true);
}

class _MutableScanSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.premium);

  void setPremiumState(AppPremiumState premiumState) {
    state = state.copyWith(premiumState: premiumState);
  }

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async {
    return state.premiumState;
  }
}

class _SynchronizingScanSubscriptionController extends SubscriptionController {
  _SynchronizingScanSubscriptionController({
    this.premiumState = AppPremiumState.premium,
    this.onSynchronize,
  });

  final AppPremiumState premiumState;
  final Future<bool> Function()? onSynchronize;
  var synchronizeCount = 0;

  @override
  SubscriptionState build() => SubscriptionState(premiumState: premiumState);

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async {
    return premiumState;
  }

  @override
  Future<bool> synchronizeServerEntitlement() async {
    synchronizeCount += 1;
    return await onSynchronize?.call() ?? true;
  }
}

class _FreeScanSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.free);

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async {
    return AppPremiumState.free;
  }
}

class _StaleFreeScanSubscriptionController extends SubscriptionController {
  var refreshCount = 0;

  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.free);

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async {
    refreshCount += 1;
    state = state.copyWith(premiumState: AppPremiumState.premium);
    return AppPremiumState.premium;
  }
}

class _ResolvingScanSubscriptionController extends SubscriptionController {
  _ResolvingScanSubscriptionController(this.resolvedState);

  final AppPremiumState resolvedState;

  @override
  SubscriptionState build() => const SubscriptionState();

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async {
    if (resolvedState != AppPremiumState.unknown) {
      state = state.copyWith(premiumState: resolvedState);
    } else if (showFailure) {
      state = state.copyWith(
        errorMessage: 'Unable to verify Premium access. Please try again.',
      );
    }
    return resolvedState;
  }
}

class _TestScanQuotaController extends ScanQuotaController {
  _TestScanQuotaController(this.quota, {this.refreshQuotas = const []});

  final ScanQuotaDto quota;
  final List<ScanQuotaDto> refreshQuotas;
  var _refreshIndex = 0;

  @override
  ScanQuotaState build() => ScanQuotaState(
    limit: quota.limit,
    remainingScans: quota.remaining,
    unlimited: quota.unlimited,
    isServerAuthoritative: true,
  );

  @override
  Future<bool> refresh() async {
    await Future<void>.value();
    if (_refreshIndex < refreshQuotas.length) {
      applyServerQuota(refreshQuotas[_refreshIndex]);
      _refreshIndex += 1;
    }
    return true;
  }
}

class _FakeScanReviewRepository implements ScanReviewRepository {
  _FakeScanReviewRepository({
    this.failure,
    this.rawPrice = 25,
    this.availableLanguages = const ['English'],
    this.availableFinishes = const ['Holofoil'],
  });

  final Exception? failure;
  final double rawPrice;
  final List<String> availableLanguages;
  final List<String> availableFinishes;
  final List<String> confirmedScanIds = [];
  final List<ScanCollectionItemInput> confirmedItems = [];

  static const target = ScanReviewTarget(
    folderId: 'main',
    folderName: 'Main',
    folders: [
      ScanReviewFolder(id: 'main', name: 'Main'),
      ScanReviewFolder(id: 'trade', name: 'Trade'),
    ],
  );

  @override
  Future<ScanReviewTarget> loadTarget({String? preferredFolderId}) async {
    return target;
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
          availableLanguages: availableLanguages,
          availableFinishes: availableFinishes,
          prices: [
            ScanReviewPrice(
              grader: 'Raw',
              grade: null,
              condition: 'Near Mint',
              price: rawPrice,
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

class _DelayedScanReviewRepository extends _FakeScanReviewRepository {
  _DelayedScanReviewRepository(this.targetFuture);

  final Future<ScanReviewTarget> targetFuture;
  var loadTargetCount = 0;

  @override
  Future<ScanReviewTarget> loadTarget({String? preferredFolderId}) {
    loadTargetCount += 1;
    return targetFuture;
  }
}

class _MissingCurrentScanReviewRepository extends _FakeScanReviewRepository {
  var loadTargetCount = 0;

  @override
  Future<ScanReviewTarget> loadTarget({String? preferredFolderId}) async {
    loadTargetCount += 1;
    return super.loadTarget(preferredFolderId: preferredFolderId);
  }

  @override
  Future<Map<String, ScanReviewCard>> loadCards(List<String> cardRefs) async {
    return const {};
  }
}

class _BlockingScanReviewRepository extends _FakeScanReviewRepository {
  final _confirmations =
      <({String scanId, Completer<ScanConfirmationDto> completer})>[];

  int get confirmationCount => _confirmations.length;

  @override
  Future<ScanConfirmationDto> addToPortfolio({
    required String scanId,
    required ScanCollectionItemInput item,
  }) {
    final completer = Completer<ScanConfirmationDto>();
    _confirmations.add((scanId: scanId, completer: completer));
    return completer.future;
  }

  void completeNextConfirmation() {
    final confirmation = _confirmations
        .where((candidate) => !candidate.completer.isCompleted)
        .first;
    confirmation.completer.complete(
      ScanConfirmationDto(
        scanId: confirmation.scanId,
        collectionItemId: 'item-${confirmation.scanId}',
        cardRef: 'card-${confirmation.scanId}',
        folderId: 'main',
      ),
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
        quota: ScanQuotaDto(
          access: ScanQuotaAccess.free,
          limit: 10,
          reserved: 0,
          consumed: 1,
          remaining: 9,
          unlimited: false,
        ),
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
    this.libraryImages = const [],
    this.libraryGate,
    Future<ScanResolution>? recognizeResult,
    List<Future<ScanResolution>> subsequentRecognizeResults = const [],
    Future<ScanResolution>? retryResult,
  }) : _photoResults = [photoResult, ...subsequentPhotoResults],
       _libraryResults =
           libraryResults ??
           [libraryResult ?? Future.value(const ScanResolution.noMatch())],
       _recognizeResults = [
         recognizeResult ?? photoResult,
         ...subsequentRecognizeResults,
       ],
       _retryResult =
           retryResult ?? Future.value(const ScanResolution.failed());

  final List<Future<ScanResolution>> _photoResults;
  final List<Future<ScanResolution>> _libraryResults;
  final List<ScanImage> libraryImages;
  final Future<void>? libraryGate;
  final List<Future<ScanResolution>> _recognizeResults;
  final Future<ScanResolution> _retryResult;
  var photoCallCount = 0;
  var libraryCallCount = 0;
  var retryCallCount = 0;
  var _nextPhotoResult = 0;
  var _nextRecognizeResult = 0;
  Uint8List? lastRetryBytes;
  String? lastRetryFileName;
  final recognizedImages = <ScanImage>[];

  @override
  Future<List<Future<ScanResolution>>> library({
    int maxItems = 10,
    void Function(ScanImage image, Future<ScanResolution> resolution)?
    onSelected,
  }) async {
    libraryCallCount += 1;
    await libraryGate;
    for (
      var index = 0;
      index < libraryImages.length && index < maxItems;
      index += 1
    ) {
      onSelected?.call(libraryImages[index], _libraryResults[index]);
    }
    return _libraryResults.take(maxItems).toList();
  }

  @override
  Future<ScanResolution> photo() {
    photoCallCount += 1;
    final resultIndex = _nextPhotoResult < _photoResults.length
        ? _nextPhotoResult
        : _photoResults.length - 1;
    _nextPhotoResult += 1;
    return _photoResults[resultIndex];
  }

  @override
  Future<ScanResolution> recognize(
    ScanImage image, {
    ValueChanged<Uint8List>? onDisplayImageReady,
  }) async {
    recognizedImages.add(image);
    final resultIndex = _nextRecognizeResult < _recognizeResults.length
        ? _nextRecognizeResult
        : _recognizeResults.length - 1;
    _nextRecognizeResult += 1;
    final result = await _recognizeResults[resultIndex];
    final displayImageBytes = result.displayImageBytes;
    if (displayImageBytes != null) {
      onDisplayImageReady?.call(displayImageBytes);
    }
    return result;
  }

  @override
  Future<ScanResolution> retry({Uint8List? imageBytes, String? fileName}) {
    retryCallCount += 1;
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
  var openCount = 0;

  @override
  Future<ScanCameraSession?> open() async {
    openCount += 1;
    return session;
  }
}

class _GrantedScanPermissionGateway implements ScanPermissionGateway {
  const _GrantedScanPermissionGateway();

  @override
  Future<ScanPermissionResult> requestCamera() async =>
      ScanPermissionResult.granted;

  @override
  Future<ScanPermissionResult> requestGallery() async =>
      ScanPermissionResult.granted;

  @override
  Future<bool> openSettings() async => true;
}

class _TestScanPermissionGateway implements ScanPermissionGateway {
  _TestScanPermissionGateway({
    this.camera = ScanPermissionResult.granted,
    this.gallery = ScanPermissionResult.granted,
  });

  final ScanPermissionResult camera;
  final ScanPermissionResult gallery;
  var cameraRequests = 0;
  var galleryRequests = 0;
  var settingsRequests = 0;

  @override
  Future<ScanPermissionResult> requestCamera() async {
    cameraRequests += 1;
    return camera;
  }

  @override
  Future<ScanPermissionResult> requestGallery() async {
    galleryRequests += 1;
    return gallery;
  }

  @override
  Future<bool> openSettings() async {
    settingsRequests += 1;
    return true;
  }
}

class _PermissionDelayedScanCameraFactory implements ScanCameraFactory {
  _PermissionDelayedScanCameraFactory(this.secondSession);

  final firstOpen = Completer<ScanCameraSession?>();
  final _TestScanCameraSession secondSession;
  var openCount = 0;

  @override
  Future<ScanCameraSession?> open() {
    openCount += 1;
    return openCount == 1 ? firstOpen.future : Future.value(secondSession);
  }
}

class _TestScanCameraSession implements ScanCameraSession {
  var _flashEnabled = false;
  var takePhotoCount = 0;
  var pausePreviewCount = 0;
  var resumePreviewCount = 0;
  var disposed = false;

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
      bytes: Uint8List.fromList(_transparentPngBytes),
      fileName: 'live-camera.jpg',
    );
  }

  @override
  Future<bool> toggleFlash() async {
    _flashEnabled = !_flashEnabled;
    return _flashEnabled;
  }

  @override
  Future<void> pausePreview() async {
    pausePreviewCount += 1;
  }

  @override
  Future<void> resumePreview() async {
    resumePreviewCount += 1;
  }

  @override
  Future<void> dispose() async {
    _flashEnabled = false;
    disposed = true;
  }
}

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}

class _ScanTestAppWithRoutes extends StatelessWidget {
  const _ScanTestAppWithRoutes({this.subscriptionResult});

  final SubscriptionPaywallResult? subscriptionResult;

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
            builder: (context, state) => SearchPage(
              fromScan: state.uri.queryParameters['from'] == 'scan',
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
          GoRoute(
            path: '/subscription',
            builder: (context, state) => Scaffold(
              body: Center(
                child: subscriptionResult == null
                    ? const Text('Subscription')
                    : TextButton(
                        key: const Key('subscription-test-result'),
                        onPressed: () => context.pop(subscriptionResult),
                        child: const Text('Unlock Premium'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
