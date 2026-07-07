import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';

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
    expect(state.visibleSets.map((set) => set.name), [
      'Mega Evolution Promos',
      'Obsidian Flames',
    ]);
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

    controller.toggleCollect('squirtle');
    final collected = container
        .read(searchControllerProvider)
        .cardById('squirtle');

    expect(collected.quantity, 1);
    expect(collected.isCollected, isTrue);
    expect(collected.isWishlisted, isFalse);

    controller.toggleCollect('squirtle');
    expect(
      container.read(searchControllerProvider).cardById('squirtle').quantity,
      0,
    );
  });

  test('missing price and change use PRD fallback text', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final card = container
        .read(searchControllerProvider)
        .cardById('mystery-promo');

    expect(card.priceText, '--');
    expect(card.changeText, '-/-');
  });
}
