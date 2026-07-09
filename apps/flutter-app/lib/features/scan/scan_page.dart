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
      body: SafeArea(
        child: _reviewing
            ? _ReviewMatches(
                items: _matchedItems,
                selectedItemId: _selectedReviewItemId,
                onSelectItem: (item) {
                  setState(() => _selectedReviewItemId = item.id);
                },
                onAddThisCard: _addSelectedItem,
                onAddAllCards: _addAllMatchedItems,
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 16),
                  Icon(
                    Icons.qr_code_scanner_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  _ScanActions(
                    canReview: _canReview,
                    onPhotoPressed: _startPhotoScan,
                    onLibraryPressed: _startLibraryScan,
                    onReviewPressed: _openReview,
                  ),
                  const SizedBox(height: 20),
                  _ScanResults(
                    items: _items,
                    addedItems: _addedItems,
                    lastAddedCount: _lastAddedCount,
                    onReviewItem: _openReview,
                    onRetryItem: _retryScan,
                    onDeleteItem: _deleteScan,
                    onSearchPressed: (item) {
                      _deleteScan(item);
                      context.go('/search');
                    },
                  ),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 2,
        onDestinationSelected: (index) {
          if (index == 0) {
            context.go('/');
            return;
          }
          if (index == 1) {
            context.go('/collection');
            return;
          }
          if (index == 3) {
            context.go('/search');
            return;
          }
          if (index == 4) {
            context.go('/profile');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            label: 'Collection',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ScanActions extends StatelessWidget {
  const _ScanActions({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onPhotoPressed,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Take Photo'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onLibraryPressed,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from Library'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: canReview ? onReviewPressed : null,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Review Your Matches'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: canReview ? onReviewPressed : null,
          child: const Text('Done'),
        ),
      ],
    );
  }
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
