import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum _ScanItemStatus { scanning, matched, failed, noMatch, added }

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

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final List<_ScanItem> _items = [];
  final List<Timer> _scanTimers = [];

  var _nextScanId = 1;
  var _photoScanCount = 0;
  var _reviewing = false;
  int? _selectedReviewItemId;
  int? _lastAddedCount;

  bool get _hasScanning {
    return _items.any((item) => item.status == _ScanItemStatus.scanning);
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

  bool get _canReview {
    return !_hasScanning && _matchedItems.isNotEmpty;
  }

  @override
  void dispose() {
    for (final timer in _scanTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  void _startPhotoScan() {
    _photoScanCount += 1;
    final result = _photoScanCount == 2
        ? _ScanItemStatus.failed
        : _ScanItemStatus.matched;
    final match = _photoScanCount >= 3
        ? const _ScanMatch(
            name: 'Charizard ex',
            candidates: ['Charizard ex', 'Charmander Promo', 'Charmeleon'],
          )
        : const _ScanMatch(
            name: 'Mega Lucario ex',
            candidates: ['Mega Lucario ex', 'Lucario ex', 'Riolu Promo'],
          );
    _addScan(
      result: result,
      match: result == _ScanItemStatus.matched ? match : null,
    );
  }

  void _startLibraryScan() {
    _addScan(result: _ScanItemStatus.noMatch);
  }

  void _retryScan(_ScanItem item) {
    _replaceItem(item.copyWith(status: _ScanItemStatus.scanning));
    _scheduleResult(
      item.id,
      result: _ScanItemStatus.matched,
      match: const _ScanMatch(
        name: 'Mega Lucario ex',
        candidates: ['Mega Lucario ex', 'Lucario ex', 'Riolu Promo'],
      ),
    );
  }

  void _deleteScan(_ScanItem item) {
    setState(() {
      _items.removeWhere((candidate) => candidate.id == item.id);
      if (_selectedReviewItemId == item.id) {
        _selectedReviewItemId = _matchedItems.firstOrNull?.id;
      }
    });
  }

  void _addScan({_ScanItemStatus? result, _ScanMatch? match}) {
    final id = _nextScanId;
    _nextScanId += 1;
    setState(() {
      _lastAddedCount = null;
      _items.add(
        _ScanItem(
          id: id,
          pictureLabel: 'Scan $id',
          status: _ScanItemStatus.scanning,
        ),
      );
    });
    _scheduleResult(
      id,
      result: result ?? _ScanItemStatus.matched,
      match: match,
    );
  }

  void _scheduleResult(
    int itemId, {
    required _ScanItemStatus result,
    _ScanMatch? match,
  }) {
    final timer = Timer(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }
      final existing = _items.where((item) => item.id == itemId).firstOrNull;
      if (existing == null || existing.status != _ScanItemStatus.scanning) {
        return;
      }
      _replaceItem(existing.copyWith(status: result, match: match));
    });
    _scanTimers.add(timer);
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
              onClosePressed: () => context.go('/'),
              onSearchPressed: () => context.go('/search'),
              onPhotoPressed: _startPhotoScan,
              onLibraryPressed: _startLibraryScan,
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
    required this.onClosePressed,
    required this.onSearchPressed,
    required this.onPhotoPressed,
    required this.onLibraryPressed,
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
  final VoidCallback onClosePressed;
  final VoidCallback onSearchPressed;
  final VoidCallback onPhotoPressed;
  final VoidCallback onLibraryPressed;
  final VoidCallback onReviewPressed;
  final ValueChanged<int?> onReviewItem;
  final ValueChanged<_ScanItem> onRetryItem;
  final ValueChanged<_ScanItem> onDeleteItem;
  final ValueChanged<_ScanItem> onSearchItem;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _CameraBackdrop()),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.86,
                colors: [
                  Colors.transparent,
                  const Color(0xFF0D0F08).withValues(alpha: 0.86),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Column(
              children: [
                _ScanTopBar(
                  onClosePressed: onClosePressed,
                  onSearchPressed: onSearchPressed,
                ),
                const SizedBox(height: 8),
                const _AlignCardPill(),
              ],
            ),
          ),
        ),
        const Positioned.fill(
          top: 150,
          bottom: 252,
          child: Center(child: _ViewfinderCorners()),
        ),
        if (items.isNotEmpty)
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
      ],
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
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Close Scan',
              onPressed: onClosePressed,
              color: const Color(0xFFEEECD8),
              icon: const Icon(Icons.close),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF222222).withValues(alpha: 0.82),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.flash_on,
              color: Color(0xFFEEECD8),
              size: 18,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Search Cards',
              onPressed: onSearchPressed,
              color: const Color(0xFFEEECD8),
              icon: const Icon(Icons.search),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.center_focus_strong, color: Color(0xFFF0FE6F), size: 16),
          SizedBox(width: 10),
          Text(
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _ScanSideAction(
          label: 'GALLERY',
          tooltip: 'Choose from Library',
          icon: Icons.photo_library_outlined,
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
              child: Icon(
                Icons.check,
                color: canReview
                    ? const Color(0xFFEEECD8)
                    : const Color(0x66EEECD8),
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
                style: TextStyle(fontSize: 13, height: 16 / 13),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScanSideAction extends StatelessWidget {
  const _ScanSideAction({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
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
              icon: Icon(icon),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEEECD8),
              fontSize: 13,
              height: 16 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderCorners extends StatelessWidget {
  const _ViewfinderCorners();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 400,
      child: CustomPaint(painter: _ViewfinderPainter()),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraBackdrop extends StatelessWidget {
  const _CameraBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CameraBackdropPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _CameraBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF201E16), Color(0xFF080907)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final binderPaint = Paint()..color = const Color(0x8033382E);
    for (var row = 0; row < 3; row += 1) {
      for (var column = 0; column < 2; column += 1) {
        final rect = Rect.fromLTWH(
          22 + column * (size.width / 2),
          70 + row * 224,
          size.width / 2 - 36,
          188,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
          binderPaint,
        );
      }
    }

    final streakPaint = Paint()
      ..color = const Color(0x26EEECD8)
      ..strokeWidth = 1;
    for (var index = 0; index < 18; index += 1) {
      final y = 40.0 + index * 46;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 28), streakPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
