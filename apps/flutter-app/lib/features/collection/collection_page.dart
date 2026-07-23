import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

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
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isPageFailure = state.isUnavailable;

            return RefreshIndicator(
              key: const Key('collection-pull-to-refresh'),
              onRefresh: controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: isPageFailure
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (state.loadStatus == KandoLoadStatus.loading)
                    const KandoLoadingBlock()
                  else if (isPageFailure)
                    SizedBox(
                      height: math.max(0.0, constraints.maxHeight),
                      child: KandoFailureBlock(onRefresh: controller.refresh),
                    )
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
                        onFolderPressed: () =>
                            showPortfolioFolderSheet(context, ref),
                        onHidePressed: () async {
                          if (!await controller.toggleAmountHidden() &&
                              context.mounted) {
                            showKandoFailureToast(context);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    _CollectionContent(state: state),
                    const SizedBox(height: 100),
                  ],
                ],
              ),
            );
          },
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
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      KandoColors.accent.withValues(alpha: 0.30),
                      KandoColors.accent.withValues(alpha: 0.10),
                    ],
                  )
                : null,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
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
      key: const Key('collection-portfolio-summary'),
      width: double.infinity,
      height: 142,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 21),
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
          const SizedBox(height: 4),
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
          const SizedBox(height: 4),
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
                child: Text(
                  '•',
                  style: TextStyle(color: KandoColors.mutedText),
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
      return const _CollectionNoMatchState();
    }
    if (state.isEmpty && state.selectedTab == CollectionTab.portfolio) {
      return _CollectionEmptyState(
        illustration: 'assets/collection/portfolio_empty.png',
        illustrationKey: const Key('collection-portfolio-empty-illustration'),
        illustrationHeight: 345,
        title: 'Start your portfolio',
        body: 'Scan or search cards to track value',
        primaryLabel: 'SCAN A CARD',
        primaryIcon: Icons.photo_camera_outlined,
        onPrimary: () => context.go('/scan'),
        secondaryLabel: 'SEARCH A CARD',
        secondaryIcon: Icons.search,
        onSecondary: () => context.go('/search'),
      );
    }
    if (state.isEmpty) {
      return _CollectionEmptyState(
        illustration: 'assets/collection/wishlist_empty.png',
        illustrationKey: const Key('collection-wishlist-empty-illustration'),
        illustrationHeight: 204,
        title: 'Your wishlist is empty',
        body: 'Add cards you want to collect later',
        primaryLabel: 'SEARCH CARDS',
        primaryIcon: Icons.search,
        onPrimary: () => context.go('/search'),
      );
    }

    return _CollectionGrid(
      items: state.visibleItems,
      showQuantity: state.selectedTab == CollectionTab.portfolio,
    );
  }
}

class _CollectionNoMatchState extends StatelessWidget {
  const _CollectionNoMatchState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('collection-no-match-state'),
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          SvgPicture.asset(
            'assets/search/no_content_available.svg',
            width: 100,
            height: 88,
          ),
          const SizedBox(height: 18),
          const Text(
            'No matching cards found.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 20,
              height: 26 / 20,
              fontWeight: FontWeight.w600,
              color: KandoColors.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting your search or filters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 22 / 14,
              color: KandoColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionEmptyState extends StatelessWidget {
  const _CollectionEmptyState({
    required this.illustration,
    required this.illustrationKey,
    required this.illustrationHeight,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
  });

  final String illustration;
  final Key illustrationKey;
  final double illustrationHeight;
  final String title;
  final String body;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          illustration,
          key: illustrationKey,
          width: double.infinity,
          height: illustrationHeight,
          fit: BoxFit.cover,
        ),
        const SizedBox(height: 32),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 24,
            height: 32 / 24,
            fontWeight: FontWeight.w600,
            color: KandoColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 22 / 14,
            color: KandoColors.mutedText,
          ),
        ),
        const SizedBox(height: 28),
        _EmptyStateButton(
          label: primaryLabel,
          icon: primaryIcon,
          onPressed: onPrimary,
          primary: true,
        ),
        if (secondaryLabel != null &&
            secondaryIcon != null &&
            onSecondary != null) ...[
          const SizedBox(height: 16),
          _EmptyStateButton(
            label: secondaryLabel!,
            icon: secondaryIcon!,
            onPressed: onSecondary!,
            primary: false,
          ),
        ],
      ],
    );
  }
}

class _EmptyStateButton extends StatelessWidget {
  const _EmptyStateButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: primary
              ? KandoColors.accent
              : KandoColors.elevatedSurface,
          foregroundColor: primary ? KandoColors.ink : KandoColors.text,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: const StadiumBorder(),
          side: primary
              ? BorderSide.none
              : const BorderSide(color: KandoColors.border),
        ),
      ),
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/cards/${Uri.encodeComponent(item.cardRef)}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xCC1C1E15), Color(0xE612140D)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KandoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 672 / 936,
              child: Container(
                decoration: BoxDecoration(
                  color: KandoColors.ink,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: KandoColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: item.imageUrl == null
                    ? const Icon(
                        Icons.image_outlined,
                        color: KandoColors.mutedText,
                        size: 28,
                      )
                    : Image.network(
                        item.imageUrl!,
                        fit: BoxFit.contain,
                        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        width: double.infinity,
                        height: double.infinity,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.image_outlined,
                              color: KandoColors.mutedText,
                              size: 28,
                            ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: KandoColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.setName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: KandoColors.mutedText,
              ),
            ),
            Text(
              item.number,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: KandoColors.mutedText,
              ),
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
                color: KandoColors.money,
              ),
            ),
            Text(
              item.changeText,
              style: TextStyle(fontSize: 11, color: changeColor),
            ),
          ],
        ),
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
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Fraunces',
          fontSize: 20,
          height: 28 / 20,
          fontWeight: FontWeight.w600,
          color: KandoColors.text,
        ),
      ),
    );
  }
}

Future<void> showPortfolioFolderSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: KandoColors.elevatedSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => Consumer(
      builder: (context, ref, child) {
        final state = ref.watch(collectionControllerProvider);
        final controller = ref.read(collectionControllerProvider.notifier);
        if (state.loadStatus == KandoLoadStatus.loading) {
          return const FractionallySizedBox(
            heightFactor: 0.62,
            child: SafeArea(child: KandoLoadingBlock()),
          );
        }
        if (state.isUnavailable) {
          return FractionallySizedBox(
            heightFactor: 0.62,
            child: SafeArea(
              child: KandoFailureBlock(onRefresh: controller.refresh),
            ),
          );
        }
        final folders = state.dashboard.folders;
        return FractionallySizedBox(
          heightFactor: 0.62,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 6,
                    decoration: BoxDecoration(
                      color: KandoColors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Portfolio',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: KandoColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: folders.length,
                      onReorderItem: (oldIndex, newIndex) async {
                        final ids = folders.map((folder) => folder.id).toList();
                        final moved = ids.removeAt(oldIndex);
                        ids.insert(newIndex, moved);
                        if (!await controller.reorderFolders(ids) &&
                            context.mounted) {
                          _showCollectionActionError(context);
                        }
                      },
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        final selected = folder.id == state.selectedFolder.id;
                        return Padding(
                          key: ValueKey(folder.id),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            height: 72,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? KandoColors.elevatedSurface
                                  : KandoColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? KandoColors.accent.withValues(alpha: 0.3)
                                    : Colors.transparent,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: KandoColors.accent.withValues(
                                          alpha: 0.12,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      size: 20,
                                      color: KandoColors.mutedText,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    key: Key(
                                      'collection-folder-select-${folder.id}',
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () async {
                                      final succeeded = await controller
                                          .selectFolder(folder.id);
                                      if (!context.mounted) return;
                                      if (succeeded) {
                                        Navigator.of(context).pop();
                                      } else {
                                        _showCollectionActionError(context);
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 40,
                                          height: 64,
                                          child: Icon(
                                            selected
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_unchecked,
                                            size: 22,
                                            color: selected
                                                ? KandoColors.accent
                                                : KandoColors.mutedText,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            folder.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: KandoColors.text,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: Key(
                                    'collection-folder-default-${folder.id}',
                                  ),
                                  tooltip: 'Set default portfolio',
                                  onPressed: folder.isDefault
                                      ? null
                                      : () async {
                                          if (!await controller
                                                  .setDefaultFolder(
                                                    folder.id,
                                                  ) &&
                                              context.mounted) {
                                            _showCollectionActionError(context);
                                          }
                                        },
                                  icon: Icon(
                                    folder.isDefault
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 22,
                                    color: folder.isDefault
                                        ? KandoColors.accent
                                        : KandoColors.mutedText,
                                  ),
                                ),
                                IconButton(
                                  key: Key(
                                    'collection-folder-edit-${folder.id}',
                                  ),
                                  tooltip: 'Edit portfolio',
                                  onPressed: () async {
                                    final name = await _promptForFolderName(
                                      context,
                                      initialName: folder.name,
                                      title: 'Edit Portfolio',
                                    );
                                    if (name == null || !context.mounted) {
                                      return;
                                    }
                                    if (!await controller.renameFolder(
                                          folder.id,
                                          name,
                                        ) &&
                                        context.mounted) {
                                      _showCollectionActionError(context);
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 21,
                                    color: KandoColors.mutedText,
                                  ),
                                ),
                                IconButton(
                                  key: Key(
                                    'collection-folder-delete-${folder.id}',
                                  ),
                                  tooltip: 'Delete portfolio',
                                  onPressed: folder.isDefault
                                      ? null
                                      : () async {
                                          final confirmed =
                                              await _confirmDeleteFolder(
                                                context,
                                                folder,
                                              );
                                          if (!confirmed || !context.mounted) {
                                            return;
                                          }
                                          if (!await controller.deleteFolder(
                                                folder.id,
                                              ) &&
                                              context.mounted) {
                                            _showCollectionActionError(context);
                                          }
                                        },
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 21,
                                    color: folder.isDefault
                                        ? KandoColors.border
                                        : KandoColors.mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'DRAG AND DROP TO CHANGE ORDER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: KandoColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('collection-folder-add'),
                      style: FilledButton.styleFrom(
                        backgroundColor: KandoColors.accent,
                        foregroundColor: KandoColors.ink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () async {
                        final name = await _promptForFolderName(
                          context,
                          title: 'Add Portfolio',
                        );
                        if (name == null || !context.mounted) return;
                        if (await controller.createFolder(name) == null &&
                            context.mounted) {
                          _showCollectionActionError(context);
                        }
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('ADD NEW'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<String?> _promptForFolderName(
  BuildContext context, {
  required String title,
  String initialName = '',
}) async {
  var value = initialName;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xBF0D0F08),
    builder: (context) {
      final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: _FolderNameBottomSheet(
          title: title,
          initialName: initialName,
          onChanged: (next) => value = next,
          onSave: () {
            final normalized = value.trim();
            if (normalized.isNotEmpty) {
              Navigator.of(context).pop(normalized);
            }
          },
        ),
      );
    },
  );
}

class _FolderNameBottomSheet extends StatelessWidget {
  const _FolderNameBottomSheet({
    required this.title,
    required this.initialName,
    required this.onChanged,
    required this.onSave,
  });

  final String title;
  final String initialName;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _PortfolioActionSheet(
      key: const Key('collection-folder-name-sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE4E3D3),
              fontFamily: 'Fraunces',
              fontSize: 24,
              fontWeight: FontWeight.w600,
              height: 32 / 24,
              fontVariations: [
                FontVariation('SOFT', 0),
                FontVariation('WONK', 1),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Name of portfolio',
            style: TextStyle(
              color: Color(0xFF92927D),
              fontSize: 11,
              fontWeight: FontWeight.w400,
              height: 18 / 11,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('collection-folder-name'),
            initialValue: initialName,
            onChanged: onChanged,
            autofocus: true,
            maxLength: 50,
            style: const TextStyle(
              color: KandoColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 22 / 15,
            ),
            cursorColor: KandoColors.accent,
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: _folderInputBorder(KandoColors.accent),
              enabledBorder: _folderInputBorder(KandoColors.accent),
              focusedBorder: _folderInputBorder(KandoColors.accent),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _RoundSheetButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Icon(
                  Icons.arrow_back,
                  color: KandoColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PillSheetButton(
                  key: const Key('collection-folder-name-save'),
                  backgroundColor: KandoColors.accent,
                  foregroundColor: KandoColors.primaryOnDefault,
                  label: 'SAVE',
                  onPressed: onSave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

OutlineInputBorder _folderInputBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );
}

class _PortfolioActionSheet extends StatelessWidget {
  const _PortfolioActionSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: KandoColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(
            top: BorderSide(color: KandoColors.accent.withValues(alpha: 0.1)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              offset: Offset(0, -8),
              blurRadius: 28,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: KandoColors.border.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundSheetButton extends StatelessWidget {
  const _RoundSheetButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          shape: BoxShape.circle,
          border: Border.all(color: KandoColors.border.withValues(alpha: 0.4)),
        ),
        child: child,
      ),
    );
  }
}

class _PillSheetButton extends StatelessWidget {
  const _PillSheetButton({
    super.key,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.label,
    required this.onPressed,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: KandoColors.borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 24 / 16,
          ),
        ),
      ),
    );
  }
}

Future<bool> _confirmDeleteFolder(
  BuildContext context,
  CollectionFolder folder,
) async {
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0xBF0D0F08),
        builder: (context) => _PortfolioActionSheet(
          key: const Key('collection-folder-delete-sheet'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this ${folder.name} portfolio?',
                style: const TextStyle(
                  color: KandoColors.errorText,
                  fontFamily: 'Fraunces',
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 32 / 24,
                  fontVariations: [
                    FontVariation('SOFT', 0),
                    FontVariation('WONK', 1),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: _PillSheetButton(
                      backgroundColor: KandoColors.elevatedSurface,
                      foregroundColor: KandoColors.text,
                      label: 'CANCEL',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PillSheetButton(
                      key: const Key('collection-folder-delete-confirm'),
                      backgroundColor: KandoColors.error,
                      foregroundColor: KandoColors.primaryOnDefault,
                      label: 'DELETE',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;
}

void _showCollectionActionError(BuildContext context) {
  showKandoFailureToast(context);
}

Future<void> _showFilterSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(collectionControllerProvider);
  var sort = state.selectedSort == CollectionSort.valueAsc
      ? CollectionSort.valueAsc
      : CollectionSort.valueDesc;
  final games = {...state.selectedGames};
  final languages = {...state.selectedLanguages};
  final languageOptions = <String>{
    'English',
    'Japanese',
    'Chinese',
    ...state.availableLanguages,
  }.toList();
  final gameOptions = state.availableGames;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.76),
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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

          return FractionallySizedBox(
            heightFactor: 0.75,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF222222),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: SafeArea(
                top: false,
                child: ListView(
                  key: const Key('collection-filter-sheet'),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C6945),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filter',
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 32,
                              height: 40 / 32,
                              fontWeight: FontWeight.w600,
                              color: KandoColors.text,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const Key('collection-filter-clear'),
                          onPressed: () {
                            setModalState(() {
                              sort = CollectionSort.valueDesc;
                              games.clear();
                              languages.clear();
                            });
                          },
                          child: const Text(
                            'CLEAR',
                            style: TextStyle(
                              color: KandoColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const _FilterSectionLabel('SORT'),
                    for (final option in const [
                      CollectionSort.valueDesc,
                      CollectionSort.valueAsc,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FilterSortOption(
                          label: _sortLabel(option),
                          selected: sort == option,
                          onTap: () => setModalState(() => sort = option),
                        ),
                      ),
                    const _FilterSectionLabel('LANGUAGE'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final language in languageOptions)
                          _FilterChip(
                            label: language,
                            selected: languages.contains(language),
                            onTap: () => toggle(languages, language),
                          ),
                      ],
                    ),
                    const _FilterSectionLabel('GAME / IP'),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 10.0;
                        final width = (constraints.maxWidth - gap) / 2;
                        return Wrap(
                          spacing: gap,
                          runSpacing: 10,
                          children: [
                            for (final game in gameOptions)
                              SizedBox(
                                width: width,
                                child: _FilterChip(
                                  label: game,
                                  selected: games.contains(game),
                                  onTap: () => toggle(games, game),
                                  expanded: true,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        key: const Key('collection-filter-apply'),
                        style: FilledButton.styleFrom(
                          backgroundColor: KandoColors.accent,
                          foregroundColor: KandoColors.ink,
                          shape: const StadiumBorder(),
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
                          'APPLY FILTERS',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
    CollectionSort.valueDesc => 'Price: High to Low',
    CollectionSort.valueAsc => 'Price: Low to High',
    CollectionSort.changeDesc => '30D gain high to low',
    CollectionSort.nameAsc => 'Name A-Z',
  };
}

class _FilterSortOption extends StatelessWidget {
  const _FilterSortOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF272821) : const Color(0xFF292A23),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? KandoColors.accent.withValues(alpha: 0.5)
                : KandoColors.borderSubtle,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: KandoColors.accent.withValues(alpha: 0.16),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: selected ? KandoColors.text : KandoColors.mutedText,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? KandoColors.accent : KandoColors.border,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.expanded = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? KandoColors.accent : const Color(0xFF1B1D16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? KandoColors.accent : KandoColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (expanded)
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: selected ? KandoColors.ink : KandoColors.mutedText,
                  ),
                ),
              )
            else
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected ? KandoColors.ink : KandoColors.mutedText,
                ),
              ),
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, size: 18, color: KandoColors.ink),
            ] else ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.radio_button_unchecked,
                size: 18,
                color: KandoColors.border,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
