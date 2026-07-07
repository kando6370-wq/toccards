import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import 'collection_controller.dart';
import 'collection_models.dart';

class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectionControllerProvider);
    final controller = ref.read(collectionControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CollectionHeader(
              state: state,
              onFolderPressed: () => _showFolderSheet(context, ref),
              onHidePressed: controller.toggleAmountHidden,
            ),
            const SizedBox(height: 16),
            if (state.isUnavailable)
              KandoFailureBlock(onRefresh: controller.refresh)
            else ...[
              SegmentedButton<CollectionTab>(
                segments: const [
                  ButtonSegment(
                    value: CollectionTab.portfolio,
                    label: Text('Portfolio'),
                  ),
                  ButtonSegment(
                    value: CollectionTab.wishlist,
                    label: Text('Wishlist'),
                  ),
                ],
                selected: {state.selectedTab},
                onSelectionChanged: (selection) {
                  controller.selectTab(selection.single);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey(state.selectedTab),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search cards',
                  border: OutlineInputBorder(),
                ),
                onChanged: controller.updateSearch,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _SummaryText(state: state)),
                  IconButton(
                    key: const Key('collection-filter-button'),
                    onPressed: () => _showFilterSheet(context, ref),
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CollectionContent(state: state),
            ],
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (index) {
          if (index == 0) {
            context.go('/');
            return;
          }
          if (index == 3) {
            context.go('/search');
            return;
          }
          if (index == 4) {
            context.go('/profile');
            return;
          }
          if (index != 1) {
            showKandoToast(context, message: 'This section is coming soon.');
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

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.state,
    required this.onFolderPressed,
    required this.onHidePressed,
  });

  final CollectionState state;
  final VoidCallback onFolderPressed;
  final VoidCallback onHidePressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Collection',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (!state.isUnavailable)
                TextButton(
                  onPressed: onFolderPressed,
                  child: Text(state.selectedFolder.name),
                ),
            ],
          ),
        ),
        IconButton(
          key: const Key('collection-hide-amount'),
          onPressed: state.isUnavailable ? null : onHidePressed,
          icon: Icon(
            state.amountHidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ],
    );
  }
}

class _SummaryText extends StatelessWidget {
  const _SummaryText({required this.state});

  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    if (state.selectedTab == CollectionTab.wishlist) {
      return Text('${state.visibleItems.length} wishlist cards');
    }

    final summary = state.portfolioSummary;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        Text(summary.totalValueText),
        Text('${summary.cardCount} cards'),
        Text('${summary.gradedCount} graded'),
      ],
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
        onPrimary: () {},
        secondaryLabel: 'Search Cards',
        onSecondary: () {},
      );
    }
    if (state.isEmpty) {
      return KandoEmptyBlock(
        title: 'Your wishlist is empty.',
        body:
            'Save cards you want to collect later and keep an eye on their market value.',
        primaryLabel: 'Search Cards',
        onPrimary: () {},
      );
    }

    return Column(
      children: [
        for (final item in state.visibleItems)
          _CollectionCardRow(
            item: item,
            showQuantity: state.selectedTab == CollectionTab.portfolio,
          ),
      ],
    );
  }
}

class _CollectionCardRow extends StatelessWidget {
  const _CollectionCardRow({required this.item, required this.showQuantity});

  final CollectionViewItem item;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('${item.setName} · ${item.number}'),
                  Text(
                    '${item.language} · ${item.finish} · ${item.statusText}',
                  ),
                  if (showQuantity) Text('Qty: ${item.quantity}'),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [Text(item.valueText), Text(item.changeText)],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showFolderSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(collectionControllerProvider);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final folder in state.dashboard.folders)
            ListTile(
              title: Text(folder.name),
              trailing: folder.id == state.selectedFolder.id
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref
                    .read(collectionControllerProvider.notifier)
                    .selectFolder(folder.id);
                Navigator.of(context).pop();
              },
            ),
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

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Sort'),
                for (final option in CollectionSort.values)
                  ListTile(
                    title: Text(_sortLabel(option)),
                    trailing: sort == option ? const Icon(Icons.check) : null,
                    onTap: () {
                      setModalState(() => sort = option);
                    },
                  ),
                const Text('Game / IP'),
                for (final game in const ['Pokemon', 'Lorcana', 'One Piece'])
                  CheckboxListTile(
                    title: Text(game),
                    value: games.contains(game),
                    onChanged: (_) => toggle(games, game),
                  ),
                const Text('Language'),
                for (final language in const ['English', 'Japanese'])
                  CheckboxListTile(
                    title: Text(language),
                    value: languages.contains(language),
                    onChanged: (_) => toggle(languages, language),
                  ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        ref
                            .read(collectionControllerProvider.notifier)
                            .clearFilters();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
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
                      child: const Text('Apply'),
                    ),
                  ],
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
