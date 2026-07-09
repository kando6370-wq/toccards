import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  test('defaults to Cards tab and Pokemon results', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(searchControllerProvider);

    expect(state.selectedTab, SearchTab.cards);
    expect(state.selectedGame.label, 'Pokemon');
    expect(state.visibleCards.map((card) => card.name), [
      'Squirtle',
      'Charizard ex',
      'Mystery Promo',
    ]);
    expect(state.cardById('squirtle').previous30dPriceUsd, 30.67);
    expect(state.cardById('squirtle').changeText, '+4.76%');
    expect(state.cardById('charizard-ex').previous30dPriceUsd, 721.58);
    expect(state.cardById('charizard-ex').changeText, '+8.10%');
    expect(state.visibleSets.map((set) => set.name), [
      'Mega Evolution Promos',
      'Obsidian Flames',
    ]);
  });

  test('repository failure shows page failure and refresh restores search', () {
    final repository = _FailingThenSuccessfulSearchRepository();
    final container = ProviderContainer(
      overrides: [searchRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final failed = container.read(searchControllerProvider);

    expect(failed.loadStatus, KandoLoadStatus.failure);
    expect(failed.isUnavailable, isTrue);
    expect(repository.calls, 1);

    container.read(searchControllerProvider.notifier).refresh();
    final restored = container.read(searchControllerProvider);

    expect(restored.loadStatus, KandoLoadStatus.content);
    expect(restored.isUnavailable, isFalse);
    expect(
      restored.visibleCards.map((card) => card.name),
      contains('Squirtle'),
    );
    expect(repository.calls, 2);
  });

  test('Cards and Sets search state stays independent', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);

    controller.updateSearch('charizard');
    expect(
      container.read(searchControllerProvider).visibleCards.single.name,
      'Charizard ex',
    );

    controller.selectTab(SearchTab.sets);
    expect(container.read(searchControllerProvider).searchText, '');

    controller.updateSearch('mega');
    expect(
      container.read(searchControllerProvider).visibleSets.single.name,
      'Mega Evolution Promos',
    );

    controller.selectTab(SearchTab.cards);
    expect(container.read(searchControllerProvider).searchText, 'charizard');
  });

  test('clear search only affects the current tab', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);

    controller.updateSearch('squirtle');
    controller.selectTab(SearchTab.sets);
    controller.updateSearch('flames');
    controller.clearSearch();

    expect(container.read(searchControllerProvider).searchText, '');
    controller.selectTab(SearchTab.cards);
    expect(container.read(searchControllerProvider).searchText, 'squirtle');
  });

  test('switching game clears current tab search and refreshes results', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);

    controller.updateSearch('squirtle');
    controller.selectGame('lorcana');
    final state = container.read(searchControllerProvider);

    expect(state.selectedGame.label, 'Lorcana');
    expect(state.searchText, '');
    expect(state.visibleCards.map((card) => card.name), ['Lorcana Elsa']);
  });

  test('Collect updates Qty and removes Wishlist state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);

    controller.toggleWishlist('squirtle');
    expect(
      container
          .read(searchControllerProvider)
          .cardById('squirtle')
          .isWishlisted,
      isTrue,
    );

    expect(controller.toggleCollect('squirtle'), SearchCollectAction.updated);
    final collected = container
        .read(searchControllerProvider)
        .cardById('squirtle');

    expect(collected.quantity, 1);
    expect(collected.isCollected, isTrue);
    expect(collected.isWishlisted, isFalse);

    expect(controller.toggleCollect('squirtle'), SearchCollectAction.updated);
    expect(
      container.read(searchControllerProvider).cardById('squirtle').quantity,
      0,
    );
  });

  test(
    'Collect on a card with multiple collection items requests detail management',
    () {
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(
            const _MultiCollectionSearchRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);

      final action = controller.toggleCollect('multi-owned');
      final card = container
          .read(searchControllerProvider)
          .cardById('multi-owned');

      expect(action, SearchCollectAction.openDetail);
      expect(card.quantity, 2);
      expect(card.collectionItemCount, 2);
    },
  );

  test('missing price and change use PRD fallback text', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final card = container
        .read(searchControllerProvider)
        .cardById('mystery-promo');

    expect(card.priceText, '--');
    expect(card.previous30dPriceUsd, isNull);
    expect(card.changeText, '-/-');
  });
}

class _FailingThenSuccessfulSearchRepository implements SearchRepository {
  var calls = 0;

  @override
  SearchCatalog loadCatalog() {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock search unavailable');
    }
    return const MockSearchRepository().loadCatalog();
  }
}

class _MultiCollectionSearchRepository implements SearchRepository {
  const _MultiCollectionSearchRepository();

  @override
  SearchCatalog loadCatalog() {
    return const SearchCatalog(
      games: [SearchGame(id: 'pokemon', label: 'Pokemon')],
      cards: [
        SearchCard(
          id: 'multi-owned',
          gameId: 'pokemon',
          type: SearchCardType.tcg,
          name: 'Multi Owned',
          priceUsd: 10,
          previous30dPriceUsd: 9,
          setName: 'Test Set',
          metadataLine: 'Promo 001',
          variantLine: 'Raw Near Mint (NM)',
          quantity: 2,
          collectionItemCount: 2,
          isWishlisted: false,
        ),
      ],
      sets: [],
    );
  }
}
