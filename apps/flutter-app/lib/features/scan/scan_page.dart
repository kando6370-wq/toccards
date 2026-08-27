import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';

import '../../shared/card_image/kando_card_image.dart';
import '../../shared/analytics/analytics_events.dart';
import '../../shared/analytics/app_analytics.dart';
import '../../shared/currency/currency.dart';
import '../../shared/portfolio/portfolio_providers.dart';
import '../../shared/portfolio/portfolio_api_client.dart';
import '../../shared/scan/scan_api_client.dart';
import '../../shared/scan/scan_image_hasher.dart';
import '../../shared/ui/kando_style.dart';
import '../../shared/ui/premium_unlocked_toast.dart';
import '../../shared/ui/subscription_restore_result.dart';
import '../../shared/ui/toast.dart';
import '../collection/collection_controller.dart';
import '../card_detail/card_detail_controller.dart';
import '../home/home_controller.dart';
import '../search/search_controller.dart';
import '../subscription/scan_quota_controller.dart';
import '../subscription/subscription_controller.dart';
import '../subscription/subscription_entitlement_cache.dart';
import 'scan_camera.dart';
import 'scan_permissions.dart';
import 'scan_review_repository.dart';

enum _ScanItemStatus {
  scanning,
  recognizing,
  revealing,
  matched,
  failed,
  noMatch,
  waiting,
  entitlementSync,
}

enum _ScanReviewSaveAction { single, all }

class _ScanReviewLoadException implements Exception {
  const _ScanReviewLoadException();
}

const _viewfinderBaseTop = 213.0;
const _viewfinderBaseWidth = 280.0;
const _viewfinderBaseHeight = 400.0;
const _viewfinderHorizontalMargin = 24.0;
const _viewfinderControlGap = 16.0;
// Reserve the full Free chrome so unlocking Premium never moves the frame.
const _viewfinderTopChromeHeight = 10 + 32 + 2 + 34 + 6 + 48;
const _viewfinderBottomChromeHeight = 22 + 88;

class _ScanViewfinderGeometry {
  const _ScanViewfinderGeometry(this.rect);

  final Rect rect;

  Alignment radialAlignment(Size viewport) {
    if (viewport.isEmpty) return Alignment.center;
    return Alignment(
      (rect.center.dx * 2 / viewport.width) - 1,
      (rect.center.dy * 2 / viewport.height) - 1,
    );
  }
}

_ScanViewfinderGeometry _scanViewfinderGeometry(
  Size viewport,
  EdgeInsets padding,
) {
  if (viewport.isEmpty) {
    return const _ScanViewfinderGeometry(Rect.zero);
  }
  final leftLimit = (padding.left + _viewfinderHorizontalMargin).clamp(
    0.0,
    viewport.width,
  );
  final rightLimit =
      (viewport.width - padding.right - _viewfinderHorizontalMargin).clamp(
        leftLimit,
        viewport.width,
      );
  final topLimit =
      (padding.top + _viewfinderTopChromeHeight + _viewfinderControlGap).clamp(
        0.0,
        viewport.height,
      );
  final bottomLimit =
      (viewport.height -
              padding.bottom -
              _viewfinderBottomChromeHeight -
              _viewfinderControlGap)
          .clamp(topLimit, viewport.height);
  final widthScale = (rightLimit - leftLimit) / _viewfinderBaseWidth;
  final heightScale = (bottomLimit - topLimit) / _viewfinderBaseHeight;
  final scale = math.max(0.0, math.min(1.0, math.min(widthScale, heightScale)));
  final width = _viewfinderBaseWidth * scale;
  final height = _viewfinderBaseHeight * scale;
  final left = leftLimit + ((rightLimit - leftLimit - width) / 2);
  final maxTop = math.max(topLimit, bottomLimit - height);
  final top = _viewfinderBaseTop.clamp(topLimit, maxTop);
  return _ScanViewfinderGeometry(Rect.fromLTWH(left, top, width, height));
}

ScanImageCrop _cameraRecognitionCrop(Size viewport, EdgeInsets padding) {
  final rect = _scanViewfinderGeometry(
    viewport,
    padding,
  ).rect.intersect(Offset.zero & viewport);
  return ScanImageCrop(
    left: rect.left / viewport.width,
    top: rect.top / viewport.height,
    width: rect.width / viewport.width,
    height: rect.height / viewport.height,
    viewportAspectRatio: viewport.width / viewport.height,
  );
}

class _ScanMatch {
  const _ScanMatch({
    required this.scanId,
    required this.cardRef,
    required this.name,
    required this.candidates,
  });

  final String scanId;
  final String cardRef;
  final String name;
  final List<_ScanCandidate> candidates;

  _ScanMatch select(_ScanCandidate candidate) {
    return _ScanMatch(
      scanId: scanId,
      cardRef: candidate.cardRef,
      name: candidate.name,
      candidates: candidates,
    );
  }
}

class _ScanCandidate {
  const _ScanCandidate({required this.cardRef, required this.name});

  final String cardRef;
  final String name;
}

class _ScanItem {
  const _ScanItem({
    required this.id,
    required this.pictureLabel,
    required this.status,
    required this.usesCameraFeedback,
    this.match,
    this.imageBytes,
    this.displayImageBytes,
    this.imageFileName,
    this.retainOnQuotaExhausted = false,
  });

  final int id;
  final String pictureLabel;
  final _ScanItemStatus status;
  final bool usesCameraFeedback;
  final _ScanMatch? match;
  final Uint8List? imageBytes;
  final Uint8List? displayImageBytes;
  final String? imageFileName;
  final bool retainOnQuotaExhausted;

  _ScanItem copyWith({
    _ScanItemStatus? status,
    _ScanMatch? match,
    Uint8List? imageBytes,
    Uint8List? displayImageBytes,
    String? imageFileName,
    bool? retainOnQuotaExhausted,
  }) {
    return _ScanItem(
      id: id,
      pictureLabel: pictureLabel,
      status: status ?? this.status,
      usesCameraFeedback: usesCameraFeedback,
      match: match ?? this.match,
      imageBytes: imageBytes ?? this.imageBytes,
      displayImageBytes: displayImageBytes ?? this.displayImageBytes,
      imageFileName: imageFileName ?? this.imageFileName,
      retainOnQuotaExhausted:
          retainOnQuotaExhausted ?? this.retainOnQuotaExhausted,
    );
  }
}

class _ScanCollectionDraft {
  const _ScanCollectionDraft({
    required this.folderId,
    required this.folderName,
    required this.quantityText,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.language,
    required this.finish,
    required this.purchasePriceText,
    required this.notes,
  });

  final String folderId;
  final String folderName;
  final String quantityText;
  final String grader;
  final String condition;
  final String grade;
  final String language;
  final String finish;
  final String purchasePriceText;
  final String notes;

  bool get isRaw => grader == 'Raw';

  _ScanCollectionDraft copyWith({
    String? folderId,
    String? folderName,
    String? quantityText,
    String? grader,
    String? condition,
    String? grade,
    String? language,
    String? finish,
    String? purchasePriceText,
    String? notes,
  }) {
    final nextGrader = grader ?? this.grader;
    final nextIsRaw = nextGrader == 'Raw';
    return _ScanCollectionDraft(
      folderId: folderId ?? this.folderId,
      folderName: folderName ?? this.folderName,
      quantityText: quantityText ?? this.quantityText,
      grader: nextGrader,
      condition: nextIsRaw
          ? condition ??
                (isRaw ? this.condition : cardCollectionConditions.first)
          : '',
      grade: nextIsRaw
          ? ''
          : grade ??
                (isRaw || grader != null
                    ? cardCollectionGradeValuesFor(nextGrader).first
                    : this.grade),
      language: language ?? this.language,
      finish: finish ?? this.finish,
      purchasePriceText: purchasePriceText ?? this.purchasePriceText,
      notes: notes ?? this.notes,
    );
  }
}

_ScanCollectionDraft _initialReviewDraft(
  ScanReviewTarget target,
  ScanReviewCard card,
) {
  return _ScanCollectionDraft(
    folderId: target.folderId,
    folderName: target.folderName,
    quantityText: '1',
    grader: 'Raw',
    condition: cardCollectionConditions.first,
    grade: '',
    language: _reviewOptionOrDefault(
      card.language,
      card.collectionLanguageOptions,
    ),
    finish: _reviewOptionOrDefault(card.finish, card.collectionFinishOptions),
    purchasePriceText: '',
    notes: '',
  );
}

String _reviewOptionOrDefault(String? value, List<String> options) {
  return options.contains(value) ? value! : options.first;
}

List<String> _optionsIncluding(List<String> options, String current) {
  return options.contains(current) ? options : [current, ...options];
}

String _reviewTotalText(
  ScanReviewCard card,
  _ScanCollectionDraft draft,
  AppCurrency currency,
) {
  final quantity = int.tryParse(draft.quantityText.trim());
  if (quantity == null || quantity < 1) return '--';
  final price = _selectedReviewPrice(card, draft);
  return CurrencyFormatter(
    currency: currency,
  ).formatUsd(price, quantity: quantity);
}

double? _selectedReviewPrice(ScanReviewCard card, _ScanCollectionDraft draft) {
  final hasFinishPrices = card.prices.any(
    (candidate) => candidate.finish != null,
  );
  final matchingPrices = card.prices.where((candidate) {
    if (hasFinishPrices &&
        candidate.finish?.toLowerCase() != draft.finish.toLowerCase()) {
      return false;
    }
    if (draft.isRaw) {
      if (candidate.grader.toLowerCase() != 'raw') return false;
      return _normalizedReviewCondition(candidate.condition) ==
          _normalizedReviewCondition(draft.condition);
    }
    final grade = double.tryParse(draft.grade);
    return grade != null &&
        cardCollectionPriceMatches(
          grader: draft.grader,
          grade: grade,
          marketGrader: candidate.grader,
          marketGrade: candidate.grade,
        );
  }).toList();
  return (matchingPrices
              .where(
                (candidate) =>
                    candidate.language?.toLowerCase() ==
                    draft.language.toLowerCase(),
              )
              .firstOrNull ??
          matchingPrices
              .where((candidate) => candidate.language == null)
              .firstOrNull)
      ?.price;
}

String _normalizedReviewCondition(String? value) {
  return (value ?? '').trim().toLowerCase().replaceFirst(
    RegExp(r'\s*\([^)]*\)\s*$'),
    '',
  );
}

class _PendingScan {
  _PendingScan(this.token);

  final int token;
  ScanResolution? resolution;
  var revealTimelineFinished = false;
  var removedFromUi = false;
  AnimationController? revealController;
}

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _maxQueueItems = 10;
  static const _revealTimelineDuration = Duration(microseconds: 1529856);
  static const _captureAnimationDuration = Duration(milliseconds: 500);
  static const _galleryCameraWarmupDuration = Duration(milliseconds: 500);

  final List<_ScanItem> _items = [];
  final List<Timer> _scanTimers = [];
  final Map<int, _PendingScan> _pendingScans = {};
  final Map<int, Stopwatch> _scanStopwatches = {};
  final Map<int, Duration> _scanDurations = {};
  final Map<int, String> _scanResultValues = {};
  final Set<int> _reportedScanResultIds = {};
  late final AnimationController _captureController;
  ScanCameraSession? _cameraSession;

  var _nextScanId = 1;
  var _nextScanToken = 1;
  var _cameraGeneration = 0;
  var _openingCamera = false;
  var _cameraPausedForLifecycle = false;
  var _permissionDialogVisible = false;
  var _appActive = true;
  var _openingReview = false;
  var _reviewing = false;
  int? _photoRecognitionItemId;
  var _premiumResolutionInFlight = false;
  var _freeEntitlementConfirmedForLifecycle = false;
  var _premiumDowngradedToFree = false;
  int? _captureFeedbackItemId;
  var _librarySelectionInFlight = false;
  var _quotaPaywallOpen = false;
  var _entitlementRefreshInFlight = false;
  Timer? _entitlementRefreshTimer;
  Completer<void>? _entitlementRefreshDelay;
  int? _selectedReviewItemId;
  ScanReviewTarget? _reviewTarget;
  Map<String, ScanReviewCard> _reviewCards = const {};
  final Map<int, _ScanCollectionDraft> _reviewDrafts = {};
  String? _reviewFormError;
  _ScanReviewSaveAction? _savingReviewAction;
  var _finishingReview = false;
  int? _dismissedFeedbackItemId;

  bool get _savingReview => _savingReviewAction != null || _finishingReview;

  bool get _isRecognizing {
    return _items.any(
      (item) =>
          item.usesCameraFeedback && item.status == _ScanItemStatus.recognizing,
    );
  }

  bool get _isRevealing {
    return _items.any(
      (item) =>
          item.usesCameraFeedback && item.status == _ScanItemStatus.revealing,
    );
  }

  bool get _showRevealingFeedback {
    final revealingItem = _items
        .where((item) => item.status == _ScanItemStatus.revealing)
        .firstOrNull;
    return revealingItem != null &&
        revealingItem.id != _dismissedFeedbackItemId;
  }

  List<_ScanItem> get _matchedItems {
    return _items
        .where((item) => item.status == _ScanItemStatus.matched)
        .toList();
  }

  bool get _canReview {
    final processing = _items.any(
      (item) =>
          item.status == _ScanItemStatus.scanning ||
          item.status == _ScanItemStatus.recognizing ||
          item.status == _ScanItemStatus.revealing,
    );
    return _matchedItems.isNotEmpty && !processing;
  }

  bool get _hasUnsavedScanResults {
    return _items.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _captureController = AnimationController(
      vsync: this,
      duration: _captureAnimationDuration,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(scanQuotaControllerProvider.notifier).refresh());
      }
    });
    unawaited(_openCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appActive = true;
      _freeEntitlementConfirmedForLifecycle = false;
      unawaited(_refreshQuotaAndResumeWaiting());
      unawaited(_resumeCameraForLifecycle());
      return;
    }
    if (state == AppLifecycleState.inactive) return;
    _appActive = false;
    unawaited(_pauseCameraForLifecycle());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureController.dispose();
    _cameraGeneration += 1;
    final camera = _cameraSession;
    if (camera != null) unawaited(camera.dispose());
    _cameraSession = null;
    for (final timer in _scanTimers) {
      timer.cancel();
    }
    for (final pending in _pendingScans.values) {
      pending.revealController?.dispose();
    }
    _entitlementRefreshTimer?.cancel();
    final entitlementRefreshDelay = _entitlementRefreshDelay;
    if (entitlementRefreshDelay?.isCompleted == false) {
      entitlementRefreshDelay!.complete();
    }
    _pendingScans.clear();
    super.dispose();
  }

  Future<void> _openCamera({Duration previewDelay = Duration.zero}) async {
    if (_openingCamera ||
        _cameraSession != null ||
        !_appActive ||
        _openingReview ||
        _reviewing ||
        _librarySelectionInFlight) {
      return;
    }
    _openingCamera = true;
    final generation = ++_cameraGeneration;
    final permission = await ref
        .read(scanPermissionGatewayProvider)
        .requestCamera();
    if (permission != ScanPermissionResult.granted) {
      if (mounted) {
        setState(() {
          _openingCamera = false;
        });
      }
      if (permission == ScanPermissionResult.permanentlyDenied) {
        await _showPermissionSettings('Camera');
      }
      return;
    }
    ScanCameraSession? session;
    try {
      session = await ref.read(scanCameraFactoryProvider).open();
      if (session != null && previewDelay > Duration.zero) {
        await Future<void>.delayed(previewDelay);
      }
    } catch (_) {
      session = null;
    }
    if (!mounted ||
        generation != _cameraGeneration ||
        !_appActive ||
        _reviewing ||
        _librarySelectionInFlight) {
      await session?.dispose();
      if (!mounted) return;
      _openingCamera = false;
      if (_appActive &&
          !_reviewing &&
          !_librarySelectionInFlight &&
          _cameraSession == null) {
        unawaited(_openCamera());
      }
      return;
    }
    setState(() {
      _cameraSession = session;
      _openingCamera = false;
    });
  }

  Future<void> _closeCamera() async {
    _cameraGeneration += 1;
    _cameraPausedForLifecycle = false;
    _photoRecognitionItemId = null;
    _captureFeedbackItemId = null;
    final session = _cameraSession;
    if (session == null) return;
    if (mounted) {
      setState(() => _cameraSession = null);
    } else {
      _cameraSession = null;
    }
    await session.dispose();
  }

  Future<void> _pauseCameraForLifecycle() async {
    if (_cameraPausedForLifecycle) return;
    _cameraPausedForLifecycle = true;
    _photoRecognitionItemId = null;
    _captureFeedbackItemId = null;
    final session = _cameraSession;
    if (session == null) return;
    try {
      if (session.flashEnabled) {
        await session.toggleFlash();
      }
      await session.pausePreview();
      if (mounted) setState(() {});
    } catch (_) {
      // The platform may already have interrupted the camera session.
    }
  }

  Future<void> _resumeCameraForLifecycle() async {
    _cameraPausedForLifecycle = false;
    final session = _cameraSession;
    if (session == null) {
      await _openCamera();
      return;
    }
    try {
      await session.resumePreview();
      if (mounted) setState(() {});
    } catch (_) {
      await _closeCamera();
      if (mounted && _appActive) {
        await _openCamera();
      }
    }
  }

  Future<void> _startPhotoScan() async {
    if (!_hasScanQueueCapacity()) return;
    if (!await _resolvePremiumBeforeScan()) return;
    if (!mounted) return;
    final source = ref.read(scanResultSourceProvider);
    final camera = _cameraSession;
    if (camera == null) {
      if (_openingCamera) return;
      if (_scanQuotaExhausted()) {
        unawaited(_openQuotaPaywall());
        return;
      }
      ref.read(analyticsProvider).track(AnalyticsEvent.cameraClick);
      _addScan(Future.sync(source.photo));
      return;
    }
    if (_photoRecognitionItemId != null) return;
    if (_scanQuotaExhausted()) {
      unawaited(_openQuotaPaywall());
      return;
    }
    ref.read(analyticsProvider).track(AnalyticsEvent.cameraClick);
    final itemId = _nextScanId;
    _photoRecognitionItemId = itemId;
    final result = _captureAndRecognize(
      itemId,
      camera,
      source,
      onCaptured: (image) => _attachScanImage(itemId, image),
      onDisplayImageReady: (bytes) => _attachScanDisplayImage(itemId, bytes),
    );
    final addedItemId = _addScan(result);
    assert(addedItemId == itemId);
    unawaited(_finishPhotoRecognition(itemId, result));
  }

  Future<ScanResolution> _captureAndRecognize(
    int itemId,
    ScanCameraSession camera,
    ScanResultSource source, {
    required ValueChanged<ScanImage> onCaptured,
    required ValueChanged<Uint8List> onDisplayImageReady,
  }) async {
    try {
      setState(() => _captureFeedbackItemId = itemId);
      await _captureController.forward(from: 0).orCancel;
      if (!mounted) return const ScanResolution.failed();
      final mediaQuery = MediaQueryData.fromView(View.of(context));
      final recognitionCrop = _cameraRecognitionCrop(
        mediaQuery.size,
        mediaQuery.padding,
      );
      final image = await camera.takePhoto();
      onCaptured(image);
      return await source.recognize(
        ScanImage(
          bytes: image.bytes,
          fileName: image.fileName,
          recognitionCrop: recognitionCrop,
        ),
        onDisplayImageReady: onDisplayImageReady,
      );
    } catch (_) {
      return const ScanResolution.failed();
    } finally {
      if (mounted && _captureFeedbackItemId == itemId) {
        setState(() => _captureFeedbackItemId = null);
      }
    }
  }

  Future<void> _finishPhotoRecognition(
    int itemId,
    Future<ScanResolution> pending,
  ) async {
    await pending;
    if (_photoRecognitionItemId == itemId) {
      _photoRecognitionItemId = null;
    }
  }

  Future<void> _toggleFlash() async {
    final camera = _cameraSession;
    if (camera == null) return;
    await camera.toggleFlash();
    if (mounted && identical(camera, _cameraSession)) setState(() {});
  }

  Future<void> _startLibraryScan() async {
    if (_librarySelectionInFlight) return;
    if (!_hasScanQueueCapacity()) return;
    if (!await _resolvePremiumBeforeScan()) return;
    if (!mounted) return;
    if (_scanQuotaExhausted()) {
      unawaited(_openQuotaPaywall());
      return;
    }
    final remainingQueueCapacity = _maxQueueItems - _items.length;
    ref.read(analyticsProvider).track(AnalyticsEvent.imageClick);
    setState(() => _librarySelectionInFlight = true);
    try {
      final permission = await ref
          .read(scanPermissionGatewayProvider)
          .requestGallery();
      if (permission != ScanPermissionResult.granted) {
        if (permission == ScanPermissionResult.permanentlyDenied) {
          await _showPermissionSettings('Photo library');
        }
        return;
      }
      await _closeCamera();
      var selectedCount = 0;
      final scans = await ref
          .read(scanResultSourceProvider)
          .library(
            maxItems: remainingQueueCapacity,
            onSelected: (image, resolution) {
              selectedCount += 1;
              if (mounted) {
                _addScan(
                  resolution,
                  usesCameraFeedback: false,
                  imageBytes: image.bytes,
                  displayImageBytes: image.bytes,
                  imageFileName: image.fileName,
                  retainOnQuotaExhausted: true,
                );
              }
            },
          );
      if (!mounted) return;
      if (selectedCount == 0) {
        for (final scan in scans.take(remainingQueueCapacity)) {
          _addScan(
            scan,
            usesCameraFeedback: false,
            retainOnQuotaExhausted: true,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        _addScan(
          Future.value(const ScanResolution.failed()),
          usesCameraFeedback: false,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _librarySelectionInFlight = false);
        unawaited(_openCamera(previewDelay: _galleryCameraWarmupDuration));
      }
    }
  }

  bool _scanQuotaExhausted() {
    final quota = ref.read(scanQuotaControllerProvider);
    if (ref.read(subscriptionControllerProvider).isPro || quota.unlimited) {
      return false;
    }
    return quota.isServerAuthoritative && quota.remainingScans == 0;
  }

  bool _hasScanQueueCapacity() {
    if (_items.length < _maxQueueItems) return true;
    showKandoTopToast(
      context,
      message: 'Scan queue is full',
      type: KandoTopToastType.info,
    );
    return false;
  }

  Future<bool> _resolvePremiumBeforeScan() async {
    final current = ref.read(subscriptionControllerProvider).premiumState;
    final quota = ref.read(scanQuotaControllerProvider);
    if (current == AppPremiumState.premium || quota.unlimited) return true;
    if (current == AppPremiumState.free &&
        _freeEntitlementConfirmedForLifecycle) {
      return true;
    }
    if (_premiumResolutionInFlight) return false;
    _premiumResolutionInFlight = true;
    try {
      final resolved = await ref
          .read(subscriptionControllerProvider.notifier)
          .refreshEntitlement();
      if (!mounted) return false;
      if (resolved == AppPremiumState.unknown) {
        showKandoTopToast(
          context,
          message:
              ref.read(subscriptionControllerProvider).errorMessage ??
              'Unable to verify Premium access. Please try again.',
          type: KandoTopToastType.failure,
        );
        return false;
      }
      _freeEntitlementConfirmedForLifecycle = resolved == AppPremiumState.free;
      return true;
    } finally {
      _premiumResolutionInFlight = false;
    }
  }

  Future<void> _openQuotaPaywall() async {
    if (!mounted || _quotaPaywallOpen) return;
    _quotaPaywallOpen = true;
    try {
      final result = await context.push<SubscriptionPaywallResult>(
        subscriptionSheetLocation,
      );
      if (!mounted || result == null) return;
      if (result == SubscriptionPaywallResult.premiumRestored) {
        showSubscriptionRestoreResult(
          context,
          type: SubscriptionRestoreResultType.premiumRestored,
        );
      } else {
        showPremiumUnlockedToast(context);
      }
      unawaited(_synchronizePremiumForScan());
    } finally {
      _quotaPaywallOpen = false;
    }
  }

  Future<void> _refreshQuotaAndResumeWaiting() async {
    final wasUnlimited = ref.read(scanQuotaControllerProvider).unlimited;
    final refreshed = await ref
        .read(scanQuotaControllerProvider.notifier)
        .refresh();
    if (!mounted || !refreshed) return;
    final quota = ref.read(scanQuotaControllerProvider);
    if (wasUnlimited &&
        !quota.unlimited &&
        ref.read(subscriptionControllerProvider).premiumState ==
            AppPremiumState.free) {
      _premiumDowngradedToFree = true;
    }
    _resumeWaitingFromServerQuota();
  }

  Future<void> _synchronizePremiumForScan() async {
    if (_entitlementRefreshInFlight) return;
    _entitlementRefreshInFlight = true;
    try {
      await ref
          .read(subscriptionControllerProvider.notifier)
          .synchronizeServerEntitlement();
      if (!mounted) return;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      do {
        await _refreshQuotaAndResumeWaiting();
        final quota = ref.read(scanQuotaControllerProvider);
        final premiumState = ref
            .read(subscriptionControllerProvider)
            .premiumState;
        if (!mounted ||
            quota.unlimited ||
            (_premiumDowngradedToFree &&
                premiumState == AppPremiumState.free &&
                quota.isServerAuthoritative) ||
            DateTime.now().isAfter(deadline)) {
          return;
        }
        if (!_items.any(_isWaitingForCapacity)) return;
        await _waitForEntitlementRefresh();
      } while (mounted && _items.any(_isWaitingForCapacity));
    } finally {
      _entitlementRefreshInFlight = false;
    }
  }

  Future<void> _waitForEntitlementRefresh() {
    final completer = Completer<void>();
    _entitlementRefreshDelay = completer;
    _entitlementRefreshTimer = Timer(const Duration(seconds: 1), () {
      _entitlementRefreshTimer = null;
      _entitlementRefreshDelay = null;
      completer.complete();
    });
    return completer.future;
  }

  bool _isWaitingForCapacity(_ScanItem item) {
    return item.status == _ScanItemStatus.waiting ||
        item.status == _ScanItemStatus.entitlementSync;
  }

  void _resumeWaitingFromServerQuota() {
    if (!mounted) return;
    final quota = ref.read(scanQuotaControllerProvider);
    if (!quota.isServerAuthoritative) return;
    final entitlementSyncItems = _items
        .where((item) => item.status == _ScanItemStatus.entitlementSync)
        .toList();
    final confirmedFree =
        _premiumDowngradedToFree &&
        ref.read(subscriptionControllerProvider).premiumState ==
            AppPremiumState.free;
    if (!quota.unlimited &&
        confirmedFree &&
        quota.remainingScans == 0 &&
        entitlementSyncItems.isNotEmpty) {
      setState(() {
        for (final item in entitlementSyncItems) {
          final index = _items.indexWhere(
            (candidate) => candidate.id == item.id,
          );
          if (index >= 0) {
            _items[index] = item.copyWith(status: _ScanItemStatus.waiting);
          }
        }
      });
      unawaited(_openQuotaPaywall());
      return;
    }
    var capacity = quota.unlimited ? _items.length : quota.remainingScans;
    if (capacity <= 0) return;
    final resumable = _items.where((item) {
      if (item.status == _ScanItemStatus.waiting) return true;
      return item.status == _ScanItemStatus.entitlementSync &&
          (quota.unlimited || confirmedFree);
    }).toList();
    for (final item in resumable) {
      if (capacity <= 0) break;
      capacity -= 1;
      _restartScan(item);
    }
  }

  Future<void> _showPermissionSettings(String name) async {
    if (!mounted || _permissionDialogVisible) return;
    _permissionDialogVisible = true;
    final useCupertino = defaultTargetPlatform == TargetPlatform.iOS;
    final open = useCupertino
        ? await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoTheme(
              key: const Key('scan-permission-cupertino-theme'),
              data: const CupertinoThemeData(
                brightness: Brightness.light,
                primaryColor: CupertinoColors.systemBlue,
              ),
              child: CupertinoAlertDialog(
                title: Text('$name permission required'),
                content: Text('Enable $name access in Settings to continue.'),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () {
                      ref
                          .read(analyticsProvider)
                          .track(AnalyticsEvent.cancelClick);
                      Navigator.pop(context, false);
                    },
                    child: const Text('Cancel'),
                  ),
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => Theme(
              key: const Key('scan-permission-material-theme'),
              data: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: Brightness.light,
                ),
                useMaterial3: true,
              ),
              child: AlertDialog(
                title: Text('$name permission required'),
                content: Text('Enable $name access in Settings to continue.'),
                actions: [
                  TextButton(
                    onPressed: () {
                      ref
                          .read(analyticsProvider)
                          .track(AnalyticsEvent.cancelClick);
                      Navigator.pop(context, false);
                    },
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          );
    _permissionDialogVisible = false;
    if (open == true) {
      await ref.read(scanPermissionGatewayProvider).openSettings();
    }
  }

  Future<void> _retryScan(_ScanItem item) async {
    if (!await _resolvePremiumBeforeScan()) return;
    if (_scanQuotaExhausted()) {
      _replaceItem(item.copyWith(status: _ScanItemStatus.waiting));
      unawaited(_openQuotaPaywall());
      return;
    }
    _restartScan(item);
  }

  void _restartScan(_ScanItem item) {
    _scanStopwatches[item.id] = Stopwatch()..start();
    _replaceItem(
      item.copyWith(
        status: _ScanItemStatus.scanning,
        retainOnQuotaExhausted: true,
      ),
    );
    _startScanTimeline(
      item.id,
      Future.sync(
        () => ref
            .read(scanResultSourceProvider)
            .retry(imageBytes: item.imageBytes, fileName: item.imageFileName),
      ),
    );
  }

  void _dismissScanFeedback() {
    final revealingItem = _items
        .where((item) => item.status == _ScanItemStatus.revealing)
        .firstOrNull;
    if (revealingItem == null) {
      return;
    }
    setState(() => _dismissedFeedbackItemId = revealingItem.id);
  }

  void _removeScan(_ScanItem item, {bool settleInBackground = false}) {
    final pending = _pendingScans[item.id];
    if (settleInBackground && pending != null) {
      pending
        ..removedFromUi = true
        ..revealController?.dispose();
      pending.revealController = null;
    } else {
      _pendingScans.remove(item.id)?.revealController?.dispose();
    }
    setState(() {
      _items.removeWhere((candidate) => candidate.id == item.id);
      if (_selectedReviewItemId == item.id) {
        _selectedReviewItemId = _matchedItems.firstOrNull?.id;
      }
    });
  }

  void _removeScanFromUser(_ScanItem item) {
    final processing =
        item.status == _ScanItemStatus.scanning ||
        item.status == _ScanItemStatus.recognizing ||
        item.status == _ScanItemStatus.revealing;
    if (processing) {
      ref.read(analyticsProvider).track(AnalyticsEvent.cancelClick);
      final stopwatch = _scanStopwatches.remove(item.id);
      stopwatch?.stop();
      _scanDurations[item.id] =
          (_scanDurations[item.id] ?? Duration.zero) +
          (stopwatch?.elapsed ?? Duration.zero);
      _scanResultValues[item.id] = AnalyticsValue.scanFailed;
    } else {
      ref.read(analyticsProvider).track(AnalyticsEvent.deleteClick);
    }
    if (_photoRecognitionItemId == item.id) {
      _photoRecognitionItemId = null;
    }
    if (_captureFeedbackItemId == item.id) {
      _captureFeedbackItemId = null;
    }
    _removeScan(item, settleInBackground: processing);
  }

  Future<void> _searchManually(_ScanItem item) async {
    await _closeCamera();
    if (!mounted) return;

    await context.push<void>('/search?from=scan');
    if (!mounted) return;

    final cachedItem = _items
        .where(
          (candidate) =>
              candidate.id == item.id &&
              candidate.status == _ScanItemStatus.noMatch,
        )
        .firstOrNull;
    if (cachedItem != null) {
      _removeScan(cachedItem);
    }
    unawaited(_openCamera());
  }

  int _addScan(
    Future<ScanResolution> resultFuture, {
    bool usesCameraFeedback = true,
    Uint8List? imageBytes,
    Uint8List? displayImageBytes,
    String? imageFileName,
    bool retainOnQuotaExhausted = false,
  }) {
    final id = _nextScanId;
    _nextScanId += 1;
    _scanStopwatches[id] = Stopwatch()..start();
    setState(() {
      _dismissedFeedbackItemId = null;
      _items.add(
        _ScanItem(
          id: id,
          pictureLabel: 'Scan $id',
          status: _ScanItemStatus.scanning,
          usesCameraFeedback: usesCameraFeedback,
          imageBytes: imageBytes,
          displayImageBytes: displayImageBytes,
          imageFileName: imageFileName,
          retainOnQuotaExhausted: retainOnQuotaExhausted,
        ),
      );
    });
    _startScanTimeline(id, resultFuture);
    return id;
  }

  void _attachScanImage(int itemId, ScanImage image) {
    final item = _items
        .where((candidate) => candidate.id == itemId)
        .firstOrNull;
    if (item == null) return;
    _replaceItem(
      item.copyWith(imageBytes: image.bytes, imageFileName: image.fileName),
    );
  }

  void _attachScanDisplayImage(int itemId, Uint8List bytes) {
    final item = _items
        .where((candidate) => candidate.id == itemId)
        .firstOrNull;
    if (item == null) return;
    _replaceItem(item.copyWith(displayImageBytes: bytes));
  }

  void _startScanTimeline(int itemId, Future<ScanResolution> resultFuture) {
    final token = _nextScanToken;
    _nextScanToken += 1;
    _pendingScans[itemId] = _PendingScan(token);
    _watchScanResolution(itemId, token, resultFuture);

    final timer = Timer(const Duration(seconds: 1), () {
      final existing = _currentItem(
        itemId,
        token,
        expectedStatus: _ScanItemStatus.scanning,
      );
      if (existing == null) {
        return;
      }
      _replaceItem(existing.copyWith(status: _ScanItemStatus.recognizing));
      _scheduleReveal(itemId, token);
    });
    _scanTimers.add(timer);
  }

  void _scheduleReveal(int itemId, int token) {
    final timer = Timer(const Duration(seconds: 1), () {
      final existing = _currentItem(
        itemId,
        token,
        expectedStatus: _ScanItemStatus.recognizing,
      );
      if (existing == null) {
        return;
      }
      _replaceItem(existing.copyWith(status: _ScanItemStatus.revealing));
      _startReveal(itemId, token);
    });
    _scanTimers.add(timer);
  }

  void _startReveal(int itemId, int token) {
    final pending = _pendingScans[itemId];
    if (pending == null || pending.token != token) {
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: _revealTimelineDuration,
    );
    pending.revealController = controller;
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      controller.value = 1;
      _markRevealTimelineFinished(itemId, token);
    } else {
      unawaited(_waitForRevealTimeline(itemId, token, controller));
    }
  }

  Future<void> _waitForRevealTimeline(
    int itemId,
    int token,
    AnimationController controller,
  ) async {
    try {
      await controller.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    _markRevealTimelineFinished(itemId, token);
  }

  void _markRevealTimelineFinished(int itemId, int token) {
    final existing = _currentItem(
      itemId,
      token,
      expectedStatus: _ScanItemStatus.revealing,
    );
    if (existing == null) {
      return;
    }
    final pending = _pendingScans[itemId];
    if (pending == null || pending.token != token) {
      return;
    }
    pending.revealTimelineFinished = true;
    _completeScanIfReady(itemId, token);
  }

  Future<void> _watchScanResolution(
    int itemId,
    int token,
    Future<ScanResolution> resultFuture,
  ) async {
    ScanResolution resolution;
    try {
      resolution = await resultFuture;
    } catch (_) {
      resolution = const ScanResolution.failed();
    }
    final pending = _pendingScans[itemId];
    if (pending == null || pending.token != token) {
      return;
    }
    if (!pending.removedFromUi) {
      final stopwatch = _scanStopwatches.remove(itemId);
      stopwatch?.stop();
      _scanDurations[itemId] =
          (_scanDurations[itemId] ?? Duration.zero) +
          (stopwatch?.elapsed ?? Duration.zero);
      _scanResultValues[itemId] = switch (resolution.kind) {
        ScanResolutionKind.matched => AnalyticsValue.scanSuccess,
        ScanResolutionKind.noMatch => AnalyticsValue.scanNotFound,
        ScanResolutionKind.failed ||
        ScanResolutionKind.cancelled ||
        ScanResolutionKind.quotaExhausted ||
        ScanResolutionKind.entitlementSyncRequired => AnalyticsValue.scanFailed,
      };
    }

    if (!mounted) {
      return;
    }
    final serverQuota = resolution.quota;
    if (serverQuota != null) {
      ref
          .read(scanQuotaControllerProvider.notifier)
          .applyServerQuota(serverQuota);
    }
    if (pending.removedFromUi) {
      _pendingScans.remove(itemId)?.revealController?.dispose();
      if (serverQuota != null) {
        _resumeWaitingFromServerQuota();
      } else {
        unawaited(_refreshQuotaAndResumeWaiting());
      }
      return;
    }
    if (resolution.kind == ScanResolutionKind.cancelled) {
      _pendingScans.remove(itemId)?.revealController?.dispose();
      setState(() {
        _items.removeWhere((item) => item.id == itemId);
      });
      return;
    }
    if (resolution.kind == ScanResolutionKind.quotaExhausted) {
      _pendingScans.remove(itemId)?.revealController?.dispose();
      final item = _items.where((item) => item.id == itemId).firstOrNull;
      if (item?.retainOnQuotaExhausted == true) {
        _replaceItem(
          item!.copyWith(
            status: _ScanItemStatus.waiting,
            imageBytes: resolution.imageBytes,
            displayImageBytes: resolution.displayImageBytes,
            imageFileName: resolution.imageFileName,
          ),
        );
      } else {
        setState(() => _items.removeWhere((item) => item.id == itemId));
      }
      unawaited(_openQuotaPaywall());
      return;
    }
    if (resolution.kind == ScanResolutionKind.entitlementSyncRequired) {
      _pendingScans.remove(itemId)?.revealController?.dispose();
      final item = _items.where((item) => item.id == itemId).firstOrNull;
      if (item != null) {
        _replaceItem(
          item.copyWith(
            status: _ScanItemStatus.entitlementSync,
            imageBytes: resolution.imageBytes,
            displayImageBytes: resolution.displayImageBytes,
            imageFileName: resolution.imageFileName,
          ),
        );
      }
      unawaited(_synchronizePremiumForScan());
      return;
    }
    pending.resolution = resolution;
    _completeScanIfReady(itemId, token);
    if (serverQuota != null) {
      _resumeWaitingFromServerQuota();
    } else if (resolution.kind == ScanResolutionKind.failed) {
      unawaited(_refreshQuotaAndResumeWaiting());
    }
  }

  _ScanItem? _currentItem(
    int itemId,
    int token, {
    _ScanItemStatus? expectedStatus,
  }) {
    if (!mounted) {
      return null;
    }
    final pending = _pendingScans[itemId];
    if (pending == null || pending.token != token) {
      return null;
    }
    final item = _items.where((item) => item.id == itemId).firstOrNull;
    if (item == null ||
        (expectedStatus != null && item.status != expectedStatus)) {
      return null;
    }
    return item;
  }

  void _completeScanIfReady(int itemId, int token) {
    final item = _currentItem(
      itemId,
      token,
      expectedStatus: _ScanItemStatus.revealing,
    );
    final pending = _pendingScans[itemId];
    if (item == null ||
        pending == null ||
        pending.token != token ||
        !pending.revealTimelineFinished ||
        pending.resolution == null) {
      return;
    }

    final resolution = pending.resolution!;
    final status = switch (resolution.kind) {
      ScanResolutionKind.matched when resolution.matchName != null =>
        _ScanItemStatus.matched,
      ScanResolutionKind.matched ||
      ScanResolutionKind.failed => _ScanItemStatus.failed,
      ScanResolutionKind.noMatch => _ScanItemStatus.noMatch,
      ScanResolutionKind.cancelled => _ScanItemStatus.failed,
      ScanResolutionKind.quotaExhausted => _ScanItemStatus.waiting,
      ScanResolutionKind.entitlementSyncRequired =>
        _ScanItemStatus.entitlementSync,
    };
    final match = status == _ScanItemStatus.matched
        ? _ScanMatch(
            scanId: resolution.scanId!,
            cardRef: resolution.cardRef!,
            name: resolution.matchName!,
            candidates: [
              for (
                var index = 0;
                index < resolution.candidates.length;
                index += 1
              )
                _ScanCandidate(
                  cardRef: index < resolution.candidateCardRefs.length
                      ? resolution.candidateCardRefs[index]
                      : resolution.cardRef!,
                  name: resolution.candidates[index],
                ),
            ],
          )
        : null;

    final completedPending = _pendingScans.remove(itemId);
    setState(() {
      for (var index = 0; index < _items.length; index += 1) {
        if (_items[index].id == itemId) {
          _items[index] = item.copyWith(
            status: status,
            match: match,
            imageBytes: resolution.imageBytes,
            displayImageBytes: resolution.displayImageBytes,
            imageFileName: resolution.imageFileName,
          );
          break;
        }
      }
      if (_dismissedFeedbackItemId == itemId) {
        _dismissedFeedbackItemId = null;
      }
    });
    if (match != null) {
      unawaited(_loadScanCards(match));
    }
    completedPending?.revealController?.dispose();
  }

  Future<void> _loadScanCards(_ScanMatch match) async {
    try {
      final cards = await ref.read(scanReviewRepositoryProvider).loadCards([
        for (final candidate in match.candidates) candidate.cardRef,
      ]);
      if (!mounted) return;
      setState(() => _reviewCards = {..._reviewCards, ...cards});
    } on Exception {
      // Price metadata is supplemental; review retries the same load explicitly.
    }
  }

  void _replaceItem(_ScanItem next) {
    setState(() {
      for (var index = 0; index < _items.length; index += 1) {
        if (_items[index].id == next.id) {
          _items[index] = next;
          return;
        }
      }
    });
  }

  Future<void> _openReview([int? itemId]) async {
    if (_openingReview || _reviewing || !_canReview) {
      return;
    }
    final items = _matchedItems;
    final cachedCards = Map<String, ScanReviewCard>.from(_reviewCards);
    final cardRefs = [
      for (final item in items)
        for (final candidate in item.match!.candidates) candidate.cardRef,
    ];
    final missingCardRefs = cardRefs
        .where((cardRef) => !cachedCards.containsKey(cardRef))
        .toList();
    setState(() => _openingReview = true);
    try {
      final repository = ref.read(scanReviewRepositoryProvider);
      final results = await Future.wait<Object>([
        repository.loadTarget(
          preferredFolderId: ref.read(selectedPortfolioFolderProvider),
        ),
        missingCardRefs.isEmpty
            ? Future.value(const <String, ScanReviewCard>{})
            : repository.loadCards(missingCardRefs),
      ]);
      final target = results[0] as ScanReviewTarget;
      final cards = {
        ...cachedCards,
        ...results[1] as Map<String, ScanReviewCard>,
      };
      final selectedReviewItemId = itemId ?? items.firstOrNull?.id;
      if (selectedReviewItemId == null) {
        throw const _ScanReviewLoadException();
      }
      final drafts = <int, _ScanCollectionDraft>{};
      for (final item in items) {
        final cardRef = item.match?.cardRef;
        final card = cardRef == null ? null : cards[cardRef];
        if (card == null) {
          throw const _ScanReviewLoadException();
        }
        drafts[item.id] = _initialReviewDraft(target, card);
      }
      if (mounted && _openingReview) {
        setState(() {
          _openingReview = false;
          _reviewing = true;
          _selectedReviewItemId = selectedReviewItemId;
          _reviewTarget = target;
          _reviewCards = cards;
          _reviewFormError = null;
          _reviewDrafts
            ..clear()
            ..addAll(drafts);
        });
        unawaited(_closeCamera());
        final selected = items
            .where((item) => item.id == _selectedReviewItemId)
            .firstOrNull;
        final selectedCard = selected == null
            ? null
            : cards[selected.match!.cardRef];
        ref
            .read(analyticsProvider)
            .track(
              AnalyticsEvent.reviewMatchesView,
              properties: {
                AnalyticsProperty.collectionType:
                    AnalyticsValue.collectionPortfolio,
                AnalyticsProperty.ipType: analyticsIpType(selectedCard?.game),
              },
            );
      }
    } catch (_) {
      _failReviewLoad();
    } finally {
      if (mounted && _openingReview) {
        setState(() => _openingReview = false);
      }
    }
  }

  void _closeReview() {
    if (_savingReview || !_reviewing) return;
    setState(() {
      _reviewing = false;
      _reviewFormError = null;
    });
    unawaited(_openCamera());
  }

  void _failReviewLoad() {
    if (!mounted) return;
    setState(() {
      _openingReview = false;
      _reviewing = false;
      _selectedReviewItemId = null;
      _reviewTarget = null;
      _reviewDrafts.clear();
      _reviewFormError = null;
    });
    showKandoTopFailureToast(context);
  }

  Future<void> _addSelectedItem() async {
    final selectedId = _selectedReviewItemId;
    final item = _matchedItems
        .where((candidate) => candidate.id == selectedId)
        .firstOrNull;
    if (item == null || _reviewTarget == null || _savingReview) {
      return;
    }
    _trackCollectionItemAdd(item);
    _reportScanResult(item.id);

    final input = _reviewInputFor(item);
    if (input == null) {
      showKandoTopToast(
        context,
        message: _reviewFormError ?? genericFailureToastText,
        type: KandoTopToastType.failure,
      );
      return;
    }

    setState(() => _savingReviewAction = _ScanReviewSaveAction.single);
    try {
      await ref
          .read(scanReviewRepositoryProvider)
          .addToPortfolio(scanId: item.match!.scanId, item: input);
      if (!mounted) return;
      await _completeSelectedItemAddition(item);
    } on ScanApiException catch (error) {
      if (error.code == 'CONFLICT' &&
          error.message == 'Scan is already confirmed.') {
        if (mounted) await _completeSelectedItemAddition(item);
      } else if (mounted) {
        showKandoTopToast(
          context,
          message: error.code == duplicateCollectionItemErrorCode
              ? duplicateCollectionItemMessage
              : error.message,
          type: KandoTopToastType.failure,
        );
      }
    } on Exception {
      if (mounted) showKandoTopFailureToast(context);
    } finally {
      if (mounted) setState(() => _savingReviewAction = null);
    }
  }

  Future<void> _completeSelectedItemAddition(_ScanItem item) async {
    setState(() {
      _savingReviewAction = null;
      _finishingReview = true;
    });
    showKandoCenteredSuccessToast(
      context,
      message: portfolioCardAddedToastText,
    );
    await Future<void>.delayed(kandoCenteredSuccessToastDuration);
    if (!mounted) return;

    setState(() {
      _reviewing = false;
      _items.removeWhere((candidate) => candidate.id == item.id);
      _selectedReviewItemId = null;
      _reviewTarget = null;
      _reviewCards = const {};
      _reviewDrafts.remove(item.id);
      _reviewFormError = null;
      _finishingReview = false;
    });
    unawaited(_openCamera());
    _refreshPortfolioSurfaces();
  }

  Future<void> _addAllMatchedItems() async {
    final matchedItems = _matchedItems;
    if (matchedItems.isEmpty || _reviewTarget == null || _savingReview) {
      return;
    }

    for (final item in matchedItems) {
      _trackCollectionItemAdd(item);
      _reportScanResult(item.id);
    }

    final inputs = <int, ScanCollectionItemInput>{};
    for (final item in matchedItems) {
      final input = _reviewInputFor(item);
      if (input == null) return;
      inputs[item.id] = input;
    }

    setState(() => _savingReviewAction = _ScanReviewSaveAction.all);
    final addedIds = <int>{};
    var failed = false;
    var duplicate = false;
    for (final item in matchedItems) {
      try {
        await ref
            .read(scanReviewRepositoryProvider)
            .addToPortfolio(scanId: item.match!.scanId, item: inputs[item.id]!);
        addedIds.add(item.id);
      } on ScanApiException catch (error) {
        duplicate = duplicate || error.code == duplicateCollectionItemErrorCode;
        failed = true;
      } on Exception {
        failed = true;
      }
    }

    if (!mounted) return;
    final allAdded = addedIds.length == matchedItems.length;
    setState(() {
      _savingReviewAction = null;
      _finishingReview = allAdded;
    });
    if (allAdded) {
      _refreshPortfolioSurfaces();
      showKandoCenteredSuccessToast(
        context,
        message: portfolioCardsAddedToastText(addedIds.length),
      );
      await Future<void>.delayed(kandoCenteredSuccessToastDuration);
      if (!mounted) return;
    }

    setState(() {
      _items.removeWhere((item) => addedIds.contains(item.id));
      for (final itemId in addedIds) {
        _reviewDrafts.remove(itemId);
      }
      final remaining = _matchedItems;
      _reviewing = remaining.isNotEmpty;
      _selectedReviewItemId = remaining.firstOrNull?.id;
      if (!_reviewing) {
        _reviewTarget = null;
        _reviewCards = const {};
      }
      _reviewFormError = null;
      _savingReviewAction = null;
      _finishingReview = false;
    });
    if (addedIds.isNotEmpty && !allAdded) {
      _refreshPortfolioSurfaces();
      showKandoCenteredSuccessToast(
        context,
        message: portfolioCardsAddedToastText(addedIds.length),
      );
    }
    if (!_reviewing) unawaited(_openCamera());
    if (failed) {
      if (duplicate) {
        showKandoTopToast(
          context,
          message: duplicateCollectionItemMessage,
          type: KandoTopToastType.failure,
        );
      } else {
        showKandoTopFailureToast(context);
      }
    }
  }

  void _selectReviewItem(_ScanItem item) {
    setState(() {
      _selectedReviewItemId = item.id;
      _reviewFormError = null;
    });
  }

  void _selectReviewCandidate(_ScanItem item, _ScanCandidate candidate) {
    final card = _reviewCards[candidate.cardRef];
    if (card == null || candidate.cardRef == item.match?.cardRef) return;
    ref.read(analyticsProvider).track(AnalyticsEvent.topMatchesClick);
    setState(() {
      for (var index = 0; index < _items.length; index += 1) {
        if (_items[index].id == item.id) {
          _items[index] = item.copyWith(match: item.match!.select(candidate));
          break;
        }
      }
      final draft = _reviewDrafts[item.id];
      if (draft != null) {
        _reviewDrafts[item.id] = draft.copyWith(
          language: _reviewOptionOrDefault(
            card.language,
            card.collectionLanguageOptions,
          ),
          finish: _reviewOptionOrDefault(
            card.finish,
            card.collectionFinishOptions,
          ),
        );
      }
      _reviewFormError = null;
    });
  }

  void _updateReviewDraft(int itemId, _ScanCollectionDraft draft) {
    setState(() {
      _reviewDrafts[itemId] = draft;
      _reviewFormError = null;
    });
  }

  ScanCollectionItemInput? _reviewInputFor(_ScanItem item) {
    final draft = _reviewDrafts[item.id];
    if (draft == null) return null;
    final quantity = int.tryParse(draft.quantityText.trim());
    if (quantity == null || quantity < 1) {
      _showReviewValidation(
        item.id,
        'Quantity must be a whole number of 1 or more.',
      );
      return null;
    }
    final priceText = draft.purchasePriceText.trim();
    final purchasePrice = priceText.isEmpty ? null : double.tryParse(priceText);
    if (priceText.isNotEmpty && (purchasePrice == null || purchasePrice < 0)) {
      _showReviewValidation(item.id, 'Please enter a valid price.');
      return null;
    }
    if (draft.notes.length > 500) {
      _showReviewValidation(item.id, 'Notes must be 500 characters or less.');
      return null;
    }
    final grade = draft.isRaw ? null : double.tryParse(draft.grade);
    if (!draft.isRaw && grade == null) {
      _showReviewValidation(item.id, 'Please select a grade.');
      return null;
    }
    return ScanCollectionItemInput(
      folderId: draft.folderId,
      cardRef: item.match!.cardRef,
      quantity: quantity,
      grader: draft.grader,
      condition: draft.isRaw ? draft.condition : null,
      grade: grade,
      language: draft.language,
      finish: draft.finish,
      purchasePrice: purchasePrice,
      purchaseCurrency: purchasePrice == null ? null : 'USD',
      notes: draft.notes.trim().isEmpty ? null : draft.notes.trim(),
    );
  }

  void _showReviewValidation(int itemId, String message) {
    setState(() {
      _selectedReviewItemId = itemId;
      _reviewFormError = message;
    });
  }

  Future<void> _deleteReviewItem(_ScanItem item) async {
    ref.read(analyticsProvider).track(AnalyticsEvent.deleteClick);
    if (!await _confirmReviewDelete(all: false)) return;
    _removeReviewItems({item.id});
  }

  Future<void> _deleteAllReviewItems() async {
    ref.read(analyticsProvider).track(AnalyticsEvent.deleteClick);
    if (!await _confirmReviewDelete(all: true)) return;
    _removeReviewItems(_matchedItems.map((item) => item.id).toSet());
  }

  Future<bool> _confirmReviewDelete({required bool all}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(all ? 'Delete all cards?' : 'Delete card?'),
        content: Text(
          all
              ? 'This action will remove all reviewed scans and cannot be undone.'
              : 'This action will remove this reviewed scan and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(analyticsProvider).track(AnalyticsEvent.cancelClick);
              Navigator.of(context).pop(false);
            },
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(analyticsProvider)
                  .track(AnalyticsEvent.deleteConfirmClick);
              Navigator.of(context).pop(true);
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _removeReviewItems(Set<int> itemIds) {
    setState(() {
      _items.removeWhere((item) => itemIds.contains(item.id));
      for (final itemId in itemIds) {
        _reviewDrafts.remove(itemId);
      }
      final remaining = _matchedItems;
      _selectedReviewItemId = remaining.firstOrNull?.id;
      _reviewing = remaining.isNotEmpty;
      _reviewFormError = null;
      if (!_reviewing) {
        _reviewTarget = null;
        _reviewCards = const {};
      }
    });
    if (!_reviewing) unawaited(_openCamera());
  }

  void _refreshPortfolioSurfaces() {
    ref.invalidate(homeControllerProvider);
    ref.invalidate(collectionControllerProvider);
    ref.invalidate(searchControllerProvider);
  }

  Future<void> _requestExitScan() async {
    if (_openingReview || _savingReview) {
      return;
    }
    if (!_hasUnsavedScanResults) {
      if (mounted) {
        _reportAllScanResults();
        context.go('/home');
      }
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Exit scan result?'),
        content: const Text('Your scanned card has not been collected yet.'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () {
                  ref.read(analyticsProvider).track(AnalyticsEvent.cancelClick);
                  Navigator.of(context).pop(false);
                },
                child: const Text('NO, STAY HERE'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('EXIT'),
              ),
            ],
          ),
        ],
      ),
    );
    if (mounted && shouldExit == true) {
      _reportAllScanResults();
      context.go('/home');
    }
  }

  void _handleClosePressed() {
    ref.read(analyticsProvider).track(AnalyticsEvent.scanCloseClick);
    _requestExitScan();
  }

  void _trackCollectionItemAdd(_ScanItem item) {
    final draft = _reviewDrafts[item.id];
    final card = _reviewCards[item.match?.cardRef];
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvent.collectionItemAddClick,
          properties: {
            AnalyticsProperty.ipType: analyticsIpType(card?.game),
            AnalyticsProperty.gradeType: draft?.isRaw == false
                ? AnalyticsValue.gradeGraded
                : AnalyticsValue.gradeNormal,
            AnalyticsProperty.entrySource: AnalyticsValue.sourceScan,
          },
          debounceKey: 'scan-${item.id}',
        );
  }

  void _reportAllScanResults() {
    final itemIds = <int>{
      ..._scanDurations.keys,
      ..._scanStopwatches.keys,
      ..._scanResultValues.keys,
    };
    for (final itemId in itemIds) {
      _reportScanResult(itemId);
    }
  }

  void _reportScanResult(int itemId) {
    if (!_reportedScanResultIds.add(itemId)) return;
    final duration =
        _scanDurations[itemId] ??
        _scanStopwatches[itemId]?.elapsed ??
        Duration.zero;
    final wholeSeconds = duration.inMilliseconds <= 0
        ? 0
        : (duration.inMilliseconds / 1000).ceil();
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvent.scanResults,
          properties: {
            AnalyticsProperty.timing: '${wholeSeconds}s',
            AnalyticsProperty.scanResults:
                _scanResultValues[itemId] ?? AnalyticsValue.scanFailed,
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppPremiumState>(
      subscriptionControllerProvider.select((value) => value.premiumState),
      (previous, next) {
        if (previous == AppPremiumState.premium &&
            next == AppPremiumState.free) {
          _freeEntitlementConfirmedForLifecycle = true;
          _premiumDowngradedToFree = true;
          unawaited(_refreshQuotaAndResumeWaiting());
        }
      },
    );
    final currency = ref.watch(selectedCurrencyProvider);
    final isPro = ref.watch(
      subscriptionControllerProvider.select((value) => value.isPro),
    );
    final quota = ref.watch(scanQuotaControllerProvider);
    final hasPremiumAccess = isPro || quota.unlimited;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_reviewing) {
            _closeReview();
          } else {
            _requestExitScan();
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10100B),
        body: _reviewing
            ? Stack(
                children: [
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: _KeyboardDismissOnPointerDown(
                        child: _ReviewMatches(
                          items: _matchedItems,
                          selectedItemId: _selectedReviewItemId,
                          target: _reviewTarget,
                          cards: _reviewCards,
                          drafts: _reviewDrafts,
                          formError: _reviewFormError,
                          saving: _savingReview,
                          savingAction: _savingReviewAction,
                          keyboardVisible: keyboardVisible,
                          currency: currency,
                          onCollapse: _closeReview,
                          onSelectItem: _selectReviewItem,
                          onSelectCandidate: _selectReviewCandidate,
                          onUpdateDraft: _updateReviewDraft,
                          onAddThisCard: _addSelectedItem,
                          onAddAllCards: _addAllMatchedItems,
                          onDeleteItem: _deleteReviewItem,
                          onDeleteAll: _deleteAllReviewItems,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    height: MediaQuery.paddingOf(context).top + 24,
                    child: GestureDetector(
                      key: const Key('scan-review-collapse-area'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeReview,
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  _ScanCameraView(
                    cameraPreview: _cameraSession?.buildPreview(),
                    flashEnabled: _cameraSession?.flashEnabled ?? false,
                    items: _items,
                    canReview: _canReview,
                    capturingPhoto: _captureFeedbackItemId != null,
                    recognizing: _isRecognizing,
                    revealing: _isRevealing,
                    showRevealingFeedback: _showRevealingFeedback,
                    captureAnimation: _captureController,
                    cards: _reviewCards,
                    currency: currency,
                    remainingScans: hasPremiumAccess
                        ? null
                        : quota.remainingScans,
                    onClosePressed: _handleClosePressed,
                    onFlashPressed: _cameraSession == null
                        ? null
                        : _toggleFlash,
                    onSearchPressed: () => context.go('/search'),
                    onUpgradePressed: () async {
                      final result = await context
                          .push<SubscriptionPaywallResult>(
                            subscriptionPageLocation(
                              source: 'scan',
                              entrySource: 'scan_pro_card',
                            ),
                          );
                      if (!mounted || !context.mounted || result == null) {
                        return;
                      }
                      if (result == SubscriptionPaywallResult.premiumRestored) {
                        showSubscriptionRestoreResult(
                          context,
                          type: SubscriptionRestoreResultType.premiumRestored,
                        );
                      }
                      unawaited(_synchronizePremiumForScan());
                    },
                    onPhotoPressed: _startPhotoScan,
                    onLibraryPressed: _startLibraryScan,
                    onDismissScanFeedback: _dismissScanFeedback,
                    onReviewPressed: _openReview,
                    onReviewItem: _openReview,
                    onRetryItem: _retryScan,
                    onDeleteItem: _removeScanFromUser,
                    onSearchItem: (item) {
                      if (item.status == _ScanItemStatus.waiting) {
                        unawaited(_openQuotaPaywall());
                      } else {
                        unawaited(_searchManually(item));
                      }
                    },
                  ),
                  if (_openingReview)
                    const Positioned.fill(
                      child: ColoredBox(
                        key: Key('scan-review-loading'),
                        color: Color(0x66000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ScanCameraView extends StatelessWidget {
  const _ScanCameraView({
    required this.cameraPreview,
    required this.flashEnabled,
    required this.items,
    required this.canReview,
    required this.capturingPhoto,
    required this.recognizing,
    required this.revealing,
    required this.showRevealingFeedback,
    required this.captureAnimation,
    required this.cards,
    required this.currency,
    required this.remainingScans,
    required this.onClosePressed,
    required this.onFlashPressed,
    required this.onSearchPressed,
    required this.onUpgradePressed,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
    required this.onDismissScanFeedback,
    required this.onReviewPressed,
    required this.onReviewItem,
    required this.onRetryItem,
    required this.onDeleteItem,
    required this.onSearchItem,
  });

  final Widget? cameraPreview;
  final bool flashEnabled;
  final List<_ScanItem> items;

  final bool canReview;
  final bool capturingPhoto;
  final bool recognizing;
  final bool revealing;
  final bool showRevealingFeedback;
  final Animation<double> captureAnimation;
  final Map<String, ScanReviewCard> cards;
  final AppCurrency currency;
  final int? remainingScans;
  final VoidCallback onClosePressed;
  final VoidCallback? onFlashPressed;
  final VoidCallback onSearchPressed;
  final VoidCallback onUpgradePressed;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback onDismissScanFeedback;
  final VoidCallback onReviewPressed;
  final ValueChanged<int?> onReviewItem;
  final ValueChanged<_ScanItem> onRetryItem;
  final ValueChanged<_ScanItem> onDeleteItem;
  final ValueChanged<_ScanItem> onSearchItem;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final geometry = _scanViewfinderGeometry(viewport, padding);
    final safeTop = padding.top;
    final topInset = safeTop + 10;
    return Stack(
      children: [
        if (cameraPreview != null)
          Positioned.fill(
            child: KeyedSubtree(
              key: const Key('scan-live-camera-preview'),
              child: cameraPreview!,
            ),
          ),
        if (recognizing)
          Positioned.fill(child: _FigmaRecognizingOverlay(geometry: geometry))
        else if (revealing)
          Positioned.fill(child: _FigmaRevealingOverlay(geometry: geometry))
        else ...[
          Positioned.fill(
            child: ColoredBox(
              key: const Key('scan-figma-camera-overlay'),
              color: const Color(0x1A0D0F08),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: geometry.radialAlignment(viewport),
                  radius: 0.86,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0D0F08).withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
        ],
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: safeTop,
          child: const ColoredBox(
            key: Key('scan-figma-top-safe-band'),
            color: Color(0xFF10100B),
          ),
        ),
        Positioned.fromRect(
          rect: geometry.rect,
          child: _ViewfinderCorners(
            size: geometry.rect.size,
            focusFrameShadow: recognizing || revealing,
          ),
        ),
        if (capturingPhoto) ...[
          Positioned.fromRect(
            rect: geometry.rect,
            child: _FigmaScanningLine(
              key: Key('scan-figma-scanning-line'),
              animation: captureAnimation,
            ),
          ),
        ],
        if (items.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 126 + padding.bottom,
            child: _ScanResults(
              items: items,
              cards: cards,
              currency: currency,
              showRevealingFeedback: showRevealingFeedback,
              onDismissRevealing: onDismissScanFeedback,
              onReviewItem: onReviewItem,
              onRetryItem: onRetryItem,
              onDeleteItem: onDeleteItem,
              onSearchPressed: onSearchItem,
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 22,
          child: SafeArea(
            top: false,
            child: _ScanBottomControls(
              canReview: canReview,
              onPhotoPressed: onPhotoPressed,
              onLibraryPressed: onLibraryPressed,
              onReviewPressed: onReviewPressed,
            ),
          ),
        ),
        Positioned(
          key: const Key('scan-figma-top-controls'),
          top: topInset,
          left: 8,
          right: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ScanTopBar(
                onClosePressed: onClosePressed,
                onFlashPressed: onFlashPressed,
                flashEnabled: flashEnabled,
                onSearchPressed: onSearchPressed,
              ),
              const SizedBox(height: 2),
              const _AlignCardPill(),
              if (remainingScans != null) ...[
                const SizedBox(height: 6),
                _ScanQuotaPill(
                  remainingScans: remainingScans!,
                  onPressed: onUpgradePressed,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ScanTopBar extends StatelessWidget {
  const _ScanTopBar({
    required this.onClosePressed,
    required this.onFlashPressed,
    required this.flashEnabled,
    required this.onSearchPressed,
  });

  final VoidCallback onClosePressed;
  final VoidCallback? onFlashPressed;
  final bool flashEnabled;
  final VoidCallback onSearchPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('scan-figma-top-bar'),
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              key: const Key('scan-figma-close-button'),
              tooltip: 'Close Scan',
              onPressed: onClosePressed,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                minimumSize: const Size(30, 30),
                maximumSize: const Size(30, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: SvgPicture.asset(
                'assets/scan/close.svg',
                key: const Key('scan-figma-close-icon'),
                width: 14,
                height: 14,
              ),
            ),
          ),
          IconButton(
            key: const Key('scan-figma-flash-button'),
            tooltip: flashEnabled ? 'Turn flash off' : 'Turn flash on',
            onPressed: onFlashPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 25, height: 25),
            style: IconButton.styleFrom(
              minimumSize: const Size(25, 25),
              maximumSize: const Size(25, 25),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: flashEnabled
                  ? const Color(0xFFF0FE6F)
                  : const Color(0xFF222222).withValues(alpha: 0.82),
              disabledBackgroundColor: const Color(
                0xFF222222,
              ).withValues(alpha: 0.82),
            ),
            icon: SvgPicture.asset(
              'assets/scan/flash.svg',
              key: const Key('scan-figma-flash-icon'),
              width: 9,
              height: 15,
              colorFilter: flashEnabled
                  ? const ColorFilter.mode(Color(0xFF10100B), BlendMode.srcIn)
                  : null,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              key: const Key('scan-figma-search-button'),
              tooltip: 'Search Cards',
              onPressed: onSearchPressed,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                minimumSize: const Size(30, 30),
                maximumSize: const Size(30, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: SvgPicture.asset(
                'assets/scan/search.svg',
                key: const Key('scan-figma-search-icon'),
                width: 18,
                height: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlignCardPill extends StatelessWidget {
  const _AlignCardPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: const Color(0xFF222222).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1A394E2C)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/scan/align.svg',
            key: const Key('scan-figma-align-icon'),
            width: 15,
            height: 15,
          ),
          const SizedBox(width: 12),
          const Text(
            'ALIGN CARD HERE',
            style: TextStyle(
              color: Color(0xFFE4E3D3),
              fontSize: 13,
              height: 16 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanQuotaPill extends StatelessWidget {
  const _ScanQuotaPill({required this.remainingScans, required this.onPressed});

  final int remainingScans;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('scan-free-quota-pill'),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            offset: Offset(0, 23.585),
            blurRadius: 23.585,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  key: const Key('scan-free-quota-pro-badge'),
                  dimension: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/scan/pro_badge.svg',
                        width: 24,
                        height: 24,
                      ),
                      const Text(
                        'PRO',
                        style: TextStyle(
                          color: KandoColors.elevatedSurface,
                          fontFamily: 'Fraunces',
                          fontSize: 7,
                          fontWeight: FontWeight.w600,
                          height: 20 / 7,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  key: const Key('scan-free-quota-copy'),
                  width: 161,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$remainingScans scans remaining',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE4E3D3),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 16 / 13,
                          letterSpacing: 0,
                        ),
                      ),
                      const Text(
                        'Tap to get unlimited scans',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFE4E3D3),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 16 / 13,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FigmaScanningLine extends StatelessWidget {
  const _FigmaScanningLine({required this.animation, super.key});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: animation,
              child: SizedBox(
                width: constraints.maxWidth,
                height: 4,
                child: const CustomPaint(
                  key: Key('scan-figma-scanning-line-canvas'),
                  painter: _FigmaScanningLinePainter(),
                ),
              ),
              builder: (context, child) {
                final progress = Curves.easeInOut.transform(animation.value);
                return Transform.translate(
                  offset: Offset(0, (constraints.maxHeight - 4) * progress),
                  child: child,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FigmaScanningLinePainter extends CustomPainter {
  const _FigmaScanningLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final lineRect = Offset.zero & size;
    final shader = const LinearGradient(
      colors: [Color(0x00F1FE70), Color(0xB3F0FE6F), Color(0x00F1FE70)],
    ).createShader(lineRect);
    final glowPaint = Paint()
      ..shader = shader
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7.5);
    canvas.drawRect(lineRect, glowPaint);
    canvas.drawRect(lineRect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _FigmaScanningLinePainter oldDelegate) => false;
}

class _ScanBottomControls extends StatelessWidget {
  const _ScanBottomControls({
    required this.canReview,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
    required this.onReviewPressed,
  });

  final bool canReview;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback onReviewPressed;

  @override
  Widget build(BuildContext context) {
    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _ScanSideAction(
          label: 'GALLERY',
          tooltip: 'Choose from Library',
          width: 72,
          icon: SvgPicture.asset(
            'assets/scan/gallery.svg',
            key: const Key('scan-figma-gallery-icon'),
            width: 20,
            height: 20,
          ),
          onPressed: onLibraryPressed,
        ),
        Tooltip(
          message: 'Take Photo',
          child: InkResponse(
            onTap: onPhotoPressed,
            customBorder: const CircleBorder(),
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x14FFFFFF), width: 4),
              ),
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x66FFFFFF), blurRadius: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
        _ScanDoneAction(enabled: canReview, onPressed: onReviewPressed),
      ],
    );
    return Padding(padding: EdgeInsets.zero, child: controls);
  }
}

class _ScanDoneAction extends StatelessWidget {
  const _ScanDoneAction({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Review completed scan',
      child: InkWell(
        key: const Key('scan-done-action'),
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const Key('scan-figma-done-background'),
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFFF0FE6F)
                      : const Color(0x7A222222),
                  shape: BoxShape.circle,
                  border: enabled
                      ? null
                      : Border.all(color: const Color(0x1A394E2C)),
                  boxShadow: enabled
                      ? const [
                          BoxShadow(color: Color(0x66F1FE70), blurRadius: 7.5),
                        ]
                      : null,
                ),
                child: Opacity(
                  opacity: enabled ? 1 : 0.4,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      enabled
                          ? const Color(0xFF394E2C)
                          : const Color(0xFFC7C8B0),
                      BlendMode.srcIn,
                    ),
                    child: SvgPicture.asset(
                      'assets/scan/done.svg',
                      key: const Key('scan-figma-done-icon'),
                      width: 16.3,
                      height: 12.025,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 16,
                child: Text(
                  'DONE',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xFFEEECD8)
                        : const Color(0x66EEECD8),
                    fontSize: 13,
                    height: 16 / 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanSideAction extends StatelessWidget {
  const _ScanSideAction({
    required this.label,
    required this.tooltip,
    required this.width,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final double width;
  final Widget icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: tooltip,
            child: IconButton(
              onPressed: onPressed,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF222222),
                foregroundColor: const Color(0xFFEEECD8),
                fixedSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: icon,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 16,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                color: Color(0xFFEEECD8),
                fontSize: 13,
                height: 16 / 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaRecognizingOverlay extends StatelessWidget {
  const _FigmaRecognizingOverlay({required this.geometry});

  final _ScanViewfinderGeometry geometry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const Key('scan-figma-recognizing-overlay'),
            painter: _FigmaRecognizingOverlayPainter(geometry.rect),
          ),
        ),
        Positioned.fromRect(
          rect: geometry.rect,
          child: const SizedBox(key: Key('scan-figma-overlay-viewfinder')),
        ),
      ],
    );
  }
}

class _FigmaRecognizingOverlayPainter extends CustomPainter {
  const _FigmaRecognizingOverlayPainter(this.viewfinderRect);

  final Rect viewfinderRect;

  @override
  void paint(Canvas canvas, Size size) {
    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        viewfinderRect.center,
        size.longestSide * 0.55,
        const [Color(0x000D0F08), Color(0xD90D0F08)],
        const [0.6, 1],
      );
    canvas.drawRect(Offset.zero & size, vignette);

    final dimOutsideViewfinder = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(viewfinderRect, const Radius.circular(16)),
      );
    canvas.drawPath(
      dimOutsideViewfinder,
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _FigmaRecognizingOverlayPainter oldDelegate) {
    return viewfinderRect != oldDelegate.viewfinderRect;
  }
}

class _FigmaRevealingOverlay extends StatelessWidget {
  const _FigmaRevealingOverlay({required this.geometry});

  final _ScanViewfinderGeometry geometry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const Key('scan-figma-revealing-overlay'),
            painter: _FigmaRevealingOverlayPainter(geometry.rect),
          ),
        ),
        Positioned.fromRect(
          rect: geometry.rect,
          child: const SizedBox(key: Key('scan-figma-overlay-viewfinder')),
        ),
      ],
    );
  }
}

class _FigmaRevealingOverlayPainter extends CustomPainter {
  const _FigmaRevealingOverlayPainter(this.viewfinderRect);

  final Rect viewfinderRect;

  @override
  void paint(Canvas canvas, Size size) {
    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        viewfinderRect.center,
        size.longestSide * 0.55,
        const [Color(0x000D0F08), Color(0xD90D0F08)],
        const [0.6, 1],
      );
    canvas.drawRect(Offset.zero & size, vignette);

    final dimOutsideViewfinder = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(viewfinderRect, const Radius.circular(16)),
      );
    canvas.drawPath(
      dimOutsideViewfinder,
      Paint()..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(covariant _FigmaRevealingOverlayPainter oldDelegate) {
    return viewfinderRect != oldDelegate.viewfinderRect;
  }
}

class _ScanRevealingToast extends StatelessWidget {
  const _ScanRevealingToast({
    required super.key,
    required this.item,
    required this.onClosePressed,
  });

  final _ScanItem item;
  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 218,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1A90927C)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 50,
                  spreadRadius: -12,
                  offset: Offset(0, 25),
                ),
              ],
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x1AF0FE6F)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(17),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ScanResultThumbnail(
                        item: item,
                        width: 48,
                        height: 48,
                        imageWidth: 30,
                        imageHeight: 40,
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 120,
                        height: 48,
                        child: Stack(
                          children: [
                            const Positioned(
                              left: 0,
                              top: 0,
                              child: Text(
                                'Scanning...',
                                style: TextStyle(
                                  color: Color(0xFFEEECD8),
                                  fontSize: 16,
                                  height: 24 / 16,
                                ),
                              ),
                            ),
                            Positioned(
                              right: -8,
                              top: -8,
                              child: _ScanDeleteButton(
                                itemId: item.id,
                                onPressed: onClosePressed,
                              ),
                            ),
                            const Positioned(
                              left: 0,
                              bottom: 0,
                              child: SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  key: Key('scan-recognition-progress'),
                                  strokeWidth: 2,
                                  strokeAlign: CircularProgressIndicator
                                      .strokeAlignInside,
                                  color: Color(0xFFF0FE6F),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewfinderCorners extends StatelessWidget {
  const _ViewfinderCorners({required this.size, this.focusFrameShadow = false});

  final Size size;
  final bool focusFrameShadow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('scan-figma-viewfinder'),
      width: size.width,
      height: size.height,
      child: CustomPaint(
        painter: _ViewfinderPainter(focusFrameShadow: focusFrameShadow),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.focusFrameShadow});

  final bool focusFrameShadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (focusFrameShadow) {
      final focusFramePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5.1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            0.5,
            1.5,
            math.max(0, size.width - 1),
            math.max(0, size.height - 3),
          ),
          const Radius.circular(16),
        ),
        focusFramePaint,
      );
    }

    final paint = Paint()
      ..color = const Color(0xFFF0FE6F)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    const corner = 40.0;
    final path = Path()
      ..moveTo(0, corner)
      ..lineTo(0, 12)
      ..quadraticBezierTo(0, 0, 12, 0)
      ..lineTo(corner, 0)
      ..moveTo(size.width - corner, 0)
      ..lineTo(size.width - 12, 0)
      ..quadraticBezierTo(size.width, 0, size.width, 12)
      ..lineTo(size.width, corner)
      ..moveTo(0, size.height - corner)
      ..lineTo(0, size.height - 12)
      ..quadraticBezierTo(0, size.height, 12, size.height)
      ..lineTo(corner, size.height)
      ..moveTo(size.width - corner, size.height)
      ..lineTo(size.width - 12, size.height)
      ..quadraticBezierTo(size.width, size.height, size.width, size.height - 12)
      ..lineTo(size.width, size.height - corner);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) =>
      focusFrameShadow != oldDelegate.focusFrameShadow;
}

class _ScanResults extends StatelessWidget {
  const _ScanResults({
    required this.items,
    required this.cards,
    required this.currency,
    required this.showRevealingFeedback,
    required this.onDismissRevealing,
    required this.onReviewItem,
    required this.onRetryItem,
    required this.onDeleteItem,
    required this.onSearchPressed,
  });

  final List<_ScanItem> items;
  final Map<String, ScanReviewCard> cards;
  final AppCurrency currency;
  final bool showRevealingFeedback;
  final VoidCallback onDismissRevealing;
  final ValueChanged<int?> onReviewItem;
  final ValueChanged<_ScanItem> onRetryItem;
  final ValueChanged<_ScanItem> onDeleteItem;
  final ValueChanged<_ScanItem> onSearchPressed;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items
        .where((item) {
          return item.status != _ScanItemStatus.revealing ||
              showRevealingFeedback;
        })
        .toList()
        .reversed
        .toList();
    if (visibleItems.isEmpty) {
      return const SizedBox.shrink();
    }
    final completedCount = items.where((item) {
      return item.status == _ScanItemStatus.matched ||
          item.status == _ScanItemStatus.failed ||
          item.status == _ScanItemStatus.noMatch;
    }).length;
    final hasValuedCards = items.any(
      (item) => item.status == _ScanItemStatus.matched,
    );
    final total = items.fold<double>(0, (sum, item) {
      final card = cards[item.match?.cardRef];
      if (card == null) return sum;
      final draft = _previewDraft(card);
      return sum + (_selectedReviewPrice(card, draft) ?? 0);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 16,
          child: Row(
            children: [
              Text(
                'Scanned: $completedCount/${items.length}',
                style: const TextStyle(
                  color: Color(0xFFEEECD8),
                  fontSize: 13,
                  height: 16 / 13,
                ),
              ),
              const Spacer(),
              if (hasValuedCards && total > 0)
                Text(
                  'Total: ${CurrencyFormatter(currency: currency).formatUsd(total)}',
                  style: const TextStyle(
                    color: Color(0xFFFFF6AF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 15 / 13,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 82,
          child: ListView.separated(
            key: const Key('scan-figma-result-rail'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: visibleItems.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              return _ScanItemCard(
                key: Key('scan-active-item-${item.id}'),
                item: item,
                card: cards[item.match?.cardRef],
                currency: currency,
                onReview: () => onReviewItem(item.id),
                onRetry: () => onRetryItem(item),
                onDelete: () => onDeleteItem(item),
                onDismissRevealing: onDismissRevealing,
                onSearch: () => onSearchPressed(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ScanItemCard extends StatelessWidget {
  const _ScanItemCard({
    required super.key,
    required this.item,
    required this.card,
    required this.currency,
    required this.onReview,
    required this.onRetry,
    required this.onDelete,
    required this.onDismissRevealing,
    required this.onSearch,
  });

  final _ScanItem item;
  final ScanReviewCard? card;
  final AppCurrency currency;
  final VoidCallback onReview;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback onDismissRevealing;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    if (item.status == _ScanItemStatus.scanning ||
        item.status == _ScanItemStatus.recognizing ||
        item.status == _ScanItemStatus.revealing) {
      return _ScanRevealingToast(
        key: null,
        item: item,
        onClosePressed: onDelete,
      );
    }

    final matched = item.status == _ScanItemStatus.matched;
    final failed = item.status == _ScanItemStatus.failed;
    final waiting = item.status == _ScanItemStatus.waiting;
    final entitlementSync = item.status == _ScanItemStatus.entitlementSync;
    final width = matched ? 240.0 : 176.0;
    final title = matched
        ? item.match?.name ?? item.pictureLabel
        : failed
        ? 'Failed'
        : waiting
        ? 'Waiting to scan'
        : entitlementSync
        ? 'Premium Syncing'
        : 'No Match Found';
    final action = matched
        ? onReview
        : failed
        ? onRetry
        : item.status == _ScanItemStatus.noMatch || waiting
        ? onSearch
        : null;
    final previewDraft = card == null ? null : _previewDraft(card!);
    final price = previewDraft == null
        ? null
        : _selectedReviewPrice(card!, previewDraft);

    return Tooltip(
      message: matched
          ? 'Review scan result'
          : failed
          ? 'Retry scan'
          : waiting
          ? 'Unlock unlimited scans'
          : entitlementSync
          ? 'Premium access is syncing'
          : 'Search manually',
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          height: 82,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF292B20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: failed ? const Color(0x668C5260) : const Color(0x1A90927C),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 50,
                spreadRadius: -12,
                offset: Offset(0, 25),
              ),
            ],
          ),
          child: Row(
            children: [
              _ScanResultThumbnail(item: item),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: failed
                                  ? const Color(0xFFFF8493)
                                  : const Color(0xFFEEECD8),
                              fontSize: 16,
                              height: 24 / 16,
                            ),
                          ),
                        ),
                        _ScanDeleteButton(itemId: item.id, onPressed: onDelete),
                      ],
                    ),
                    if (matched)
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x33F0FE6F),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                previewDraft?.condition.toUpperCase() ?? 'RAW',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFF0FE6F),
                                  fontSize: 11,
                                  height: 16 / 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FittedBox(
                              key: Key('scan-item-price-${item.id}'),
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                price == null
                                    ? '--'
                                    : CurrencyFormatter(
                                        currency: currency,
                                      ).formatUsd(price),
                                maxLines: 1,
                                style: TextStyle(
                                  color: Color(0xFFFFF6AF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 15 / 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        failed
                            ? 'Tap to retry'
                            : waiting
                            ? 'Waiting to scan'
                            : entitlementSync
                            ? 'Syncing Premium'
                            : 'Search Manually',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFFF0FE6F),
                          fontSize: 13,
                          height: 16 / 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanDeleteButton extends StatelessWidget {
  const _ScanDeleteButton({required this.itemId, required this.onPressed});

  final int itemId;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: IconButton(
        key: Key('scan-delete-item-$itemId'),
        tooltip: 'Delete scan result',
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: SvgPicture.asset(
          'assets/scan/reveal_close.svg',
          width: 10.5,
          height: 10.5,
        ),
      ),
    );
  }
}

_ScanCollectionDraft _previewDraft(ScanReviewCard card) {
  return _ScanCollectionDraft(
    folderId: '',
    folderName: '',
    quantityText: '1',
    grader: 'Raw',
    condition: cardCollectionConditions.first,
    grade: '',
    language: card.language ?? 'English',
    finish: card.finish ?? 'Normal',
    purchasePriceText: '',
    notes: '',
  );
}

class _ScanResultThumbnail extends StatelessWidget {
  const _ScanResultThumbnail({
    required this.item,
    this.width = 42,
    this.height = 58,
    this.imageWidth,
    this.imageHeight,
  });

  final _ScanItem item;
  final double width;
  final double height;
  final double? imageWidth;
  final double? imageHeight;

  @override
  Widget build(BuildContext context) {
    final bytes = item.displayImageBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF10100B),
        alignment: Alignment.center,
        child: bytes == null
            ? SvgPicture.asset(
                'assets/scan/reveal_question.svg',
                width: 18,
                height: 28,
              )
            : Image.memory(
                bytes,
                width: imageWidth ?? width,
                height: imageHeight ?? height,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}

class _ReviewMatches extends StatelessWidget {
  const _ReviewMatches({
    required this.items,
    required this.selectedItemId,
    required this.target,
    required this.cards,
    required this.drafts,
    required this.formError,
    required this.saving,
    required this.savingAction,
    required this.keyboardVisible,
    required this.currency,
    required this.onCollapse,
    required this.onSelectItem,
    required this.onSelectCandidate,
    required this.onUpdateDraft,
    required this.onAddThisCard,
    required this.onAddAllCards,
    required this.onDeleteItem,
    required this.onDeleteAll,
  });

  final List<_ScanItem> items;
  final int? selectedItemId;
  final ScanReviewTarget? target;
  final Map<String, ScanReviewCard> cards;
  final Map<int, _ScanCollectionDraft> drafts;
  final String? formError;
  final bool saving;
  final _ScanReviewSaveAction? savingAction;
  final bool keyboardVisible;
  final AppCurrency currency;
  final VoidCallback onCollapse;
  final ValueChanged<_ScanItem> onSelectItem;
  final void Function(_ScanItem, _ScanCandidate) onSelectCandidate;
  final void Function(int, _ScanCollectionDraft) onUpdateDraft;
  final VoidCallback onAddThisCard;
  final VoidCallback onAddAllCards;
  final ValueChanged<_ScanItem> onDeleteItem;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    final selected = items.firstWhere(
      (item) => item.id == selectedItemId,
      orElse: () => items.first,
    );
    final match = selected.match!;
    final card = cards[match.cardRef];
    final draft = drafts[selected.id];
    final ready = target != null && card != null && draft != null;

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            key: const Key('scan-review-list'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 170),
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 62,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return InkWell(
                            key: Key('scan-review-item-${item.id}'),
                            onTap: saving ? null : () => onSelectItem(item),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              width: 44,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10100B),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: item.id == selected.id
                                      ? const Color(0xFFF0FE6F)
                                      : Colors.transparent,
                                ),
                              ),
                              child: _ScanResultThumbnail(
                                item: item,
                                width: 40,
                                height: 58,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Back to Scan',
                    onPressed: saving ? null : onCollapse,
                    icon: SvgPicture.asset(
                      'assets/scan/close.svg',
                      width: 14,
                      height: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFF222222),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Review your matches',
                      style: TextStyle(
                        color: Color(0xFFEEECD8),
                        fontFamily: 'Fraunces',
                        fontSize: 28,
                        height: 36 / 28,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _ReviewImageComparison(item: selected, card: card),
                    const SizedBox(height: 24),
                    const Text(
                      'Top matched results:',
                      style: TextStyle(
                        color: Color(0xFFEEECD8),
                        fontFamily: 'Fraunces',
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 192,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: match.candidates.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final candidate = match.candidates[index];
                          return _ReviewCandidateCard(
                            candidate: candidate,
                            card: cards[candidate.cardRef],
                            selected: candidate.cardRef == match.cardRef,
                            onTap: saving
                                ? null
                                : () => onSelectCandidate(selected, candidate),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!ready)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      KeyedSubtree(
                        key: ValueKey(
                          'scan-review-form-${selected.id}-${match.cardRef}',
                        ),
                        child: _ReviewCollectionItem(
                          itemId: selected.id,
                          target: target!,
                          card: card,
                          draft: draft,
                          formError: formError,
                          enabled: !saving,
                          onChanged: (next) => onUpdateDraft(selected.id, next),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (ready && !keyboardVisible)
          Align(
            alignment: Alignment.bottomCenter,
            child: _ReviewFooter(
              totalText: _reviewTotalText(card, draft, currency),
              showBulkActions: items.length > 1,
              saving: saving,
              savingAction: savingAction,
              onAddThisCard: onAddThisCard,
              onAddAllCards: onAddAllCards,
              onDeleteItem: () => onDeleteItem(selected),
              onDeleteAll: onDeleteAll,
            ),
          ),
      ],
    );
  }
}

class _KeyboardDismissOnPointerDown extends StatelessWidget {
  const _KeyboardDismissOnPointerDown({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final focus = FocusManager.instance.primaryFocus;
        final focusContext = focus?.context;
        if (focus == null || focusContext == null) {
          return;
        }

        final renderObject = focusContext.findRenderObject();
        if (renderObject is RenderBox && renderObject.attached) {
          final localPosition = renderObject.globalToLocal(event.position);
          if (renderObject.paintBounds.contains(localPosition)) {
            return;
          }
        }

        FocusScope.of(context).unfocus();
      },
      child: child,
    );
  }
}

class _ReviewImageComparison extends StatelessWidget {
  const _ReviewImageComparison({required this.item, required this.card});

  final _ScanItem item;
  final ScanReviewCard? card;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 218,
      child: Row(
        children: [
          Expanded(
            child: _ReviewPicture(
              label: 'YOUR PICTURE',
              child: item.displayImageBytes == null
                  ? const _ReviewImageUnavailable()
                  : Image.memory(
                      item.displayImageBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ReviewPicture(
              label: 'OUR MATCH',
              child: _ReviewNetworkImage(
                imageUrl: card?.imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewPicture extends StatelessWidget {
  const _ReviewPicture({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: const Color(0xFF10100B),
              child: SizedBox.expand(child: child),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF92927D), fontSize: 11),
        ),
      ],
    );
  }
}

class _ReviewNetworkImage extends StatelessWidget {
  const _ReviewNetworkImage({required this.imageUrl, required this.fit});

  final String? imageUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return KandoCardImage(
      imageUrl: imageUrl,
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
    );
  }
}

class _ReviewImageUnavailable extends StatelessWidget {
  const _ReviewImageUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'NO IMAGE',
          style: TextStyle(color: Color(0xFF92927D), fontSize: 10),
        ),
      ),
    );
  }
}

class _ReviewCandidateCard extends StatelessWidget {
  const _ReviewCandidateCard({
    required this.candidate,
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final _ScanCandidate candidate;
  final ScanReviewCard? card;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('scan-review-candidate-${candidate.cardRef}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF171811),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFF0FE6F) : const Color(0xFF464835),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox.expand(
                  child: _ReviewNetworkImage(
                    imageUrl: card?.imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card?.name ?? candidate.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFEEECD8), fontSize: 13),
            ),
            Text(
              card == null ? '' : '#${card!.cardNumber} • ${card!.setName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF92927D), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCollectionItem extends StatelessWidget {
  const _ReviewCollectionItem({
    required this.itemId,
    required this.target,
    required this.card,
    required this.draft,
    required this.formError,
    required this.enabled,
    required this.onChanged,
  });

  final int itemId;
  final ScanReviewTarget target;
  final ScanReviewCard card;
  final _ScanCollectionDraft draft;
  final String? formError;
  final bool enabled;
  final ValueChanged<_ScanCollectionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SizedBox(
                height: 32,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Collection item',
                    maxLines: 1,
                    style: TextStyle(
                      color: Color(0xFFEEECD8),
                      fontFamily: 'Fraunces',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: TextButton(
                key: Key('scan-review-folder-$itemId'),
                onPressed: enabled
                    ? () async {
                        ProviderScope.containerOf(context, listen: false)
                            .read(analyticsProvider)
                            .track(AnalyticsEvent.folderClick);
                        final folder = await _showScanFolderSheet(
                          context,
                          folders: target.folders,
                          selectedFolderId: draft.folderId,
                        );
                        if (folder != null) {
                          onChanged(
                            draft.copyWith(
                              folderId: folder.id,
                              folderName: folder.name,
                            ),
                          );
                        }
                      }
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFF0FE6F),
                  disabledForegroundColor: const Color(0x66615D3B),
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Adding to ${draft.folderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 16 / 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF171811),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF464835)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      height: 110,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: _ReviewNetworkImage(
                          imageUrl: card.imageUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (card.game ?? 'TCG').toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFF0FE6F),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            card.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFE4E3D3),
                              fontFamily: 'Fraunces',
                              fontSize: 20,
                            ),
                          ),
                          Text(
                            card.setName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFC7C8B0)),
                          ),
                          Text(
                            card.cardNumber,
                            style: const TextStyle(
                              color: Color(0xFF92927D),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF464835)),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ReviewSectionLabel('OWNERSHIP SUMMARY'),
                    const SizedBox(height: 12),
                    _ReviewTextRow(
                      fieldKey: Key('scan-review-quantity-$itemId'),
                      label: 'QUANTITY',
                      value: draft.quantityText,
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          onChanged(draft.copyWith(quantityText: value)),
                    ),
                    const SizedBox(height: 24),
                    _ReviewPillGroup(
                      fieldKey: Key('scan-review-finish-$itemId'),
                      label: 'FINISH',
                      selected: draft.finish,
                      options: _optionsIncluding(
                        card.collectionFinishOptions,
                        draft.finish,
                      ),
                      enabled: enabled,
                      onChanged: (value) =>
                          onChanged(draft.copyWith(finish: value)),
                    ),
                    const SizedBox(height: 24),
                    _ReviewCardState(
                      rawKey: Key('scan-review-state-raw-$itemId'),
                      gradedKey: Key('scan-review-state-graded-$itemId'),
                      isRaw: draft.isRaw,
                      enabled: enabled,
                      onRaw: () => onChanged(draft.copyWith(grader: 'Raw')),
                      onGraded: () => onChanged(draft.copyWith(grader: 'PSA')),
                    ),
                    const SizedBox(height: 32),
                    const Divider(color: Color(0xFF464835)),
                    const SizedBox(height: 24),
                    _ReviewDetailsHeading(isRaw: draft.isRaw),
                    const SizedBox(height: 24),
                    if (draft.isRaw)
                      _ReviewPillGroup(
                        fieldKey: Key('scan-review-condition-$itemId'),
                        label: 'CONDITION',
                        selected: draft.condition,
                        options: cardCollectionConditions,
                        columns: 1,
                        enabled: enabled,
                        onChanged: (value) =>
                            onChanged(draft.copyWith(condition: value)),
                      )
                    else ...[
                      _ReviewPillGroup(
                        fieldKey: Key('scan-review-grader-$itemId'),
                        label: 'GRADER',
                        selected: draft.grader,
                        options: cardCollectionGraders
                            .where((value) => value != 'Raw')
                            .toList(),
                        enabled: enabled,
                        onChanged: (value) =>
                            onChanged(draft.copyWith(grader: value)),
                      ),
                      const SizedBox(height: 24),
                      _ReviewPillGroup(
                        fieldKey: Key('scan-review-grade-$itemId'),
                        label: 'GRADE',
                        selected: draft.grade,
                        options: cardCollectionGradeValuesFor(draft.grader),
                        enabled: enabled,
                        onChanged: (value) =>
                            onChanged(draft.copyWith(grade: value)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _ReviewDropdownRow(
                      fieldKey: Key('scan-review-language-$itemId'),
                      label: 'LANGUAGE',
                      value: draft.language,
                      options: _optionsIncluding(
                        card.collectionLanguageOptions,
                        draft.language,
                      ),
                      enabled: enabled,
                      onChanged: (value) =>
                          onChanged(draft.copyWith(language: value)),
                    ),
                    const SizedBox(height: 24),
                    _ReviewTextRow(
                      fieldKey: Key('scan-review-price-$itemId'),
                      label: 'PURCHASE PRICE',
                      value: draft.purchasePriceText,
                      enabled: enabled,
                      prefixText: r'US$',
                      accentText: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (value) =>
                          onChanged(draft.copyWith(purchasePriceText: value)),
                    ),
                    const SizedBox(height: 32),
                    const Divider(color: Color(0xFF464835)),
                    const SizedBox(height: 32),
                    Text(
                      'NOTES',
                      key: Key('scan-review-notes-label-$itemId'),
                      style: const TextStyle(
                        color: Color(0xFFEEECD8),
                        fontFamily: 'Fraunces',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 20 / 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: Key('scan-review-notes-$itemId'),
                      initialValue: draft.notes,
                      enabled: enabled,
                      minLines: 5,
                      maxLines: 8,
                      maxLength: 500,
                      scrollPadding: const EdgeInsets.only(bottom: 190),
                      cursorColor: const Color(0xFFF0FE6F),
                      style: const TextStyle(
                        color: Color(0xFFEEECD8),
                        fontSize: 14,
                        height: 20 / 14,
                      ),
                      onChanged: (value) =>
                          onChanged(draft.copyWith(notes: value)),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF10110C),
                        counterText: '',
                        contentPadding: const EdgeInsets.fromLTRB(
                          17,
                          16,
                          17,
                          17,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFF464835),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFF464835),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFF0FE6F),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (formError != null) ...[
          const SizedBox(height: 8),
          Text(
            formError!,
            key: const Key('scan-review-form-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _ReviewTextRow extends StatelessWidget {
  const _ReviewTextRow({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.enabled,
    required this.keyboardType,
    required this.onChanged,
    this.prefixText,
    this.accentText = false,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final bool enabled;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;
  final String? prefixText;
  final bool accentText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReviewSectionLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          key: fieldKey,
          initialValue: value,
          enabled: enabled,
          keyboardType: keyboardType,
          cursorColor: const Color(0xFFF0FE6F),
          style: TextStyle(
            color: accentText
                ? const Color(0xFFF0FE6F)
                : const Color(0xFFEEECD8),
            fontSize: 16,
            fontWeight: accentText ? FontWeight.w600 : FontWeight.w400,
            height: 24 / 16,
          ),
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixText: prefixText,
            prefixStyle: TextStyle(
              color: accentText
                  ? const Color(0xFFF0FE6F)
                  : const Color(0xFFEEECD8),
              fontSize: 16,
              fontWeight: accentText ? FontWeight.w600 : FontWeight.w400,
              height: 24 / 16,
            ),
            filled: true,
            fillColor: const Color(0xFF10110C),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 17,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF464835)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF464835)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFF0FE6F)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewDropdownRow extends StatelessWidget {
  const _ReviewDropdownRow({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.contains(value) ? value : options.first;
    final displayText = selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReviewSectionLabel(label),
        const SizedBox(height: 8),
        InkWell(
          key: fieldKey,
          borderRadius: BorderRadius.circular(8),
          onTap: enabled
              ? () async {
                  FocusManager.instance.primaryFocus?.unfocus(
                    disposition: UnfocusDisposition.scope,
                  );
                  final next = await _showReviewChoiceSheet(
                    context,
                    title: label,
                    selected: selected,
                    options: options,
                  );
                  FocusManager.instance.primaryFocus?.unfocus(
                    disposition: UnfocusDisposition.scope,
                  );
                  if (next != null) onChanged(next);
                }
              : null,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 17),
            decoration: BoxDecoration(
              color: const Color(0xFF10110C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF464835)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFFEEECD8)
                          : const Color(0xFFEEECD8).withValues(alpha: 0.45),
                      fontSize: 16,
                      height: 24 / 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: enabled
                      ? const Color(0xFFC7C8B0)
                      : const Color(0xFFC7C8B0).withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewSectionLabel extends StatelessWidget {
  const _ReviewSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF92927D),
      fontSize: 11,
      height: 18 / 11,
    ),
  );
}

class _ReviewPillGroup extends StatelessWidget {
  const _ReviewPillGroup({
    required this.fieldKey,
    required this.label,
    required this.selected,
    required this.options,
    required this.enabled,
    required this.onChanged,
    this.columns = 3,
  });
  final Key fieldKey;
  final String label;
  final String selected;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final int columns;

  @override
  Widget build(BuildContext context) => Column(
    key: fieldKey,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _ReviewSectionLabel(label),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final gap = columns == 1 ? 0.0 : 8.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: 8,
            children: [
              for (final option in options)
                SizedBox(
                  width: width,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: enabled ? () => onChanged(option) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: option == selected
                          ? const Color(0xFFF0FE6F)
                          : const Color(0xFFC7C8B0),
                      backgroundColor: option == selected
                          ? const Color(0xFF343718)
                          : const Color(0xFF10110C),
                      side: BorderSide(
                        color: option == selected
                            ? const Color(0xFFF0FE6F)
                            : const Color(0xFF464835),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: columns == 1
                          ? Alignment.centerLeft
                          : Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Text(
                      option,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, height: 24 / 16),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _ReviewDetailsHeading extends StatelessWidget {
  const _ReviewDetailsHeading({required this.isRaw});

  final bool isRaw;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          isRaw ? 'RAW DETAILS' : 'GRADING DETAILS',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFEEECD8),
            fontFamily: 'Fraunces',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 20 / 14,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0x1AF0FE6F),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isRaw ? 'Raw details' : 'Third-party graded',
          style: const TextStyle(color: Color(0xFF92927D), fontSize: 10),
        ),
      ),
    ],
  );
}

class _ReviewCardState extends StatelessWidget {
  const _ReviewCardState({
    required this.rawKey,
    required this.gradedKey,
    required this.isRaw,
    required this.enabled,
    required this.onRaw,
    required this.onGraded,
  });
  final Key rawKey;
  final Key gradedKey;
  final bool isRaw;
  final bool enabled;
  final VoidCallback onRaw;
  final VoidCallback onGraded;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _ReviewSectionLabel('CARD STATE'),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _stateButton(rawKey, 'Raw', 'Unrated card', isRaw, onRaw),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _stateButton(
              gradedKey,
              'Graded',
              'Certified card',
              !isRaw,
              onGraded,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _stateButton(
    Key key,
    String title,
    String subtitle,
    bool selected,
    VoidCallback onPressed,
  ) => SizedBox(
    height: 58,
    child: OutlinedButton(
      key: key,
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        foregroundColor: selected
            ? const Color(0xFFF0FE6F)
            : const Color(0xFFC7C8B0),
        backgroundColor: selected
            ? const Color(0xFF343718)
            : const Color(0xFF10110C),
        side: BorderSide(
          color: selected ? const Color(0xFFF0FE6F) : const Color(0xFF464835),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _showReviewChoiceSheet(
  BuildContext context, {
  required String title,
  required String selected,
  required List<String> options,
  String Function(String value)? displayValue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    requestFocus: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final screenHeight = MediaQuery.sizeOf(sheetContext).height;
      final maxHeight = screenHeight * 0.68 > 520 ? 520.0 : screenHeight * 0.68;

      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Material(
              color: const Color(0xFF191A12),
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    key: const Key('scan-review-choice-sheet-handle'),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFEEECD8),
                              fontFamily: 'Fraunces',
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              height: 32 / 24,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF92927D),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      key: const Key('scan-review-choice-sheet-list'),
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        return _ReviewChoiceSheetOption(
                          key: Key('scan-review-choice-option-$option'),
                          label: displayValue?.call(option) ?? option,
                          selected: option == selected,
                          onTap: () => Navigator.of(sheetContext).pop(option),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ReviewChoiceSheetOption extends StatelessWidget {
  const _ReviewChoiceSheetOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFF0FE6F).withValues(alpha: 0.16)
              : const Color(0xFF171811).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFFF0FE6F).withValues(alpha: 0.8)
                : const Color(0xFF464835).withValues(alpha: 0.75),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFEEECD8)
                      : const Color(0xFFC7C8B0),
                  fontSize: 15,
                  height: 22 / 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: selected
                  ? const Color(0xFFF0FE6F)
                  : const Color(0xFF464835),
            ),
          ],
        ),
      ),
    );
  }
}

Future<ScanReviewFolder?> _showScanFolderSheet(
  BuildContext context, {
  required List<ScanReviewFolder> folders,
  required String selectedFolderId,
}) {
  return showModalBottomSheet<ScanReviewFolder>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99000000),
    builder: (context) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Material(
          color: const Color(0xFF222222),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 21, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: const Key('scan-review-folder-sheet-handle'),
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF615D3B),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Add scanned cards to',
                    style: TextStyle(
                      color: Color(0xFFF0FE6F),
                      fontSize: 16,
                      height: 24 / 16,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FE6F),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    key: const Key('scan-review-folder-sheet-list'),
                    shrinkWrap: true,
                    itemCount: folders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      final selected = folder.id == selectedFolderId;
                      return InkWell(
                        key: Key('scan-review-folder-option-${folder.id}'),
                        onTap: () => Navigator.of(context).pop(folder),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 58,
                          padding: const EdgeInsets.symmetric(horizontal: 17),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0x0DF0FE6F)
                                : const Color(0xFF1A1C14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFFF0FE6F)
                                  : const Color(0xFF464835),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 20,
                                color: selected
                                    ? const Color(0xFFF0FE6F)
                                    : const Color(0xFF92927D),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? const Color(0xFFEEECD8)
                                        : const Color(0xFF92927D),
                                    fontSize: selected ? 15 : 16,
                                    height: selected ? 22 / 15 : 24 / 16,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_circle,
                                  key: Key(
                                    'scan-review-folder-selected-indicator',
                                  ),
                                  size: 20,
                                  color: Color(0xFFF0FE6F),
                                )
                              else
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF464835),
                                      width: 2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({
    required this.totalText,
    required this.showBulkActions,
    required this.saving,
    required this.savingAction,
    required this.onAddThisCard,
    required this.onAddAllCards,
    required this.onDeleteItem,
    required this.onDeleteAll,
  });

  final String totalText;
  final bool showBulkActions;
  final bool saving;
  final _ScanReviewSaveAction? savingAction;
  final VoidCallback onAddThisCard;
  final VoidCallback onAddAllCards;
  final VoidCallback onDeleteItem;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    final addingSingle = savingAction == _ScanReviewSaveAction.single;
    final addingAll = savingAction == _ScanReviewSaveAction.all;

    return Material(
      color: const Color(0xFF10100B),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'TOTAL VALUE',
                    style: TextStyle(color: Color(0xFF92927D), fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    totalText,
                    key: const Key('scan-review-total'),
                    style: const TextStyle(
                      color: Color(0xFFF0FE6F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        key: const Key('scan-review-add-one'),
                        onPressed: saving ? null : onAddThisCard,
                        icon: addingSingle
                            ? const SizedBox(
                                key: Key('scan-review-add-one-loading'),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '+',
                                style: TextStyle(fontSize: 20, height: 1),
                              ),
                        label: const Text('Add this card'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    key: const Key('scan-review-delete-one'),
                    tooltip: 'Delete card',
                    onPressed: saving ? null : onDeleteItem,
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(56),
                      minimumSize: const Size.square(56),
                      padding: EdgeInsets.zero,
                      backgroundColor: const Color(0x1AE1B6FF),
                      disabledBackgroundColor: const Color(0x0DE1B6FF),
                      foregroundColor: const Color(0xFFFFB4AB),
                      disabledForegroundColor: const Color(0x66FFB4AB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(33),
                        side: const BorderSide(color: Color(0x33FFB4AB)),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 24),
                  ),
                ],
              ),
              if (showBulkActions) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('scan-review-add-all'),
                        onPressed: saving ? null : onAddAllCards,
                        child: addingAll
                            ? const SizedBox(
                                key: Key('scan-review-add-all-loading'),
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('ADD ALL CARDS'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : onDeleteAll,
                        child: const Text('DELETE ALL CARDS'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
