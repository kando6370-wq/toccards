import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import 'search_controller.dart';
import 'search_models.dart';

class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);

    return KandoTabScaffold(
      currentTab: KandoMainTab.search,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.isLoading) ...[
              Text('Search', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              const KandoLoadingBlock(),
            ] else if (state.isUnavailable) ...[
              Text('Search', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              KandoFailureBlock(onRefresh: controller.refresh),
            ] else ...[
              TextFormField(
                key: ValueKey(
                  'search-field-${state.selectedTab}-${state.searchText}',
                ),
                initialValue: state.searchText,
                style: const TextStyle(fontSize: 15, color: KandoColors.text),
                decoration: InputDecoration(
                  hintText: 'Search cards, sets, or characters',
                  hintStyle: const TextStyle(
                    fontSize: 15,
                    color: KandoColors.mutedText,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  filled: true,
                  fillColor: KandoColors.surface,
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: KandoColors.mutedText,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.hasQuery)
                        IconButton(
                          key: const Key('search-clear-button'),
                          onPressed: controller.clearSearch,
                          icon: const Icon(Icons.close, size: 20),
                          color: KandoColors.mutedText,
                        ),
                      IconButton(
                        onPressed: () => context.go('/scan'),
                        icon: const Icon(
                          Icons.qr_code_scanner_outlined,
                          size: 20,
                        ),
                        color: KandoColors.accent,
                      ),
                    ],
                  ),
                  border: _inputBorder(KandoColors.border),
                  enabledBorder: _inputBorder(KandoColors.border),
                  focusedBorder: _inputBorder(KandoColors.accent),
                ),
                onChanged: controller.updateSearch,
              ),
              const SizedBox(height: 12),
              _GameSelectorField(
                selectedGame: state.selectedGame,
                onPressed: () => _showGameSheet(context, ref),
              ),
              const SizedBox(height: 16),
              _SearchTabs(
                selected: state.selectedTab,
                onSelect: controller.selectTab,
              ),
              const SizedBox(height: 16),
              _SearchResults(state: state),
            ],
          ],
        ),
      ),
    );
  }
}

OutlineInputBorder _inputBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color),
  );
}

class _GameSelectorField extends StatelessWidget {
  const _GameSelectorField({
    required this.selectedGame,
    required this.onPressed,
  });

  final SearchGame selectedGame;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KandoColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KandoColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.style_outlined,
                size: 20,
                color: KandoColors.mutedText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedGame.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: KandoColors.text),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: KandoColors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchTabs extends StatelessWidget {
  const _SearchTabs({required this.selected, required this.onSelect});

  final SearchTab selected;
  final ValueChanged<SearchTab> onSelect;

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
          Expanded(
            child: _SearchTabButton(
              label: 'Cards',
              isSelected: selected == SearchTab.cards,
              onTap: () => onSelect(SearchTab.cards),
            ),
          ),
          Expanded(
            child: _SearchTabButton(
              label: 'Sets',
              isSelected: selected == SearchTab.sets,
              onTap: () => onSelect(SearchTab.sets),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTabButton extends StatelessWidget {
  const _SearchTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? KandoColors.accent.withValues(alpha: 0.22)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: Alignment.center,
          height: 42,
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

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isCurrentSearchUnavailable) {
      return KandoFailureBlock(
        onRefresh: ref.read(searchControllerProvider.notifier).retrySearch,
      );
    }

    if (state.isNoMatch) {
      return const _SearchEmptyState(
        title: 'No results found',
        body: 'Try a different keyword',
      );
    }

    if (state.selectedTab == SearchTab.sets) {
      return Column(
        children: [
          for (final set in state.visibleSets) _SearchSetRow(set: set),
        ],
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 12,
      crossAxisSpacing: 10,
      childAspectRatio: 0.5,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final card in state.visibleCards) _SearchCardTile(card: card),
      ],
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 72,
            color: KandoColors.accent.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: KandoColors.text,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 12),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 20 / 14,
                letterSpacing: 0.2,
                color: KandoColors.mutedText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchCardTile extends ConsumerWidget {
  const _SearchCardTile({required this.card});

  final SearchCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchControllerProvider.notifier);
    final showFilledHeart = card.isWishlisted && !card.isCollected;
    final change = card.changeText;
    final changeColor = change.startsWith('-')
        ? Theme.of(context).colorScheme.error
        : (change.startsWith('+') ? KandoColors.accent : KandoColors.mutedText);

    const mutedLine = TextStyle(
      fontSize: 11,
      height: 18 / 11,
      color: KandoColors.mutedText,
    );

    return Material(
      key: Key('search-card-${card.id}'),
      color: KandoColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.go('/cards/${card.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KandoColors.border),
          ),
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: KandoColors.ink,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: KandoColors.border),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: card.imageUrl == null
                              ? const Icon(
                                  Icons.style_outlined,
                                  color: KandoColors.mutedText,
                                )
                              : Image.network(
                                  card.imageUrl!,
                                  fit: BoxFit.contain,
                                  webHtmlElementStrategy:
                                      WebHtmlElementStrategy.prefer,
                                  semanticLabel: card.name,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.style_outlined,
                                      color: KandoColors.mutedText,
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Row(
                        children: [
                          _SearchCardActionButton(
                            key: Key('search-collect-${card.id}'),
                            tooltip: card.isCollected ? 'Collected' : 'Collect',
                            icon: card.isCollected
                                ? Icons.add_to_photos
                                : Icons.add_to_photos_outlined,
                            selected: card.isCollected,
                            onPressed: () async {
                              final action = await controller.toggleCollect(
                                card.id,
                              );
                              if (action == SearchCollectAction.openDetail) {
                                if (context.mounted) {
                                  context.go('/cards/${card.id}');
                                }
                              } else if (action ==
                                      SearchCollectAction.ignored &&
                                  context.mounted) {
                                showKandoFailureToast(context);
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          _SearchCardActionButton(
                            key: Key('search-wishlist-${card.id}'),
                            tooltip: showFilledHeart
                                ? 'Remove from wishlist'
                                : 'Add to wishlist',
                            icon: showFilledHeart
                                ? Icons.favorite
                                : Icons.favorite_border,
                            selected: showFilledHeart,
                            onPressed: () async {
                              final succeeded = await controller.toggleWishlist(
                                card.id,
                              );
                              if (!succeeded && context.mounted) {
                                showKandoFailureToast(context);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w600,
                  color: KandoColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                card.setName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mutedLine,
              ),
              Text(
                card.metadataLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mutedLine,
              ),
              if (card.variantLine.isNotEmpty)
                Text(
                  card.variantLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mutedLine,
                ),
              Text('Qty: ${card.quantity}', style: mutedLine),
              const SizedBox(height: 6),
              Text(
                card.priceText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 24 / 14,
                  fontWeight: FontWeight.w600,
                  color: KandoColors.text,
                ),
              ),
              Text(
                change,
                style: TextStyle(
                  fontSize: 10,
                  height: 14 / 10,
                  color: changeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchCardActionButton extends StatelessWidget {
  const _SearchCardActionButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? KandoColors.accent.withValues(alpha: 0.28)
            : KandoColors.elevatedSurface.withValues(alpha: 0.82),
        shape: BoxShape.circle,
        border: Border.all(color: KandoColors.borderSubtle, width: 0.5),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        color: selected ? KandoColors.accent : KandoColors.text,
        icon: Icon(icon),
      ),
    );
  }
}

class _SearchSetRow extends StatelessWidget {
  const _SearchSetRow({required this.set});

  final SearchSet set;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(
        '/sets/${Uri.encodeComponent(set.id)}'
        '?game=${Uri.encodeQueryComponent(set.game)}'
        '&name=${Uri.encodeQueryComponent(set.name)}',
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: KandoColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KandoColors.border),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: KandoColors.ink,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KandoColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: set.imageUrl == null
                  ? const Icon(
                      Icons.layers_outlined,
                      color: KandoColors.mutedText,
                    )
                  : Image.network(
                      set.imageUrl!,
                      fit: BoxFit.contain,
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.layers_outlined,
                        color: KandoColors.mutedText,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    set.name,
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
                    set.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: KandoColors.mutedText,
                    ),
                  ),
                  Text(
                    '${set.releaseText} · ${set.cardCountText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: KandoColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: KandoColors.mutedText),
          ],
        ),
      ),
    );
  }
}

Future<void> _showGameSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(searchControllerProvider);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final game in state.catalog.games)
              ListTile(
                title: Text(game.label),
                trailing: game.id == state.selectedGame.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  ref
                      .read(searchControllerProvider.notifier)
                      .selectGame(game.id);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}
