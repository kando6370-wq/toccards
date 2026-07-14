import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';

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
  const _ScanMatch({required this.name, required this.candidates});

  final String name;
  final List<String> candidates;
}

class _ScanItem {
  const _ScanItem({
    required this.id,
    required this.pictureLabel,
    required this.status,
    this.match,
  });

  final int id;
  final String pictureLabel;
  final _ScanItemStatus status;
  final _ScanMatch? match;

  _ScanItem copyWith({_ScanItemStatus? status, _ScanMatch? match}) {
    return _ScanItem(
      id: id,
      pictureLabel: pictureLabel,
      status: status ?? this.status,
      match: match ?? this.match,
    );
  }
}

class _PendingScan {
  _PendingScan(this.token);

  final int token;
  ScanResolution? resolution;
  var revealTimelineFinished = false;
}

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with SingleTickerProviderStateMixin {
  static const _revealTimelineDuration = Duration(microseconds: 1529856);

  final List<_ScanItem> _items = [];
  final List<Timer> _scanTimers = [];
  final Map<int, _PendingScan> _pendingScans = {};

  late final AnimationController _revealController;

  var _nextScanId = 1;
  var _nextScanToken = 1;
  var _reviewing = false;
  int? _selectedReviewItemId;
  int? _lastAddedCount;
  int? _dismissedFeedbackItemId;

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

  _ScanItem? get _completedCameraItem {
    if (_hasScanning) {
      return null;
    }
    final terminalItems = _items
        .where(
          (item) =>
              item.status == _ScanItemStatus.matched ||
              item.status == _ScanItemStatus.failed ||
              item.status == _ScanItemStatus.noMatch,
        )
        .toList();
    return terminalItems.length == 1 &&
            terminalItems.single.status == _ScanItemStatus.matched
        ? terminalItems.single
        : null;
  }

  bool get _canReview {
    return !_hasScanning && _matchedItems.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: _revealTimelineDuration,
    );
  }

  @override
  void dispose() {
    for (final timer in _scanTimers) {
      timer.cancel();
    }
    _pendingScans.clear();
    _revealController.dispose();
    super.dispose();
  }

  void _startPhotoScan() {
    if (_hasScanning) {
      return;
    }
    _addScan(Future.sync(() => ref.read(scanResultSourceProvider).photo()));
  }

  void _startLibraryScan() {
    if (_hasScanning) {
      return;
    }
    _addScan(Future.sync(() => ref.read(scanResultSourceProvider).library()));
  }

  void _retryScan(_ScanItem item) {
    if (_hasScanning) {
      return;
    }
    _replaceItem(item.copyWith(status: _ScanItemStatus.scanning));
    _startScanTimeline(
      item.id,
      Future.sync(() => ref.read(scanResultSourceProvider).retry()),
    );
  }

  void _cancelScanning() {
    _revealController.stop();
    final activeItemIds = _items
        .where(
          (item) =>
              item.status == _ScanItemStatus.scanning ||
              item.status == _ScanItemStatus.recognizing ||
              item.status == _ScanItemStatus.revealing,
        )
        .map((item) => item.id)
        .toSet();
    setState(() {
      _items.removeWhere(
        (item) =>
            item.status == _ScanItemStatus.scanning ||
            item.status == _ScanItemStatus.recognizing ||
            item.status == _ScanItemStatus.revealing,
      );
      if (activeItemIds.contains(_dismissedFeedbackItemId)) {
        _dismissedFeedbackItemId = null;
      }
    });
    for (final itemId in activeItemIds) {
      _pendingScans.remove(itemId);
    }
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
    _pendingScans.remove(item.id);
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
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      _revealController.value = 1;
      _markRevealTimelineFinished(itemId, token);
    } else {
      _waitForRevealTimeline(itemId, token);
    }
  }

  Future<void> _waitForRevealTimeline(int itemId, int token) async {
    try {
      await _revealController.forward(from: 0).orCancel;
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
    };
    final match = status == _ScanItemStatus.matched
        ? _ScanMatch(
            name: resolution.matchName!,
            candidates: resolution.candidates,
          )
        : null;

    _pendingScans.remove(itemId);
    setState(() {
      for (var index = 0; index < _items.length; index += 1) {
        if (_items[index].id == itemId) {
          _items[index] = item.copyWith(status: status, match: match);
          break;
        }
      }
      if (_dismissedFeedbackItemId == itemId) {
        _dismissedFeedbackItemId = null;
      }
    });
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

  void _openReview([int? itemId]) {
    if (!_canReview) {
      return;
    }
    setState(() {
      _reviewing = true;
      _selectedReviewItemId = itemId ?? _matchedItems.first.id;
    });
  }

  void _addSelectedItem() {
    final selectedId = _selectedReviewItemId;
    if (selectedId == null) {
      return;
    }

    setState(() {
      _lastAddedCount = 1;
      _reviewing = false;
      for (var index = 0; index < _items.length; index += 1) {
        if (_items[index].id == selectedId) {
          _items[index] = _items[index].copyWith(status: _ScanItemStatus.added);
          break;
        }
      }
      _selectedReviewItemId = null;
    });
  }

  void _addAllMatchedItems() {
    final matchedIds = _matchedItems.map((item) => item.id).toSet();
    if (matchedIds.isEmpty) {
      return;
    }

    setState(() {
      _lastAddedCount = matchedIds.length;
      _reviewing = false;
      for (var index = 0; index < _items.length; index += 1) {
        if (matchedIds.contains(_items[index].id)) {
          _items[index] = _items[index].copyWith(status: _ScanItemStatus.added);
        }
      }
      _selectedReviewItemId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10100B),
      body: _reviewing
          ? SafeArea(
              child: _ReviewMatches(
                items: _matchedItems,
                selectedItemId: _selectedReviewItemId,
                onSelectItem: (item) {
                  setState(() => _selectedReviewItemId = item.id);
                },
                onAddThisCard: _addSelectedItem,
                onAddAllCards: _addAllMatchedItems,
              ),
            )
          : _ScanCameraView(
              items: _items,
              addedItems: _addedItems,
              lastAddedCount: _lastAddedCount,
              canReview: _canReview,
              completedItem: _completedCameraItem,
              scanning: _isScanning,
              recognizing: _isRecognizing,
              revealing: _isRevealing,
              showRevealingFeedback: _showRevealingFeedback,
              revealAnimation: _revealController,
              onClosePressed: () => context.go('/'),
              onSearchPressed: () => context.go('/search'),
              onPhotoPressed: _startPhotoScan,
              onLibraryPressed: _startLibraryScan,
              onCancelScanning: _cancelScanning,
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
    );
  }
}

class _ScanCameraView extends StatelessWidget {
  const _ScanCameraView({
    required this.items,
    required this.addedItems,
    required this.lastAddedCount,
    required this.canReview,
    required this.completedItem,
    required this.scanning,
    required this.recognizing,
    required this.revealing,
    required this.showRevealingFeedback,
    required this.revealAnimation,
    required this.onClosePressed,
    required this.onSearchPressed,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
    required this.onCancelScanning,
    required this.onDismissScanFeedback,
    required this.onReviewPressed,
    required this.onReviewItem,
    required this.onRetryItem,
    required this.onDeleteItem,
    required this.onSearchItem,
  });

  final List<_ScanItem> items;
  final List<_ScanItem> addedItems;
  final int? lastAddedCount;

  final bool canReview;
  final _ScanItem? completedItem;
  final bool scanning;
  final bool recognizing;
  final bool revealing;
  final bool showRevealingFeedback;
  final Animation<double> revealAnimation;
  final VoidCallback onClosePressed;
  final VoidCallback onSearchPressed;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback onCancelScanning;
  final VoidCallback onDismissScanFeedback;
  final VoidCallback onReviewPressed;
  final ValueChanged<int?> onReviewItem;
  final ValueChanged<_ScanItem> onRetryItem;
  final ValueChanged<_ScanItem> onDeleteItem;
  final ValueChanged<_ScanItem> onSearchItem;

  @override
  Widget build(BuildContext context) {
    final completed = completedItem != null;
    return Stack(
      children: [
        if (completed)
          const Positioned.fill(child: _FigmaCompletedCanvas())
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
        else if (!completed) ...[
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
        if (!completed)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 59,
            child: ColoredBox(color: Color(0xFF10100B)),
          ),
        if (!completed && !scanning && !recognizing)
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
                    onSearchPressed: onSearchPressed,
                  ),
                  const SizedBox(height: 2),
                  const _AlignCardPill(),
                ],
              ),
            ),
          ),
        if (!completed)
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
            left: 35,
            top: 221,
            width: 320,
            height: 87,
            child: const _FigmaScanningLine(
              key: Key('scan-figma-scanning-line'),
            ),
          ),
          Positioned(
            left: 137,
            top: 679,
            child: _ScanCancelButton(onPressed: onCancelScanning),
          ),
        ],
        if (revealing && showRevealingFeedback)
          Positioned(
            left: 16,
            top: 627,
            child: _FigmaRevealEntrance(
              animation: revealAnimation,
              active: true,
              opacityStart: 0.13073,
              opacityEnd: 0.39219,
              translateStart: 0.13073,
              translateEnd: 0.52293,
              initialOffsetY: -200,
              translationCurve: const Cubic(0.7, -0.4, 0.4, 1.4),
              child: _ScanRevealingToast(onClosePressed: onDismissScanFeedback),
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
        if (!scanning &&
            !recognizing &&
            !revealing &&
            !completed &&
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
        if (!completed && !scanning && !recognizing)
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
    required this.onSearchPressed,
  });

  final VoidCallback onClosePressed;
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
          Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
              color: const Color(0xFF222222).withValues(alpha: 0.82),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: SvgPicture.asset(
                'assets/scan/flash.svg',
                key: const Key('scan-figma-flash-icon'),
                width: 9,
                height: 15,
              ),
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

class _ScanCancelButton extends StatelessWidget {
  const _ScanCancelButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('scan-figma-cancel'),
        onTap: onPressed,
        child: SizedBox(
          width: 116,
          height: 36,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8.9, sigmaY: 8.9),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x615F6054),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0x1FFFFFFF),
                    width: 0.5,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Geist',
                      fontSize: 13,
                      height: 16 / 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
    final arc = Path()
      ..moveTo(160, 0)
      ..cubicTo(240.081, 0, 305, 30.0542, 305, 67.1279)
      ..lineTo(305, 68)
      ..lineTo(15, 68)
      ..cubicTo(15, 30.0542, 79.9189, 0, 160, 0)
      ..close();
    final arcPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.bottomCenter,
        radius: 1.15,
        colors: [Color(0xBFF0FE6F), Color(0x00FFFFFF)],
      ).createShader(const Rect.fromLTWH(15, 0, 290, 68));
    canvas.drawPath(arc, arcPaint);

    const lineRect = Rect.fromLTWH(15, 68, 290, 4);
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
    this.translationCurve = const _FigmaSpringCurve(),
    this.opacityCurve = const Cubic(0.5, 0, 0.5, 1),
  });

  final Animation<double> animation;
  final bool active;
  final double opacityStart;
  final double opacityEnd;
  final double translateStart;
  final double translateEnd;
  final double initialOffsetY;
  final Curve translationCurve;
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
          translationCurve,
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
  const _ScanRevealingToast({required this.onClosePressed});

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
            key: const Key('scan-figma-revealing-toast'),
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
                      key: Key('scan-figma-revealing-toast-glow'),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Expanded(
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
                                Tooltip(
                                  message: 'Dismiss scan feedback',
                                  child: InkWell(
                                    key: const Key(
                                      'scan-figma-revealing-dismiss',
                                    ),
                                    onTap: onClosePressed,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: SvgPicture.asset(
                                        'assets/scan/reveal_close.svg',
                                        width: 10.5,
                                        height: 10.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SvgPicture.asset(
                              'assets/scan/reveal_spinner.svg',
                              width: 16,
                              height: 16,
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
    required this.onSelectItem,
    required this.onAddThisCard,
    required this.onAddAllCards,
  });

  final List<_ScanItem> items;
  final int? selectedItemId;
  final ValueChanged<_ScanItem> onSelectItem;
  final VoidCallback onAddThisCard;
  final VoidCallback onAddAllCards;

  @override
  Widget build(BuildContext context) {
    final selected = items.firstWhere(
      (item) => item.id == selectedItemId,
      orElse: () => items.first,
    );
    final match = selected.match!;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Review Your Matches',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (items.length > 1)
          Wrap(
            spacing: 8,
            children: [
              for (final item in items)
                ChoiceChip(
                  label: Text(item.match?.name ?? item.pictureLabel),
                  selected: item.id == selected.id,
                  onSelected: (_) => onSelectItem(item),
                ),
            ],
          ),
        const SizedBox(height: 12),
        _ReviewImageComparison(item: selected),
        const SizedBox(height: 12),
        Text(
          'Top matched results',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final candidate in match.candidates)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.style_outlined),
            title: Text(candidate),
            trailing: candidate == match.name ? const Icon(Icons.check) : null,
          ),
        const SizedBox(height: 12),
        _ReviewCollectionItem(matchName: match.name),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onAddThisCard,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Add this card'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: onAddAllCards,
          icon: const Icon(Icons.done_all_outlined),
          label: const Text('Add all cards'),
        ),
      ],
    );
  }
}

class _ReviewImageComparison extends StatelessWidget {
  const _ReviewImageComparison({required this.item});

  final _ScanItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ImageStandIn(
            title: 'Your Picture',
            subtitle: item.pictureLabel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ImageStandIn(
            title: 'Our Match',
            subtitle: item.match?.name ?? '-',
          ),
        ),
      ],
    );
  }
}

class _ImageStandIn extends StatelessWidget {
  const _ImageStandIn({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _ReviewCollectionItem extends StatelessWidget {
  const _ReviewCollectionItem({required this.matchName});

  final String matchName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collection Item',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(matchName),
            const Text('Adding to Main'),
            const Text('Raw'),
            const Text('Near Mint (NM)'),
          ],
        ),
      ),
    );
  }
}
