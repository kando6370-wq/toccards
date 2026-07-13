import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'collection_controller.dart';
import 'collection_models.dart';

// Semantic gain/loss colors from the Figma spec. No design token maps to
// financial up/down, so these are defined locally rather than approximated.
const _gainColor = Color(0xFF4ADE80);
const _lossColor = Color(0xFFF87171);

class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectionControllerProvider);
    final controller = ref.read(collectionControllerProvider.notifier);

    return KandoTabScaffold(
      currentTab: KandoMainTab.collection,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (state.loadStatus == KandoLoadStatus.loading)
              const KandoLoadingBlock()
            else if (state.isUnavailable)
              KandoFailureBlock(onRefresh: controller.refresh)
            else ...[
              _SegmentedTabs(
                selected: state.selectedTab,
                onSelect: controller.selectTab,
              ),
              const SizedBox(height: 16),
              _SearchField(
                fieldKey: ValueKey(state.selectedTab),
                onChanged: controller.updateSearch,
                onFilterPressed: () => _showFilterSheet(context, ref),
              ),
              const SizedBox(height: 16),
              if (state.selectedTab == CollectionTab.portfolio) ...[
                _PortfolioSummaryCard(
                  state: state,
                  onFolderPressed: () => _showFolderSheet(context, ref),
                  onHidePressed: controller.toggleAmountHidden,
                ),
                const SizedBox(height: 16),
              ],
              _CollectionContent(state: state),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.selected, required this.onSelect});

  final CollectionTab selected;
  final ValueChanged<CollectionTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: KandoColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KandoColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          _tab(CollectionTab.portfolio, 'Portfolio'),
          _tab(CollectionTab.wishlist, 'Wishlist'),
        ],
      ),
    );
  }

  Widget _tab(CollectionTab tab, String label) {
    final isSelected = selected == tab;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? KandoColors.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: isSelected
                ? Border.all(color: KandoColors.accent.withValues(alpha: 0.5))
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? KandoColors.accent : KandoColors.mutedText,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.fieldKey,
    required this.onChanged,
    required this.onFilterPressed,
  });

  final Key fieldKey;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterPressed;

  @override
  Widget build(BuildContext context) {
    final base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: KandoColors.border),
    );
    return TextField(
      key: fieldKey,
      onChanged: onChanged,
      style: const TextStyle(color: KandoColors.text, fontSize: 15),
      decoration: InputDecoration(
        filled: true,
        fillColor: KandoColors.surface,
        prefixIcon: const Icon(
          Icons.search,
          color: KandoColors.mutedText,
          size: 20,
        ),
        hintText: 'Search cards',
        hintStyle: const TextStyle(color: KandoColors.mutedText, fontSize: 15),
        suffixIcon: IconButton(
          key: const Key('collection-filter-button'),
          onPressed: onFilterPressed,
          icon: const Icon(Icons.tune, color: KandoColors.mutedText, size: 20),
        ),
        border: base,
        enabledBorder: base,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: KandoColors.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

class _PortfolioSummaryCard extends StatelessWidget {
  const _PortfolioSummaryCard({
    required this.state,
    required this.onFolderPressed,
    required this.onHidePressed,
  });

  final CollectionState state;
  final VoidCallback onFolderPressed;
  final VoidCallback onHidePressed;

  @override
  Widget build(BuildContext context) {
    final summary = state.portfolioSummary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KandoColors.accent.withValues(alpha: 0.10),
            KandoColors.surface.withValues(alpha: 0.30),
          ],
        ),
        color: KandoColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KandoColors.accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PORTFOLIO',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.6,
                    color: KandoColors.mutedText,
                  ),
                ),
              ),
              _FolderButton(
                name: state.selectedFolder.name,
                onPressed: onFolderPressed,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                  summary.totalValueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: KandoColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _HideAmountButton(
                hidden: state.amountHidden,
                onPressed: onHidePressed,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${summary.cardCount} cards',
                style: const TextStyle(
                  fontSize: 14,
                  color: KandoColors.mutedText,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('•', style: TextStyle(color: KandoColors.mutedText)),
              ),
              Text(
                '${summary.gradedCount} graded',
                style: const TextStyle(
                  fontSize: 14,
                  color: KandoColors.mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderButton extends StatelessWidget {
  const _FolderButton({required this.name, required this.onPressed});

  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: KandoColors.accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: KandoColors.accent.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, size: 14, color: KandoColors.accent),
            const SizedBox(width: 4),
            Text(
              name,
              style: const TextStyle(
                fontSize: 15,
                color: KandoColors.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HideAmountButton extends StatelessWidget {
  const _HideAmountButton({required this.hidden, required this.onPressed});

  final bool hidden;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('collection-hide-amount'),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 18,
        color: KandoColors.mutedText,
      ),
    );
  }
}

class _CollectionContent extends StatelessWidget {
  const _CollectionContent({required this.state});

  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    if (state.isNoMatch) {
      return const KandoEmptyBlock(title: 'No matching cards found.');
    }
    if (state.isEmpty && state.selectedTab == CollectionTab.portfolio) {
      return KandoEmptyBlock(
        title: 'No cards in this portfolio yet.',
        body: 'Scan or search cards to start tracking your collection.',
        primaryLabel: 'Scan a Card',
        onPrimary: () => context.go('/scan'),
        secondaryLabel: 'Search Cards',
        onSecondary: () => context.go('/search'),
      );
    }
    if (state.isEmpty) {
      return KandoEmptyBlock(
        title: 'Your wishlist is empty.',
        body:
            'Save cards you want to collect later and keep an eye on their market value.',
        primaryLabel: 'Search Cards',
        onPrimary: () => context.go('/search'),
      );
    }

    return _CollectionGrid(
      items: state.visibleItems,
      showQuantity: state.selectedTab == CollectionTab.portfolio,
    );
  }
}

class _CollectionGrid extends StatelessWidget {
  const _CollectionGrid({required this.items, required this.showQuantity});

  final List<CollectionViewItem> items;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: tileWidth,
                child: _CollectionCardTile(
                  item: item,
                  showQuantity: showQuantity,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CollectionCardTile extends StatelessWidget {
  const _CollectionCardTile({required this.item, required this.showQuantity});

  final CollectionViewItem item;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    final trimmed = item.changeText.trimLeft();
    final changeColor = trimmed.startsWith('-')
        ? _lossColor
        : trimmed.startsWith('+')
        ? _gainColor
        : KandoColors.mutedText;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KandoColors.elevatedSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KandoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              decoration: BoxDecoration(
                color: KandoColors.ink,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KandoColors.border),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_outlined,
                color: KandoColors.mutedText,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KandoColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.setName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: KandoColors.mutedText),
          ),
          Text(
            item.number,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: KandoColors.mutedText),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: item.statusText,
                  style: const TextStyle(color: KandoColors.accent),
                ),
                const TextSpan(
                  text: '  ·  ',
                  style: TextStyle(color: KandoColors.mutedText),
                ),
                TextSpan(
                  text: item.finish,
                  style: const TextStyle(color: KandoColors.mutedText),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          if (showQuantity) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 12,
                  color: KandoColors.mutedText,
                ),
                const SizedBox(width: 4),
                Text(
                  'Qty: ${item.quantity}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: KandoColors.mutedText,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            item.valueText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KandoColors.text,
            ),
          ),
          Text(
            item.changeText,
            style: TextStyle(fontSize: 11, color: changeColor),
          ),
        ],
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: KandoColors.mutedText,
        ),
      ),
    );
  }
}

Future<void> _showFolderSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(collectionControllerProvider);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: KandoColors.elevatedSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KandoColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Folders',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KandoColors.text,
                ),
              ),
            ),
          ),
          for (final folder in state.dashboard.folders)
            ListTile(
              title: Text(
                folder.name,
                style: const TextStyle(color: KandoColors.text),
              ),
              trailing: folder.id == state.selectedFolder.id
                  ? const Icon(Icons.check, color: KandoColors.accent)
                  : null,
              onTap: () {
                ref
                    .read(collectionControllerProvider.notifier)
                    .selectFolder(folder.id);
                Navigator.of(context).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _showFilterSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(collectionControllerProvider);
  var sort = state.selectedSort;
  final games = {...state.selectedGames};
  final languages = {...state.selectedLanguages};

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: KandoColors.elevatedSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          void toggle(Set<String> target, String value) {
            setModalState(() {
              if (target.contains(value)) {
                target.remove(value);
              } else {
                target.add(value);
              }
            });
          }

          Widget chip(String label, bool selected, VoidCallback onTap) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected ? KandoColors.accent : KandoColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? KandoColors.accent : KandoColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: selected ? KandoColors.ink : KandoColors.text,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: KandoColors.ink,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: KandoColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Filter',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: KandoColors.text,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref
                            .read(collectionControllerProvider.notifier)
                            .clearFilters();
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'Clear',
                        style: TextStyle(
                          color: KandoColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const _FilterSectionLabel('SORT'),
                for (final option in CollectionSort.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setModalState(() => sort = option),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: KandoColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sort == option
                                ? KandoColors.accent.withValues(alpha: 0.6)
                                : KandoColors.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _sortLabel(option),
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: KandoColors.text,
                                ),
                              ),
                            ),
                            Icon(
                              sort == option
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: sort == option
                                  ? KandoColors.accent
                                  : KandoColors.mutedText,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const _FilterSectionLabel('LANGUAGE'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final language in const ['English', 'Japanese'])
                      chip(
                        language,
                        languages.contains(language),
                        () => toggle(languages, language),
                      ),
                  ],
                ),
                const _FilterSectionLabel('GAME / IP'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final game in const ['Pokemon', 'Lorcana', 'One Piece'])
                      chip(
                        game,
                        games.contains(game),
                        () => toggle(games, game),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: KandoColors.accent,
                      foregroundColor: KandoColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () {
                      ref
                          .read(collectionControllerProvider.notifier)
                          .applySortAndFilters(
                            sort: sort,
                            games: games,
                            languages: languages,
                          );
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'Apply',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _sortLabel(CollectionSort sort) {
  return switch (sort) {
    CollectionSort.newest => 'Newest',
    CollectionSort.valueDesc => 'Value high to low',
    CollectionSort.changeDesc => '30D gain high to low',
    CollectionSort.nameAsc => 'Name A-Z',
  };
}
