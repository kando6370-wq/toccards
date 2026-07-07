import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';

void main() {
  test('defaults to Portfolio tab and Main folder summary', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(collectionControllerProvider);

    expect(state.selectedTab, CollectionTab.portfolio);
    expect(state.selectedFolder.name, 'Main');
    expect(state.portfolioSummary.totalValueText, r'$1,245');
    expect(state.portfolioSummary.cardCount, 3);
    expect(state.portfolioSummary.gradedCount, 2);
    expect(state.visibleItems.map((item) => item.name), [
      'Charizard ex',
      'Umbreon VMAX',
      'Pikachu Promo',
    ]);
    expect(state.visibleItems.first.source.previous30dPriceUsd, 721.55);
    expect(state.visibleItems.first.changeText, '+8.10%');
  });

  test('switching folders changes only Portfolio scoped items', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.selectFolder('sealed');
    final sealed = container.read(collectionControllerProvider);

    expect(sealed.selectedFolder.name, 'Sealed');
    expect(sealed.visibleItems.map((item) => item.name), [
      'Evolving Skies Booster Box',
    ]);

    controller.selectTab(CollectionTab.wishlist);
    final wishlist = container.read(collectionControllerProvider);

    expect(wishlist.visibleItems.map((item) => item.name), [
      'Lorcana Elsa',
      'One Piece Manga Luffy',
    ]);
  });

  test('search is scoped per tab and current folder', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.updateSearch('umbreon');
    expect(
      container.read(collectionControllerProvider).visibleItems.single.name,
      'Umbreon VMAX',
    );

    controller.selectTab(CollectionTab.wishlist);
    expect(container.read(collectionControllerProvider).searchText, '');

    controller.updateSearch('luffy');
    expect(
      container.read(collectionControllerProvider).visibleItems.single.name,
      'One Piece Manga Luffy',
    );
  });

  test('sort and filters combine for the selected tab', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.applySortAndFilters(
      sort: CollectionSort.valueDesc,
      games: {'Pokemon'},
      languages: {'English'},
    );
    final filtered = container.read(collectionControllerProvider);

    expect(filtered.visibleItems.map((item) => item.name), [
      'Charizard ex',
      'Umbreon VMAX',
    ]);
  });

  test('amount hiding masks money but leaves percentages readable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.toggleAmountHidden();
    final state = container.read(collectionControllerProvider);

    expect(state.portfolioSummary.totalValueText, '••••••');
    expect(state.visibleItems.first.valueText, '••••••');
    expect(state.visibleItems.first.changeText, '+8.10%');
  });

  test('empty and no-match states are distinct', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.selectFolder('empty');
    expect(container.read(collectionControllerProvider).isEmpty, isTrue);
    expect(container.read(collectionControllerProvider).isNoMatch, isFalse);

    controller.selectFolder('main');
    controller.updateSearch('missing');
    expect(container.read(collectionControllerProvider).isEmpty, isFalse);
    expect(container.read(collectionControllerProvider).isNoMatch, isTrue);
  });
}
