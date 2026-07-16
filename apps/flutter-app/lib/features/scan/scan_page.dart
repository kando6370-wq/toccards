import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';

import '../../shared/portfolio/portfolio_providers.dart';
import '../../shared/scan/scan_api_client.dart';
import '../../shared/ui/toast.dart';
import '../collection/collection_controller.dart';
import '../card_detail/card_detail_controller.dart';
import '../home/home_controller.dart';
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

String _reviewTotalText(ScanReviewCard card, _ScanCollectionDraft draft) {
  final quantity = int.tryParse(draft.quantityText.trim());
  if (quantity == null || quantity < 1) return '--';
  final price = card.prices
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
  return price == null ? '--' : '\$${(price * quantity).toStringAsFixed(2)}';
}

String _normalizedReviewCondition(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');
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
  int? _selectedReviewItemId;
  int? _lastAddedCount;
  ScanReviewTarget? _reviewTarget;
  Map<String, ScanReviewCard> _reviewCards = const {};
  final Map<int, _ScanCollectionDraft> _reviewDrafts = {};
  String? _reviewFormError;
  var _savingReview = false;
  int? _dismissedFeedbackItemId;
  int? _dismissedFailureFeedbackItemId;

  bool get _hasScanning {
    return _items.any(
      (item) =>
          item.status == _ScanItemStatus.scanning ||
          item.status == _ScanItemStatus.recognizing ||
          item.status == _ScanItemStatus.revealing,
    );
  }

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

  List<_ScanItem> get _addedItems {
    return _items
        .where((item) => item.status == _ScanItemStatus.added)
        .toList();
  }

  _ScanItem? get _singleTerminalCameraItem {
    if (_hasScanning) {
      return null;
    }
    final terminalItems = _items
        .where(
          (item) =>
              item.status == _ScanItemStatus.matched ||
              item.status == _ScanItemStatus.failed ||
              item.status == _ScanItemStatus.noMatch ||
              item.status == _ScanItemStatus.added,
        )
        .toList();
    return terminalItems.length == 1 ? terminalItems.single : null;
  }

  _ScanItem? get _completedCameraItem {
    final item = _singleTerminalCameraItem;
    return item?.status == _ScanItemStatus.matched ? item : null;
  }

  _ScanItem? get _failedCameraItem {
    final item = _singleTerminalCameraItem;
    return item?.status == _ScanItemStatus.failed ? item : null;
  }

  bool get _showFailedCameraFeedback {
    final item = _failedCameraItem;
    return item != null && item.id != _dismissedFailureFeedbackItemId;
  }

  bool get _canReview {
    return !_hasScanning && _matchedItems.isNotEmpty;
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
      return;
    }
    setState(() {
      _cameraSession = session;
      _openingCamera = false;
    });
  }

  Future<void> _closeCamera() async {
    _cameraGeneration += 1;
    _openingCamera = false;
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
    _addScan(
      camera == null
          ? Future.sync(source.photo)
          : camera.takePhoto().then(source.recognize),
    );
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

  void _dismissFailedScanFeedback() {
    final failedItem = _failedCameraItem;
    if (failedItem == null) {
      return;
    }
    setState(() => _dismissedFailureFeedbackItemId = failedItem.id);
  }

  void _deleteScan(_ScanItem item) {
    _pendingScans.remove(item.id)?.revealController?.dispose();
    setState(() {
      _items.removeWhere((candidate) => candidate.id == item.id);
      if (_selectedReviewItemId == item.id) {
        _selectedReviewItemId = _matchedItems.firstOrNull?.id;
      }
      if (_dismissedFailureFeedbackItemId == item.id) {
        _dismissedFailureFeedbackItemId = null;
      }
    });
  }

  void _addScan(Future<ScanResolution> resultFuture) {
    final id = _nextScanId;
    _nextScanId += 1;
    setState(() {
      _lastAddedCount = null;
      _dismissedFeedbackItemId = null;
      _dismissedFailureFeedbackItemId = null;
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
    completedPending?.revealController?.dispose();
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
    setState(() {
      _reviewing = true;
      _selectedReviewItemId = itemId ?? _matchedItems.first.id;
      _reviewTarget = null;
      _reviewCards = const {};
      _reviewFormError = null;
    });
    unawaited(_closeCamera());
    try {
      final items = _matchedItems;
      final repository = ref.read(scanReviewRepositoryProvider);
      final results = await Future.wait<Object>([
        repository.loadTarget(
          preferredFolderId: ref.read(selectedPortfolioFolderProvider),
        ),
        repository.loadCards([
          for (final item in items)
            for (final candidate in item.match!.candidates) candidate.cardRef,
        ]),
      ]);
      final target = results[0] as ScanReviewTarget;
      final cards = results[1] as Map<String, ScanReviewCard>;
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
                addedItems: _addedItems,
                lastAddedCount: _lastAddedCount,
                canReview: _canReview,
                completedItem: _completedCameraItem,
                failedItem: _failedCameraItem,
                showFailedFeedback: _showFailedCameraFeedback,
                scanning: _isScanning,
                recognizing: _isRecognizing,
                revealing: _isRevealing,
                showRevealingFeedback: _showRevealingFeedback,
                revealAnimation: _revealAnimation,
                onClosePressed: _requestExitScan,
                onFlashPressed: _cameraSession == null ? null : _toggleFlash,
                onSearchPressed: () => context.go('/search'),
                onPhotoPressed: _startPhotoScan,
                onLibraryPressed: _startLibraryScan,
                onDismissScanFeedback: _dismissScanFeedback,
                onDismissFailedFeedback: _dismissFailedScanFeedback,
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
    required this.addedItems,
    required this.lastAddedCount,
    required this.canReview,
    required this.completedItem,
    required this.failedItem,
    required this.showFailedFeedback,
    required this.scanning,
    required this.recognizing,
    required this.revealing,
    required this.showRevealingFeedback,
    required this.revealAnimation,
    required this.onClosePressed,
    required this.onFlashPressed,
    required this.onSearchPressed,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
    required this.onDismissScanFeedback,
    required this.onDismissFailedFeedback,
    required this.onReviewPressed,
    required this.onReviewItem,
    required this.onRetryItem,
    required this.onDeleteItem,
    required this.onSearchItem,
  });

  final Widget? cameraPreview;
  final bool flashEnabled;
  final List<_ScanItem> items;
  final List<_ScanItem> addedItems;
  final int? lastAddedCount;

  final bool canReview;
  final _ScanItem? completedItem;
  final _ScanItem? failedItem;
  final bool showFailedFeedback;
  final bool scanning;
  final bool recognizing;
  final bool revealing;
  final bool showRevealingFeedback;
  final Animation<double> revealAnimation;
  final VoidCallback onClosePressed;
  final VoidCallback? onFlashPressed;
  final VoidCallback onSearchPressed;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback onDismissScanFeedback;
  final VoidCallback onDismissFailedFeedback;
  final VoidCallback onReviewPressed;
  final ValueChanged<int?> onReviewItem;
  final ValueChanged<_ScanItem> onRetryItem;
  final ValueChanged<_ScanItem> onDeleteItem;
  final ValueChanged<_ScanItem> onSearchItem;

  @override
  Widget build(BuildContext context) {
    final completed = completedItem != null;
    final failed = failedItem != null;
    final showingFailedFeedback = failed && showFailedFeedback;
    return Stack(
      children: [
        if (completed)
          const Positioned.fill(child: _FigmaCompletedCanvas())
        else if (showingFailedFeedback)
          const Positioned.fill(child: _FigmaFailedCanvas())
        else if (cameraPreview != null)
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
        else if (!completed && !showingFailedFeedback) ...[
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
        if (!completed && !showingFailedFeedback)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 59,
            child: ColoredBox(color: Color(0xFF10100B)),
          ),
        if (!completed && !showingFailedFeedback)
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
        if (!completed && !showingFailedFeedback)
          Positioned(
            top: 163,
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
        if ((scanning || recognizing || revealing) &&
            !completed &&
            !showingFailedFeedback)
          Positioned(
            left: 16,
            right: 16,
            bottom: 134,
            child: _ActiveScanResults(
              items: items,
              showRevealingFeedback: showRevealingFeedback,
              onDismissRevealing: onDismissScanFeedback,
              onDeleteItem: onDeleteItem,
            ),
          ),
        if (completed)
          _FigmaCompletedActions(
            item: completedItem!,
            onClosePressed: onClosePressed,
            onSearchPressed: onSearchPressed,
            onPhotoPressed: onPhotoPressed,
            onLibraryPressed: onLibraryPressed,
            onReviewPressed: onReviewPressed,
            onModifyPressed: () => onReviewItem(completedItem!.id),
          ),
        if (showingFailedFeedback)
          _FigmaFailedActions(
            item: failedItem!,
            onClosePressed: onClosePressed,
            onSearchPressed: onSearchPressed,
            onPhotoPressed: onPhotoPressed,
            onLibraryPressed: onLibraryPressed,
            onRetryPressed: () => onRetryItem(failedItem!),
            onDismissPressed: onDismissFailedFeedback,
          ),
        if (!scanning &&
            !recognizing &&
            !revealing &&
            !completed &&
            !failed &&
            items.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 144,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 292),
              child: SingleChildScrollView(
                child: _ScanResults(
                  items: items,
                  addedItems: addedItems,
                  lastAddedCount: lastAddedCount,
                  onReviewItem: onReviewItem,
                  onRetryItem: onRetryItem,
                  onDeleteItem: onDeleteItem,
                  onSearchPressed: onSearchItem,
                ),
              ),
            ),
          ),
        if (!completed && !showingFailedFeedback)
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

class _FigmaCompletedCanvas extends StatelessWidget {
  const _FigmaCompletedCanvas();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/scan/complete_canvas.png',
      key: const Key('scan-figma-complete-background'),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.none,
    );
  }
}

class _FigmaFailedCanvas extends StatelessWidget {
  const _FigmaFailedCanvas();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/scan/failure_canvas.png',
      key: const Key('scan-figma-failure-background'),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.none,
    );
  }
}

class _FigmaFailedActions extends StatelessWidget {
  const _FigmaFailedActions({
    required this.item,
    required this.onClosePressed,
    required this.onSearchPressed,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
    required this.onRetryPressed,
    required this.onDismissPressed,
  });

  final _ScanItem item;
  final VoidCallback onClosePressed;
  final VoidCallback onSearchPressed;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback onRetryPressed;
  final VoidCallback onDismissPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalScale = constraints.maxWidth / 390;
        final verticalScale = constraints.maxHeight / 844;
        final itemName = item.match?.name ?? item.pictureLabel;
        return Stack(
          children: [
            Positioned(
              left: 16 * horizontalScale,
              top: 617 * verticalScale,
              width: 175 * horizontalScale,
              height: 92 * verticalScale,
              child: Semantics(
                key: const Key('scan-figma-failure-toast'),
                container: true,
                label: '0 of 1 cards scanned. $itemName failed. Tap to retry.',
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 8 * horizontalScale,
              top: 59 * verticalScale,
              width: 48 * horizontalScale,
              height: 48 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Close Scan',
                onPressed: onClosePressed,
              ),
            ),
            Positioned(
              right: 8 * horizontalScale,
              top: 59 * verticalScale,
              width: 48 * horizontalScale,
              height: 48 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Search Cards',
                onPressed: onSearchPressed,
              ),
            ),
            Positioned(
              left: 16 * horizontalScale,
              top: 617 * verticalScale,
              width: 175 * horizontalScale,
              height: 92 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Tap to retry',
                onPressed: onRetryPressed,
              ),
            ),
            Positioned(
              left: 151 * horizontalScale,
              top: 617 * verticalScale,
              width: 40 * horizontalScale,
              height: 48 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Dismiss failed scan feedback',
                onPressed: onDismissPressed,
              ),
            ),
            Positioned(
              left: 16 * horizontalScale,
              top: 726 * verticalScale,
              width: 72 * horizontalScale,
              height: 96 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Choose from Library',
                onPressed: onLibraryPressed,
              ),
            ),
            Positioned(
              left: 151 * horizontalScale,
              top: 734 * verticalScale,
              width: 88 * horizontalScale,
              height: 88 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Take Photo',
                onPressed: onPhotoPressed,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FigmaCompletedActions extends StatelessWidget {
  const _FigmaCompletedActions({
    required this.item,
    required this.onClosePressed,
    required this.onSearchPressed,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
    required this.onReviewPressed,
    required this.onModifyPressed,
  });

  final _ScanItem item;
  final VoidCallback onClosePressed;
  final VoidCallback onSearchPressed;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback onReviewPressed;
  final VoidCallback onModifyPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalScale = constraints.maxWidth / 390;
        final verticalScale = constraints.maxHeight / 844;
        final matchName = item.match?.name ?? item.pictureLabel;
        return Stack(
          children: [
            Positioned(
              left: 19 * horizontalScale,
              top: 590 * verticalScale,
              child: Semantics(
                key: const Key('scan-figma-complete-count'),
                container: true,
                label:
                    'Scanned: 1/1. $matchName. PSA 10. Estimated value '
                    '\$16,785.28. Total \$16,874.16.',
                child: const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: 8 * horizontalScale,
              top: 59 * verticalScale,
              width: 48 * horizontalScale,
              height: 48 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Close Scan',
                onPressed: onClosePressed,
              ),
            ),
            Positioned(
              right: 8 * horizontalScale,
              top: 59 * verticalScale,
              width: 48 * horizontalScale,
              height: 48 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Search Cards',
                onPressed: onSearchPressed,
              ),
            ),
            Positioned(
              left: 246 * horizontalScale,
              top: 627 * verticalScale,
              width: 76 * horizontalScale,
              height: 82 * verticalScale,
              child: _FigmaCompletedAction(
                focusKey: const Key('scan-figma-complete-result'),
                tooltip: 'Modify scan match',
                onPressed: onModifyPressed,
              ),
            ),
            Positioned(
              left: 16 * horizontalScale,
              top: 726 * verticalScale,
              width: 72 * horizontalScale,
              height: 96 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Choose from Library',
                onPressed: onLibraryPressed,
              ),
            ),
            Positioned(
              left: 151 * horizontalScale,
              top: 734 * verticalScale,
              width: 88 * horizontalScale,
              height: 88 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Take Photo',
                onPressed: onPhotoPressed,
              ),
            ),
            Positioned(
              right: 10 * horizontalScale,
              top: 726 * verticalScale,
              width: 80 * horizontalScale,
              height: 96 * verticalScale,
              child: _FigmaCompletedAction(
                tooltip: 'Review completed scan',
                onPressed: onReviewPressed,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FigmaCompletedAction extends StatelessWidget {
  const _FigmaCompletedAction({
    this.focusKey,
    required this.tooltip,
    required this.onPressed,
  });

  final Key? focusKey;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Focus(
      key: focusKey,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Tooltip(
            message: tooltip,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  button: true,
                  label: tooltip,
                  onTap: onPressed,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onPressed,
                    child: const SizedBox.expand(),
                  ),
                ),
                if (hasFocus)
                  IgnorePointer(
                    child: DecoratedBox(
                      key: const Key('scan-figma-complete-focus-outline'),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFF0FE6F),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [
                          BoxShadow(color: Color(0x66F0FE6F), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
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
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(
                  0xFF222222,
                ).withValues(alpha: canReview ? 0.92 : 0.48),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x1A394E2C)),
              ),
              child: Opacity(
                opacity: canReview ? 1 : 0.4,
                child: SvgPicture.asset(
                  'assets/scan/done.svg',
                  key: const Key('scan-figma-done-icon'),
                  width: 16.3,
                  height: 12.025,
                ),
              ),
            ),
            TextButton(
              onPressed: canReview ? onReviewPressed : null,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEEECD8),
                disabledForegroundColor: const Color(0x66EEECD8),
                minimumSize: const Size(62, 28),
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                'DONE',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  height: 16 / 13,
                ),
              ),
            ),
          ],
        ),
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
            child: CustomPaint(
              key: const Key('scan-figma-recognizing-overlay'),
              painter: const _FigmaRecognizingOverlayPainter(),
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
    const designSize = Size(390, 884);
    canvas.save();
    canvas.scale(
      size.width / designSize.width,
      size.height / designSize.height,
    );

    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(195, 442),
        483.104,
        const [Color(0x000D0F08), Color(0xD90D0F08)],
        const [0.6, 1],
      );
    canvas.drawRect(Offset.zero & designSize, vignette);

    final dimOutsideViewfinder = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & designSize)
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(55, 163, 280, 400),
          const Radius.circular(16),
        ),
      );
    canvas.drawPath(
      dimOutsideViewfinder,
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawRect(Offset.zero & designSize, vignette);
    canvas.restore();
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
            child: CustomPaint(
              key: const Key('scan-figma-revealing-overlay'),
              painter: const _FigmaRevealingOverlayPainter(),
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
    const designSize = Size(390, 884);
    canvas.save();
    canvas.scale(
      size.width / designSize.width,
      size.height / designSize.height,
    );

    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(195, 442),
        483.1,
        const [Color(0x000D0F08), Color(0xD90D0F08)],
        const [0.6, 1],
      );
    canvas.drawRect(Offset.zero & designSize, vignette);

    final dimOutsideViewfinder = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & designSize)
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(55, 163, 280, 400),
          const Radius.circular(16),
        ),
      );
    canvas.drawPath(
      dimOutsideViewfinder,
      Paint()..color = const Color(0x66000000),
    );
    canvas.restore();
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

class _ActiveScanResults extends StatelessWidget {
  const _ActiveScanResults({
    required this.items,
    required this.showRevealingFeedback,
    required this.onDismissRevealing,
    required this.onDeleteItem,
  });

  final List<_ScanItem> items;
  final bool showRevealingFeedback;
  final VoidCallback onDismissRevealing;
  final ValueChanged<_ScanItem> onDeleteItem;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.where((item) {
      final active =
          item.status == _ScanItemStatus.scanning ||
          item.status == _ScanItemStatus.recognizing ||
          item.status == _ScanItemStatus.revealing;
      return active &&
          (item.status != _ScanItemStatus.revealing || showRevealingFeedback);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scanned: $completedCount/${items.length}',
          style: const TextStyle(
            color: Color(0xFFEEECD8),
            fontFamily: 'Geist',
            fontSize: 13,
            height: 16 / 13,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: visibleItems.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              return _ScanRevealingToast(
                key: Key('scan-active-item-${item.id}'),
                closeTooltip: item.status == _ScanItemStatus.revealing
                    ? 'Dismiss scan feedback'
                    : 'Cancel scan',
                onClosePressed: item.status == _ScanItemStatus.revealing
                    ? onDismissRevealing
                    : () => onDeleteItem(item),
              );
            },
          ),
        ),
      ],
    );
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
      width: 280,
      height: 400,
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
    required this.addedItems,
    required this.lastAddedCount,
    required this.onReviewItem,
    required this.onRetryItem,
    required this.onDeleteItem,
    required this.onSearchPressed,
  });

  final List<_ScanItem> items;
  final List<_ScanItem> addedItems;
  final int? lastAddedCount;
  final ValueChanged<int?> onReviewItem;
  final ValueChanged<_ScanItem> onRetryItem;
  final ValueChanged<_ScanItem> onDeleteItem;
  final ValueChanged<_ScanItem> onSearchPressed;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lastAddedCount != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(
                lastAddedCount == 1
                    ? 'Added to Portfolio'
                    : 'Added $lastAddedCount cards to Portfolio',
              ),
            ),
          ),
        Text('Scan Results', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final item in items)
          _ScanItemCard(
            item: item,
            onReview: () => onReviewItem(item.id),
            onRetry: () => onRetryItem(item),
            onDelete: () => onDeleteItem(item),
            onSearch: () => onSearchPressed(item),
          ),
        if (addedItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Added Cards', style: Theme.of(context).textTheme.titleMedium),
          for (final item in addedItems)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Added to Portfolio'),
                subtitle: Text(item.match?.name ?? item.pictureLabel),
              ),
            ),
        ],
      ],
    );
  }
}

class _ScanItemCard extends StatelessWidget {
  const _ScanItemCard({
    required this.item,
    required this.onReview,
    required this.onRetry,
    required this.onDelete,
    required this.onSearch,
  });

  final _ScanItem item;
  final VoidCallback onReview;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: switch (item.status) {
          _ScanItemStatus.scanning => ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Scanning'),
            subtitle: Text(item.pictureLabel),
          ),
          _ScanItemStatus.recognizing => ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Recognizing'),
            subtitle: Text(item.pictureLabel),
          ),
          _ScanItemStatus.revealing => ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Scanning...'),
            subtitle: Text(item.pictureLabel),
          ),
          _ScanItemStatus.matched => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_circle_outline),
                title: Text('Matched'),
              ),
              Text(item.match?.name ?? item.pictureLabel),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review'),
                ),
              ),
            ],
          ),
          _ScanItemStatus.failed => _ActionResult(
            icon: Icons.error_outline,
            title: 'Failed',
            subtitle: 'Recognition failed',
            primaryLabel: 'Retry',
            onPrimary: onRetry,
            secondaryLabel: 'Delete',
            onSecondary: onDelete,
          ),
          _ScanItemStatus.noMatch => _ActionResult(
            icon: Icons.search_off_outlined,
            title: 'No Match Found',
            subtitle: 'No database match for this scan',
            primaryLabel: 'Search Manually',
            onPrimary: onSearch,
            secondaryLabel: 'Delete',
            onSecondary: onDelete,
          ),
          _ScanItemStatus.added => ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Added to Portfolio'),
            subtitle: Text(item.match?.name ?? item.pictureLabel),
          ),
        },
      ),
    );
  }
}

class _ActionResult extends StatelessWidget {
  const _ActionResult({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onPrimary,
              icon: const Icon(Icons.search_outlined),
              label: Text(primaryLabel),
            ),
            TextButton.icon(
              onPressed: onSecondary,
              icon: const Icon(Icons.delete_outline),
              label: Text(secondaryLabel),
            ),
          ],
        ),
      ],
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
                                fit: BoxFit.cover,
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
              totalText: _reviewTotalText(card, draft),
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
                fit: BoxFit.cover,
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
                    fit: BoxFit.cover,
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
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: Key('scan-review-folder-$itemId'),
                value: draft.folderId,
                dropdownColor: const Color(0xFF2A2B20),
                icon: const Text(
                  'v',
                  style: TextStyle(color: Color(0xFFF0FE6F), fontSize: 12),
                ),
                style: const TextStyle(
                  color: Color(0xFFF0FE6F),
                  fontFamily: 'Geist',
                  fontSize: 13,
                ),
                items: [
                  for (final folder in target.folders)
                    DropdownMenuItem(
                      value: folder.id,
                      child: Text('Adding to ${folder.name}'),
                    ),
                ],
                onChanged: enabled
                    ? (folderId) {
                        final folder = target.folders
                            .where((folder) => folder.id == folderId)
                            .firstOrNull;
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
                          fit: BoxFit.cover,
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
