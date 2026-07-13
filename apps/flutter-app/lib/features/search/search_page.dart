import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';

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
              _SearchHeader(
                selectedGame: state.selectedGame,
                onGamePressed: () => _showGameSheet(context, ref),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey(
                  'search-field-${state.selectedTab}-${state.searchText}',
                ),
                initialValue: state.searchText,
                decoration: InputDecoration(
                  hintText: 'Search cards, sets, or characters',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.hasQuery)
                        IconButton(
                          key: const Key('search-clear-button'),
                          onPressed: controller.clearSearch,
                          icon: const Icon(Icons.close),
                        ),
                      IconButton(
                        onPressed: () => context.go('/scan'),
                        icon: const Icon(Icons.qr_code_scanner_outlined),
                      ),
                    ],
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: controller.updateSearch,
              ),
              const SizedBox(height: 12),
              SegmentedButton<SearchTab>(
                segments: const [
                  ButtonSegment(value: SearchTab.cards, label: Text('Cards')),
                  ButtonSegment(value: SearchTab.sets, label: Text('Sets')),
                ],
                selected: {state.selectedTab},
                onSelectionChanged: (selection) {
                  controller.selectTab(selection.single);
                },
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

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.selectedGame,
    required this.onGamePressed,
  });

  final SearchGame selectedGame;
  final VoidCallback onGamePressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Search',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: KandoColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onGamePressed,
          icon: const Icon(Icons.style_outlined),
          label: Text(selectedGame.label),
        ),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isNoMatch) {
      return const KandoEmptyBlock(
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
      crossAxisSpacing: 12,
      childAspectRatio: 1.2,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final card in state.visibleCards) _SearchCardTile(card: card),
      ],
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

    return Card(
      key: Key('search-card-${card.id}'),
      child: InkWell(
        onTap: () => context.go('/cards/${card.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: KandoColors.border),
                  ),
                  child: Icon(
                    Icons.style_outlined,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(card.setName, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                card.metadataLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                card.variantLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(card.priceText),
                  const Spacer(),
                  Text(card.changeText),
                ],
              ),
              const SizedBox(height: 6),
              Text('Qty: ${card.quantity}'),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      final action = controller.toggleCollect(card.id);
                      if (action == SearchCollectAction.openDetail) {
                        context.go('/cards/${card.id}');
                      }
                    },
                    child: Text(card.isCollected ? 'Collected' : 'Collect'),
                  ),
                  const Spacer(),
                  IconButton(
                    key: Key('search-wishlist-${card.id}'),
                    onPressed: () => controller.toggleWishlist(card.id),
                    icon: Icon(
                      showFilledHeart ? Icons.favorite : Icons.favorite_border,
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

class _SearchSetRow extends StatelessWidget {
  const _SearchSetRow({required this.set});

  final SearchSet set;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.layers_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    set.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(set.subtitle),
                  Text('${set.releaseText} · ${set.cardCountText}'),
                ],
              ),
            ),
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
