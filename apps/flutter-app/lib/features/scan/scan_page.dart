import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';

import '../../shared/currency/currency.dart';
import '../../shared/portfolio/portfolio_providers.dart';
import '../../shared/scan/scan_api_client.dart';
import '../../shared/ui/toast.dart';
import '../collection/collection_controller.dart';
import '../card_detail/card_detail_controller.dart';
import '../home/home_controller.dart';
import '../search/search_controller.dart';
import 'scan_camera.dart';
import 'scan_review_repository.dart';

enum _ScanItemStatus {
  scanning,
  recognizing,
  revealing,
  matched,
  failed,
  noMatch,
  added,
}

const _viewfinderTop = 163.0;
const _viewfinderWidth = 280.0;
const _viewfinderHeight = 400.0;

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
    this.match,
    this.imageBytes,
    this.imageFileName,
  });

  final int id;
  final String pictureLabel;
  final _ScanItemStatus status;
  final _ScanMatch? match;
  final Uint8List? imageBytes;
  final String? imageFileName;

  _ScanItem copyWith({
    _ScanItemStatus? status,
    _ScanMatch? match,
    Uint8List? imageBytes,
    String? imageFileName,
  }) {
    return _ScanItem(
      id: id,
      pictureLabel: pictureLabel,
      status: status ?? this.status,
      match: match ?? this.match,
      imageBytes: imageBytes ?? this.imageBytes,
      imageFileName: imageFileName ?? this.imageFileName,
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
                    ? cardCollectionGradeValues.first
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
    language: _supportedValue(
      card.language,
      cardCollectionLanguages,
      'English',
    ),
    finish: _supportedValue(card.finish, cardCollectionFinishes, 'Normal'),
    purchasePriceText: '',
    notes: '',
  );
}

String _supportedValue(String? value, List<String> options, String fallback) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return fallback;
  return options
          .where((option) => option.toLowerCase() == normalized.toLowerCase())
          .firstOrNull ??
      normalized;
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
  return card.prices
      .where((candidate) {
        if (candidate.grader.toLowerCase() != draft.grader.toLowerCase()) {
          return false;
        }
        if (draft.isRaw) {
          return _normalizedReviewCondition(candidate.condition) ==
              _normalizedReviewCondition(draft.condition);
        }
        final grade = double.tryParse(draft.grade);
        return grade != null && candidate.grade == grade;
      })
      .firstOrNull
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
  AnimationController? revealController;
}

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _revealTimelineDuration = Duration(microseconds: 1529856);

  final List<_ScanItem> _items = [];
  final List<Timer> _scanTimers = [];
  final Map<int, _PendingScan> _pendingScans = {};
  ScanCameraSession? _cameraSession;

  var _nextScanId = 1;
  var _nextScanToken = 1;
  var _cameraGeneration = 0;
  var _openingCamera = false;
  var _appActive = true;
  var _reviewing = false;
  var _photoRecognitionInFlight = false;
  int? _selectedReviewItemId;
  int? _lastAddedCount;
  ScanReviewTarget? _reviewTarget;
  Map<String, ScanReviewCard> _reviewCards = const {};
  final Map<int, _ScanCollectionDraft> _reviewDrafts = {};
  String? _reviewFormError;
  var _savingReview = false;
  int? _dismissedFeedbackItemId;

  bool get _isScanning {
    return _items.any((item) => item.status == _ScanItemStatus.scanning);
  }

  bool get _isRecognizing {
    return _items.any((item) => item.status == _ScanItemStatus.recognizing);
  }

  bool get _isRevealing {
    return _items.any((item) => item.status == _ScanItemStatus.revealing);
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
    return _matchedItems.isNotEmpty;
  }

  Animation<double> get _revealAnimation {
    final revealingItem = _items
        .where((item) => item.status == _ScanItemStatus.revealing)
        .firstOrNull;
    return revealingItem == null
        ? const AlwaysStoppedAnimation(0)
        : _pendingScans[revealingItem.id]?.revealController ??
              const AlwaysStoppedAnimation(0);
  }

  bool get _hasUnsavedScanResults {
    return _items.any((item) => item.status != _ScanItemStatus.added);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_openCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appActive = true;
      unawaited(_openCamera());
      return;
    }
    _appActive = false;
    unawaited(_closeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    _pendingScans.clear();
    super.dispose();
  }

  Future<void> _openCamera() async {
    if (_openingCamera || _cameraSession != null || !_appActive || _reviewing) {
      return;
    }
    _openingCamera = true;
    final generation = ++_cameraGeneration;
    ScanCameraSession? session;
    try {
      session = await ref.read(scanCameraFactoryProvider).open();
    } catch (_) {
      session = null;
    }
    if (!mounted ||
        generation != _cameraGeneration ||
        !_appActive ||
        _reviewing) {
      await session?.dispose();
      if (!mounted) return;
      _openingCamera = false;
      if (_appActive && !_reviewing && _cameraSession == null) {
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
    _photoRecognitionInFlight = false;
    final session = _cameraSession;
    if (session == null) return;
    if (mounted) {
      setState(() => _cameraSession = null);
    } else {
      _cameraSession = null;
    }
    await session.dispose();
  }

  void _startPhotoScan() {
    final source = ref.read(scanResultSourceProvider);
    final camera = _cameraSession;
    if (camera == null) {
      if (_openingCamera) return;
      _addScan(Future.sync(source.photo));
      return;
    }
    if (_photoRecognitionInFlight) return;
    _photoRecognitionInFlight = true;
    final result = _captureAndRecognize(camera, source);
    _addScan(result);
    unawaited(_finishPhotoRecognition(result));
  }

  Future<ScanResolution> _captureAndRecognize(
    ScanCameraSession camera,
    ScanResultSource source,
  ) async {
    try {
      final image = await camera.takePhoto();
      return await source.recognize(image);
    } catch (_) {
      return const ScanResolution.failed();
    }
  }

  Future<void> _finishPhotoRecognition(Future<ScanResolution> pending) async {
    await pending;
    _photoRecognitionInFlight = false;
  }

  Future<void> _toggleFlash() async {
    final camera = _cameraSession;
    if (camera == null) return;
    await camera.toggleFlash();
    if (mounted && identical(camera, _cameraSession)) setState(() {});
  }

  Future<void> _startLibraryScan() async {
    try {
      final scans = await ref.read(scanResultSourceProvider).library();
      if (!mounted) return;
      for (final scan in scans) {
        _addScan(scan);
      }
    } catch (_) {
      if (mounted) {
        _addScan(Future.value(const ScanResolution.failed()));
      }
    }
  }

  void _retryScan(_ScanItem item) {
    _replaceItem(item.copyWith(status: _ScanItemStatus.scanning));
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

  void _deleteScan(_ScanItem item) {
    _pendingScans.remove(item.id)?.revealController?.dispose();
    setState(() {
      _items.removeWhere((candidate) => candidate.id == item.id);
      if (_selectedReviewItemId == item.id) {
        _selectedReviewItemId = _matchedItems.firstOrNull?.id;
      }
    });
  }

  void _addScan(Future<ScanResolution> resultFuture) {
    final id = _nextScanId;
    _nextScanId += 1;
    setState(() {
      _lastAddedCount = null;
      _dismissedFeedbackItemId = null;
      _items.add(
        _ScanItem(
          id: id,
          pictureLabel: 'Scan $id',
          status: _ScanItemStatus.scanning,
        ),
      );
    });
    _startScanTimeline(id, resultFuture);
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
    if (!mounted || pending == null || pending.token != token) {
      return;
    }
    if (resolution.kind == ScanResolutionKind.cancelled) {
      _pendingScans.remove(itemId)?.revealController?.dispose();
      setState(() {
        _items.removeWhere((item) => item.id == itemId);
      });
      return;
    }
    pending.resolution = resolution;
    _completeScanIfReady(itemId, token);
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
    if (!_canReview) {
      return;
    }
    final items = _matchedItems;
    final matchedIds = items.map((item) => item.id).toSet();
    final cachedCards = Map<String, ScanReviewCard>.from(_reviewCards);
    final cardRefs = [
      for (final item in items)
        for (final candidate in item.match!.candidates) candidate.cardRef,
    ];
    final missingCardRefs = cardRefs
        .where((cardRef) => !cachedCards.containsKey(cardRef))
        .toList();
    for (final pendingId
        in _pendingScans.keys
            .where((id) => !matchedIds.contains(id))
            .toList()) {
      _pendingScans.remove(pendingId)?.revealController?.dispose();
    }
    setState(() {
      _items.removeWhere((item) => !matchedIds.contains(item.id));
      _reviewing = true;
      _selectedReviewItemId = itemId ?? items.first.id;
      _reviewTarget = null;
      _reviewCards = const {};
      _reviewFormError = null;
    });
    unawaited(_closeCamera());
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
      if (mounted && _reviewing) {
        setState(() {
          _reviewTarget = target;
          _reviewCards = cards;
          _reviewDrafts
            ..clear()
            ..addEntries(
              items.map((item) {
                final card = cards[item.match!.cardRef]!;
                return MapEntry(item.id, _initialReviewDraft(target, card));
              }),
            );
        });
      }
    } on Exception {
      _failReviewLoad();
    }
  }

  void _failReviewLoad() {
    if (!mounted) return;
    setState(() {
      _reviewing = false;
      _selectedReviewItemId = null;
      _reviewTarget = null;
      _reviewCards = const {};
      _reviewDrafts.clear();
      _reviewFormError = null;
    });
    unawaited(_openCamera());
    showKandoFailureToast(context);
  }

  Future<void> _addSelectedItem() async {
    final selectedId = _selectedReviewItemId;
    final item = _matchedItems
        .where((candidate) => candidate.id == selectedId)
        .firstOrNull;
    if (item == null || _reviewTarget == null || _savingReview) {
      return;
    }
    final input = _reviewInputFor(item);
    if (input == null) return;

    setState(() => _savingReview = true);
    try {
      await ref
          .read(scanReviewRepositoryProvider)
          .addToPortfolio(scanId: item.match!.scanId, item: input);
      if (!mounted) return;
      setState(() {
        _lastAddedCount = 1;
        _reviewing = false;
        _markItemsAdded({item.id});
        _selectedReviewItemId = null;
        _reviewTarget = null;
        _reviewCards = const {};
        _reviewDrafts.remove(item.id);
        _reviewFormError = null;
      });
      unawaited(_openCamera());
      _refreshPortfolioSurfaces();
    } on Exception {
      if (mounted) showKandoFailureToast(context);
    } finally {
      if (mounted) setState(() => _savingReview = false);
    }
  }

  Future<void> _addAllMatchedItems() async {
    final matchedItems = _matchedItems;
    if (matchedItems.isEmpty || _reviewTarget == null || _savingReview) {
      return;
    }

    final inputs = <int, ScanCollectionItemInput>{};
    for (final item in matchedItems) {
      final input = _reviewInputFor(item);
      if (input == null) return;
      inputs[item.id] = input;
    }

    setState(() => _savingReview = true);
    final addedIds = <int>{};
    var failed = false;
    for (final item in matchedItems) {
      try {
        await ref
            .read(scanReviewRepositoryProvider)
            .addToPortfolio(scanId: item.match!.scanId, item: inputs[item.id]!);
        addedIds.add(item.id);
      } on Exception {
        failed = true;
      }
    }

    if (!mounted) return;
    setState(() {
      _markItemsAdded(addedIds);
      for (final itemId in addedIds) {
        _reviewDrafts.remove(itemId);
      }
      _lastAddedCount = addedIds.isEmpty ? null : addedIds.length;
      final remaining = _matchedItems;
      _reviewing = remaining.isNotEmpty;
      _selectedReviewItemId = remaining.firstOrNull?.id;
      if (!_reviewing) {
        _reviewTarget = null;
        _reviewCards = const {};
      }
      _reviewFormError = null;
      _savingReview = false;
    });
    if (addedIds.isNotEmpty) _refreshPortfolioSurfaces();
    if (!_reviewing) unawaited(_openCamera());
    if (failed) showKandoFailureToast(context);
  }

  void _selectReviewItem(_ScanItem item) {
    setState(() {
      _selectedReviewItemId = item.id;
      _reviewFormError = null;
    });
  }

  void _selectReviewCandidate(_ScanItem item, _ScanCandidate candidate) {
    final card = _reviewCards[candidate.cardRef];
    if (card == null) return;
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
          language: _supportedValue(
            card.language,
            cardCollectionLanguages,
            'English',
          ),
          finish: _supportedValue(
            card.finish,
            cardCollectionFinishes,
            'Normal',
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
    if (!await _confirmReviewDelete(all: false)) return;
    _removeReviewItems({item.id});
  }

  Future<void> _deleteAllReviewItems() async {
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
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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

  void _markItemsAdded(Set<int> itemIds) {
    for (var index = 0; index < _items.length; index += 1) {
      if (itemIds.contains(_items[index].id)) {
        _items[index] = _items[index].copyWith(status: _ScanItemStatus.added);
      }
    }
  }

  void _refreshPortfolioSurfaces() {
    ref.invalidate(homeControllerProvider);
    ref.invalidate(collectionControllerProvider);
    ref.invalidate(searchControllerProvider);
  }

  Future<void> _requestExitScan() async {
    if (_savingReview) {
      return;
    }
    if (!_hasUnsavedScanResults) {
      if (mounted) context.go('/home');
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
                onPressed: () => Navigator.of(context).pop(false),
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
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(selectedCurrencyProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExitScan();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10100B),
        body: _reviewing
            ? SafeArea(
                child: _ReviewMatches(
                  items: _matchedItems,
                  selectedItemId: _selectedReviewItemId,
                  target: _reviewTarget,
                  cards: _reviewCards,
                  drafts: _reviewDrafts,
                  formError: _reviewFormError,
                  saving: _savingReview,
                  currency: currency,
                  onExit: _requestExitScan,
                  onSelectItem: _selectReviewItem,
                  onSelectCandidate: _selectReviewCandidate,
                  onUpdateDraft: _updateReviewDraft,
                  onAddThisCard: _addSelectedItem,
                  onAddAllCards: _addAllMatchedItems,
                  onDeleteItem: _deleteReviewItem,
                  onDeleteAll: _deleteAllReviewItems,
                ),
              )
            : _ScanCameraView(
                cameraPreview: _cameraSession?.buildPreview(),
                flashEnabled: _cameraSession?.flashEnabled ?? false,
                items: _items,
                lastAddedCount: _lastAddedCount,
                canReview: _canReview,
                scanning: _isScanning,
                recognizing: _isRecognizing,
                revealing: _isRevealing,
                showRevealingFeedback: _showRevealingFeedback,
                revealAnimation: _revealAnimation,
                cards: _reviewCards,
                currency: currency,
                onClosePressed: _requestExitScan,
                onFlashPressed: _cameraSession == null ? null : _toggleFlash,
                onSearchPressed: () => context.go('/search'),
                onPhotoPressed: _startPhotoScan,
                onLibraryPressed: _startLibraryScan,
                onDismissScanFeedback: _dismissScanFeedback,
                onReviewPressed: _openReview,
                onReviewItem: _openReview,
                onRetryItem: _retryScan,
                onDeleteItem: _deleteScan,
                onSearchItem: (item) {
                  _deleteScan(item);
                  context.go('/search');
                },
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
    required this.lastAddedCount,
    required this.canReview,
    required this.scanning,
    required this.recognizing,
    required this.revealing,
    required this.showRevealingFeedback,
    required this.revealAnimation,
    required this.cards,
    required this.currency,
    required this.onClosePressed,
    required this.onFlashPressed,
    required this.onSearchPressed,
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
  final int? lastAddedCount;

  final bool canReview;
  final bool scanning;
  final bool recognizing;
  final bool revealing;
  final bool showRevealingFeedback;
  final Animation<double> revealAnimation;
  final Map<String, ScanReviewCard> cards;
  final AppCurrency currency;
  final VoidCallback onClosePressed;
  final VoidCallback? onFlashPressed;
  final VoidCallback onSearchPressed;
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
    return Stack(
      children: [
        if (cameraPreview != null)
          Positioned.fill(
            child: KeyedSubtree(
              key: const Key('scan-live-camera-preview'),
              child: cameraPreview!,
            ),
          )
        else if (revealing)
          Positioned(
            left: -205,
            top: -27,
            width: 595,
            height: 1348,
            child: Image.asset(
              'assets/scan/camera_before.png',
              key: const Key('scan-figma-revealing-background'),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          )
        else
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight < 884
                        ? 884
                        : constraints.maxHeight,
                    child: Image.asset(
                      'assets/scan/camera_before.png',
                      key: const Key('scan-figma-camera-background'),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                );
              },
            ),
          ),
        if (recognizing)
          const Positioned.fill(child: _FigmaRecognizingOverlay())
        else if (revealing)
          const Positioned.fill(child: _FigmaRevealingOverlay())
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
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 59,
          child: ColoredBox(color: Color(0xFF10100B)),
        ),
        Positioned(
          top: 59,
          left: 8,
          right: 8,
          child: _FigmaRevealEntrance(
            animation: revealAnimation,
            active: revealing,
            opacityStart: 0,
            opacityEnd: 0.26146,
            translateStart: 0,
            translateEnd: 0.39219,
            initialOffsetY: -40,
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
              ],
            ),
          ),
        ),
        Positioned(
          top: _viewfinderTop,
          left: 0,
          right: 0,
          child: Center(
            child: _ViewfinderCorners(
              focusFrameShadow: recognizing || revealing,
            ),
          ),
        ),
        if (scanning) ...[
          Positioned(
            left: 55,
            top: 291,
            width: 280,
            height: 4,
            child: const _FigmaScanningLine(
              key: Key('scan-figma-scanning-line'),
            ),
          ),
        ],
        if (items.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 134,
            child: _ScanResults(
              items: items,
              cards: cards,
              currency: currency,
              lastAddedCount: lastAddedCount,
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
          bottom: revealing ? 19 : 22,
          child: _FigmaRevealEntrance(
            animation: revealAnimation,
            active: revealing,
            opacityStart: 0.52293,
            opacityEnd: 0.84834,
            translateStart: 0.52293,
            translateEnd: 0.91512,
            initialOffsetY: -25,
            opacityCurve: const _FigmaSpringCurve(),
            child: SafeArea(
              top: false,
              child: _ScanBottomControls(
                canReview: canReview,
                centered: revealing,
                onPhotoPressed: onPhotoPressed,
                onLibraryPressed: onLibraryPressed,
                onReviewPressed: onReviewPressed,
              ),
            ),
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
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Close Scan',
              onPressed: onClosePressed,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              icon: SvgPicture.asset(
                'assets/scan/close.svg',
                key: const Key('scan-figma-close-icon'),
                width: 14,
                height: 14,
              ),
            ),
          ),
          IconButton(
            tooltip: flashEnabled ? 'Turn flash off' : 'Turn flash on',
            onPressed: onFlashPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 25, height: 25),
            style: IconButton.styleFrom(
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
              tooltip: 'Search Cards',
              onPressed: onSearchPressed,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
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
              fontFamily: 'Geist',
              fontSize: 13,
              height: 16 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaScanningLine extends StatelessWidget {
  const _FigmaScanningLine({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const Key('scan-figma-scanning-line-canvas'),
      painter: const _FigmaScanningLinePainter(),
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
    required this.centered,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
    required this.onReviewPressed,
  });

  final bool canReview;
  final bool centered;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback onReviewPressed;

  @override
  Widget build(BuildContext context) {
    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.end,
      children: [
        _ScanSideAction(
          label: 'GALLERY',
          tooltip: 'Choose from Library',
          width: centered ? 62 : 72,
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
    return centered
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: controls,
          )
        : controls;
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
              Text(
                'DONE',
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFFEEECD8)
                      : const Color(0x66EEECD8),
                  fontFamily: 'Geist',
                  fontSize: 13,
                  height: 16 / 13,
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
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEEECD8),
              fontFamily: 'Geist',
              fontSize: 13,
              height: 16 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaRecognizingOverlay extends StatelessWidget {
  const _FigmaRecognizingOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight < 884 ? 884 : constraints.maxHeight,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(
                    key: Key('scan-figma-recognizing-overlay'),
                    painter: _FigmaRecognizingOverlayPainter(),
                  ),
                ),
                const Positioned(
                  top: _viewfinderTop,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox(
                      key: Key('scan-figma-overlay-viewfinder'),
                      width: _viewfinderWidth,
                      height: _viewfinderHeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FigmaRecognizingOverlayPainter extends CustomPainter {
  const _FigmaRecognizingOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        size.center(Offset.zero),
        size.longestSide * 0.55,
        const [Color(0x000D0F08), Color(0xD90D0F08)],
        const [0.6, 1],
      );
    canvas.drawRect(Offset.zero & size, vignette);

    final dimOutsideViewfinder = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(
          _viewfinderRect(size),
          const Radius.circular(16),
        ),
      );
    canvas.drawPath(
      dimOutsideViewfinder,
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _FigmaRecognizingOverlayPainter oldDelegate) =>
      false;
}

class _FigmaRevealingOverlay extends StatelessWidget {
  const _FigmaRevealingOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight < 884 ? 884 : constraints.maxHeight,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(
                    key: Key('scan-figma-revealing-overlay'),
                    painter: _FigmaRevealingOverlayPainter(),
                  ),
                ),
                const Positioned(
                  top: _viewfinderTop,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox(
                      key: Key('scan-figma-overlay-viewfinder'),
                      width: _viewfinderWidth,
                      height: _viewfinderHeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FigmaRevealingOverlayPainter extends CustomPainter {
  const _FigmaRevealingOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        size.center(Offset.zero),
        size.longestSide * 0.55,
        const [Color(0x000D0F08), Color(0xD90D0F08)],
        const [0.6, 1],
      );
    canvas.drawRect(Offset.zero & size, vignette);

    final dimOutsideViewfinder = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(
          _viewfinderRect(size),
          const Radius.circular(16),
        ),
      );
    canvas.drawPath(
      dimOutsideViewfinder,
      Paint()..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(covariant _FigmaRevealingOverlayPainter oldDelegate) =>
      false;
}

class _FigmaRevealEntrance extends StatelessWidget {
  const _FigmaRevealEntrance({
    required this.animation,
    required this.active,
    required this.opacityStart,
    required this.opacityEnd,
    required this.translateStart,
    required this.translateEnd,
    required this.initialOffsetY,
    required this.child,
    this.opacityCurve = const Cubic(0.5, 0, 0.5, 1),
  });

  final Animation<double> animation;
  final bool active;
  final double opacityStart;
  final double opacityEnd;
  final double translateStart;
  final double translateEnd;
  final double initialOffsetY;
  final Curve opacityCurve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final opacity = _figmaInterval(
          animation.value,
          opacityStart,
          opacityEnd,
          opacityCurve,
        );
        final translate = _figmaInterval(
          animation.value,
          translateStart,
          translateEnd,
          const _FigmaSpringCurve(),
        );
        return IgnorePointer(
          ignoring: opacity == 0,
          child: Opacity(
            opacity: opacity.clamp(0, 1).toDouble(),
            child: Transform.translate(
              offset: Offset(0, initialOffsetY * (1 - translate)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

double _figmaInterval(double progress, double start, double end, Curve curve) {
  if (progress <= start) {
    return 0;
  }
  if (progress >= end) {
    return 1;
  }
  return curve.transform((progress - start) / (end - start));
}

class _FigmaSpringCurve extends Curve {
  const _FigmaSpringCurve();

  static const _samples = [
    0.0,
    0.0188,
    0.0679,
    0.1374,
    0.2195,
    0.308,
    0.3978,
    0.4856,
    0.5686,
    0.6452,
    0.7142,
    0.7753,
    0.8283,
    0.8735,
    0.9113,
    0.9423,
    0.9671,
    0.9866,
    1.0014,
    1.0123,
    1.0198,
    1.0247,
    1.0274,
    1.0283,
    1.0281,
    1.0268,
    1.025,
    1.0227,
    1.0202,
    1.0177,
    1.0152,
    1.0128,
    1.0106,
    1.0085,
    1.0068,
    1.0052,
    1.0039,
    1.0028,
    1.0018,
    1.0011,
    1.0005,
    1.0,
    0.9997,
    0.9995,
    0.9993,
    0.9992,
    0.9992,
    0.9992,
    0.9992,
    0.9993,
    0.9993,
  ];

  @override
  double transformInternal(double t) {
    if (t >= 1) {
      return 1;
    }
    final position = t * (_samples.length - 1);
    final lower = position.floor();
    if (lower >= _samples.length - 1) {
      return _samples.last;
    }
    final fraction = position - lower;
    return _samples[lower] + (_samples[lower + 1] - _samples[lower]) * fraction;
  }
}

class _ScanRevealingToast extends StatelessWidget {
  const _ScanRevealingToast({
    required super.key,
    required this.closeTooltip,
    required this.onClosePressed,
  });

  final String closeTooltip;
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
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1C14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Container(
                          width: 30,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white),
                            borderRadius: BorderRadius.circular(2),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x1F747B26), Color(0x0A141506)],
                            ),
                          ),
                          child: SvgPicture.asset(
                            'assets/scan/reveal_question.svg',
                            width: 10,
                            height: 16,
                          ),
                        ),
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
                                  fontFamily: 'Geist',
                                  fontSize: 16,
                                  height: 24 / 16,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Tooltip(
                                message: closeTooltip,
                                child: InkWell(
                                  onTap: onClosePressed,
                                  child: SvgPicture.asset(
                                    'assets/scan/reveal_close.svg',
                                    width: 10.5,
                                    height: 10.5,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: SvgPicture.asset(
                                'assets/scan/reveal_spinner.svg',
                                width: 16,
                                height: 16,
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
  const _ViewfinderCorners({this.focusFrameShadow = false});

  final bool focusFrameShadow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('scan-figma-viewfinder'),
      width: _viewfinderWidth,
      height: _viewfinderHeight,
      child: CustomPaint(
        painter: _ViewfinderPainter(focusFrameShadow: focusFrameShadow),
      ),
    );
  }
}

Rect _viewfinderRect(Size size) {
  return Rect.fromLTWH(
    (size.width - _viewfinderWidth) / 2,
    _viewfinderTop,
    _viewfinderWidth,
    _viewfinderHeight,
  );
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
          const Rect.fromLTWH(0.5, 1.5, 279, 397),
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
    required this.lastAddedCount,
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
  final int? lastAddedCount;
  final bool showRevealingFeedback;
  final VoidCallback onDismissRevealing;
  final ValueChanged<int?> onReviewItem;
  final ValueChanged<_ScanItem> onRetryItem;
  final ValueChanged<_ScanItem> onDeleteItem;
  final ValueChanged<_ScanItem> onSearchPressed;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.where((item) {
      return item.status != _ScanItemStatus.revealing || showRevealingFeedback;
    }).toList();
    if (visibleItems.isEmpty) {
      return const SizedBox.shrink();
    }
    final completedCount = items.where((item) {
      return item.status == _ScanItemStatus.matched ||
          item.status == _ScanItemStatus.failed ||
          item.status == _ScanItemStatus.noMatch ||
          item.status == _ScanItemStatus.added;
    }).length;
    final hasValuedCards = items.any(
      (item) =>
          item.status == _ScanItemStatus.matched ||
          item.status == _ScanItemStatus.added,
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
                lastAddedCount == null
                    ? 'Scanned: $completedCount/${items.length}'
                    : lastAddedCount == 1
                    ? 'Added to Portfolio'
                    : 'Added $lastAddedCount cards to Portfolio',
                style: const TextStyle(
                  color: Color(0xFFEEECD8),
                  fontFamily: 'Geist',
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
                    fontFamily: 'Geist Mono',
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
        closeTooltip: item.status == _ScanItemStatus.revealing
            ? 'Dismiss scan feedback'
            : 'Cancel scan',
        onClosePressed: item.status == _ScanItemStatus.revealing
            ? onDismissRevealing
            : onDelete,
      );
    }

    final matched = item.status == _ScanItemStatus.matched;
    final added = item.status == _ScanItemStatus.added;
    final failed = item.status == _ScanItemStatus.failed;
    final width = matched || added ? 240.0 : 176.0;
    final title = matched || added
        ? item.match?.name ?? item.pictureLabel
        : failed
        ? 'Failed'
        : 'No Match Found';
    final action = matched
        ? onReview
        : failed
        ? onRetry
        : item.status == _ScanItemStatus.noMatch
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
                              fontFamily: 'Geist',
                              fontSize: 16,
                              height: 24 / 16,
                            ),
                          ),
                        ),
                        if (!matched && !added)
                          Tooltip(
                            message: 'Delete scan result',
                            child: InkWell(
                              onTap: onDelete,
                              child: SvgPicture.asset(
                                'assets/scan/reveal_close.svg',
                                width: 10.5,
                                height: 10.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (matched || added)
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x33F0FE6F),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              added
                                  ? 'ADDED'
                                  : previewDraft?.condition.toUpperCase() ??
                                        'RAW',
                              style: const TextStyle(
                                color: Color(0xFFF0FE6F),
                                fontFamily: 'Geist Mono',
                                fontSize: 11,
                                height: 16 / 11,
                              ),
                            ),
                          ),
                          if (!added) ...[
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
                                    fontFamily: 'Geist Mono',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 15 / 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      Text(
                        failed ? 'Tap to retry' : 'Search Manually',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFFF0FE6F),
                          fontFamily: 'Geist',
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
  const _ScanResultThumbnail({required this.item});

  final _ScanItem item;

  @override
  Widget build(BuildContext context) {
    final bytes = item.imageBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 42,
        height: 58,
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
                width: 42,
                height: 58,
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
    required this.currency,
    required this.onExit,
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
  final AppCurrency currency;
  final VoidCallback onExit;
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
                          final preview = cards[item.match!.cardRef];
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
                              child: _ReviewNetworkImage(
                                imageUrl: preview?.imageUrl,
                                fit: BoxFit.contain,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close Scan',
                    onPressed: saving ? null : onExit,
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
        if (ready)
          Align(
            alignment: Alignment.bottomCenter,
            child: _ReviewFooter(
              totalText: _reviewTotalText(card, draft, currency),
              saving: saving,
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
              child: item.imageBytes == null
                  ? const _ReviewImageUnavailable()
                  : Image.memory(
                      item.imageBytes!,
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
          style: const TextStyle(
            color: Color(0xFF92927D),
            fontFamily: 'Geist',
            fontSize: 11,
          ),
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
    final url = imageUrl;
    if (url == null) return const _ReviewImageUnavailable();
    return Image.network(
      url,
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (_, _, _) => const _ReviewImageUnavailable(),
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
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    height: 16 / 13,
                  ),
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
              _ReviewTextRow(
                fieldKey: Key('scan-review-quantity-$itemId'),
                label: 'Quantity',
                value: draft.quantityText,
                enabled: enabled,
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    onChanged(draft.copyWith(quantityText: value)),
              ),
              _ReviewDropdownRow(
                fieldKey: Key('scan-review-grader-$itemId'),
                label: 'Grader',
                value: draft.grader,
                options: cardCollectionGraders,
                enabled: enabled,
                onChanged: (value) => onChanged(draft.copyWith(grader: value)),
              ),
              if (draft.isRaw)
                _ReviewDropdownRow(
                  fieldKey: Key('scan-review-condition-$itemId'),
                  label: 'Condition',
                  value: draft.condition,
                  options: cardCollectionConditions,
                  enabled: enabled,
                  onChanged: (value) =>
                      onChanged(draft.copyWith(condition: value)),
                )
              else
                _ReviewDropdownRow(
                  fieldKey: Key('scan-review-grade-$itemId'),
                  label: 'Grade',
                  value: draft.grade,
                  options: cardCollectionGradeValues,
                  enabled: enabled,
                  displayValue: (value) => '${draft.grader} $value',
                  onChanged: (value) => onChanged(draft.copyWith(grade: value)),
                ),
              _ReviewDropdownRow(
                fieldKey: Key('scan-review-language-$itemId'),
                label: 'Language',
                value: draft.language,
                options: _optionsIncluding(
                  cardCollectionLanguages,
                  draft.language,
                ),
                enabled: enabled,
                onChanged: (value) =>
                    onChanged(draft.copyWith(language: value)),
              ),
              _ReviewDropdownRow(
                fieldKey: Key('scan-review-finish-$itemId'),
                label: 'Finish',
                value: draft.finish,
                options: _optionsIncluding(
                  cardCollectionFinishes,
                  draft.finish,
                ),
                enabled: enabled,
                onChanged: (value) => onChanged(draft.copyWith(finish: value)),
              ),
              _ReviewTextRow(
                fieldKey: Key('scan-review-price-$itemId'),
                label: 'Purchase Price',
                value: draft.purchasePriceText,
                enabled: enabled,
                prefixText: r'US$',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (value) =>
                    onChanged(draft.copyWith(purchasePriceText: value)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextFormField(
                  key: Key('scan-review-notes-$itemId'),
                  initialValue: draft.notes,
                  enabled: enabled,
                  maxLines: 4,
                  maxLength: 500,
                  onChanged: (value) => onChanged(draft.copyWith(notes: value)),
                  decoration: _reviewInputDecoration('NOTES'),
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
  });

  final Key fieldKey;
  final String label;
  final String value;
  final bool enabled;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1A90927C))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFC7C8B0)),
            ),
          ),
          SizedBox(
            width: 140,
            child: TextFormField(
              key: fieldKey,
              initialValue: value,
              enabled: enabled,
              textAlign: TextAlign.end,
              keyboardType: keyboardType,
              onChanged: onChanged,
              decoration: InputDecoration(
                border: InputBorder.none,
                prefixText: prefixText,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
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
    this.displayValue,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String Function(String value)? displayValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1A90927C))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFC7C8B0)),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: fieldKey,
                value: value,
                isExpanded: true,
                dropdownColor: const Color(0xFF2A2B20),
                alignment: Alignment.centerRight,
                icon: const Text(
                  'v',
                  style: TextStyle(color: Color(0xFFC7C8B0), fontSize: 12),
                ),
                style: const TextStyle(
                  color: Color(0xFFEEECD8),
                  fontFamily: 'Geist',
                  fontSize: 14,
                ),
                selectedItemBuilder: (context) => [
                  for (final option in options)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        displayValue?.call(option) ?? option,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                items: [
                  for (final option in options)
                    DropdownMenuItem(
                      value: option,
                      child: Text(
                        displayValue?.call(option) ?? option,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (next) {
                        if (next != null) onChanged(next);
                      }
                    : null,
              ),
            ),
          ),
        ],
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
                      fontFamily: 'Geist',
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
                                    fontFamily: 'Geist',
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

InputDecoration _reviewInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    alignLabelWithHint: true,
    filled: true,
    fillColor: const Color(0xFF2A2B20),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
  );
}

class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({
    required this.totalText,
    required this.saving,
    required this.onAddThisCard,
    required this.onAddAllCards,
    required this.onDeleteItem,
    required this.onDeleteAll,
  });

  final String totalText;
  final bool saving;
  final VoidCallback onAddThisCard;
  final VoidCallback onAddAllCards;
  final VoidCallback onDeleteItem;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
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
                    child: FilledButton.icon(
                      key: const Key('scan-review-add-one'),
                      onPressed: saving ? null : onAddThisCard,
                      icon: const Text(
                        '+',
                        style: TextStyle(fontSize: 20, height: 1),
                      ),
                      label: Text(saving ? 'Adding...' : 'Add this card'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: 'Delete card',
                    onPressed: saving ? null : onDeleteItem,
                    icon: const Text(
                      'DEL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving ? null : onAddAllCards,
                      child: const Text('ADD ALL CARDS'),
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
          ),
        ),
      ),
    );
  }
}
