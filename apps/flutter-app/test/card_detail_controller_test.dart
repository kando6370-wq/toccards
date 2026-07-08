import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_models.dart';
import 'package:kando_app/features/card_detail/card_detail_repository.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  test('uncollected detail exposes card identity and price overview', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(cardDetailControllerProvider('squirtle'));

    expect(state.isUnavailable, isFalse);
    expect(state.detail.name, 'Squirtle');
    expect(state.detail.game, 'Pokemon');
    expect(state.detail.setName, 'Mega Evolution Promos');
    expect(state.detail.identityLine, 'Promo #039');
    expect(state.detail.finish, 'Holofoil');
    expect(state.detail.language, 'English');
    expect(state.marketPriceText, r'$32.13');
    expect(state.changeText, '+4.76%');
    expect(state.detail.isCollected, isFalse);
  });

  test(
    'selected currency converts market price without changing percentage',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container
            .read(cardDetailControllerProvider('squirtle'))
            .marketPriceText,
        r'$32.13',
      );

      container.read(selectedCurrencyProvider.notifier).select(AppCurrency.eur);
      final state = container.read(cardDetailControllerProvider('squirtle'));

      expect(
        state.marketPriceText,
        CurrencyFormatter(currency: AppCurrency.eur).formatUsd(32.13),
      );
      expect(state.changeText, '+4.76%');
    },
  );

  test('missing price and change use CardDetail fallback copy', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(cardDetailControllerProvider('mystery-promo'));

    expect(state.detail.name, 'Mystery Promo');
    expect(state.marketPriceText, '--');
    expect(state.changeText, '-/-');
    expect(state.marketRows.single.priceText, '--');
    expect(state.marketRows.single.changeText, '-/-');
  });

  test('quick Collect marks card collected and clears Wishlist', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('one-piece-luffy');
    final controller = container.read(provider.notifier);

    expect(container.read(provider).detail.isWishlisted, isTrue);

    controller.quickCollect();
    final collected = container.read(provider).detail;

    expect(collected.quantity, 1);
    expect(collected.isCollected, isTrue);
    expect(collected.isWishlisted, isFalse);
  });

  test('owned detail exposes collection item rows', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(cardDetailControllerProvider('charizard-ex'));

    expect(state.detail.isCollected, isTrue);
    expect(state.detail.quantity, 1);
    expect(state.collectionItemRows.single.portfolioName, 'Main');
    expect(state.collectionItemRows.single.quantityText, 'Qty: 1');
    expect(state.collectionItemRows.single.statusText, 'PSA 10');
    expect(state.collectionItemRows.single.purchasePriceText, r'$650.00');
    expect(state.collectionItemRows.single.notes, contains('Obsidian Flames'));
  });

  test(
    'quick Collect creates a default collection item and clears Wishlist',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('one-piece-luffy');

      container.read(provider.notifier).quickCollect();
      final state = container.read(provider);

      expect(state.detail.isCollected, isTrue);
      expect(state.detail.isWishlisted, isFalse);
      expect(state.collectionItemRows.single.portfolioName, 'Main');
      expect(state.collectionItemRows.single.statusText, 'Raw / Near Mint');
      expect(state.collectionItemRows.single.purchasePriceText, '--');
    },
  );

  test('adding a Collection Item appends an owned row and clears Wishlist', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('squirtle');
    final controller = container.read(provider.notifier);

    controller.startAddingCollectionItem();
    controller.updateCollectionItemDraft(
      quantityText: '2',
      portfolioName: 'Sealed',
      grader: 'Raw',
      condition: 'Lightly Played',
      purchasePriceText: '12.50',
      notes: 'Second binder copy.',
    );

    expect(controller.saveCollectionItemDraft(), isTrue);
    final state = container.read(provider);

    expect(state.detail.isCollected, isTrue);
    expect(state.detail.quantity, 2);
    expect(state.detail.isWishlisted, isFalse);
    expect(state.collectionItemRows.single.portfolioName, 'Sealed');
    expect(state.collectionItemRows.single.quantityText, 'Qty: 2');
    expect(state.collectionItemRows.single.statusText, 'Raw / Lightly Played');
    expect(state.collectionItemRows.single.purchasePriceText, r'$12.50');
    expect(state.collectionItemRows.single.notes, 'Second binder copy.');
    expect(state.collectionItemDraft, isNull);
  });

  test('editing a Collection Item switches graded state to Raw state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('charizard-ex');
    final controller = container.read(provider.notifier);

    controller.startEditingCollectionItem('item-charizard');
    controller.updateCollectionItemDraft(
      quantityText: '3',
      grader: 'Raw',
      condition: 'Near Mint',
      purchasePriceText: '640',
      notes: 'Cracked slab for binder.',
    );

    expect(controller.saveCollectionItemDraft(), isTrue);
    final row = container.read(provider).collectionItemRows.single;

    expect(row.quantityText, 'Qty: 3');
    expect(row.statusText, 'Raw / Near Mint');
    expect(row.purchasePriceText, r'$640.00');
    expect(row.notes, 'Cracked slab for binder.');
  });

  test('invalid Collection Item draft stays open with validation copy', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('charizard-ex');
    final controller = container.read(provider.notifier);

    controller.startEditingCollectionItem('item-charizard');
    controller.updateCollectionItemDraft(quantityText: '0');

    expect(controller.saveCollectionItemDraft(), isFalse);
    final state = container.read(provider);

    expect(state.collectionItemDraft, isNotNull);
    expect(state.collectionItemFormError, 'Quantity must be at least 1.');
    expect(state.collectionItemRows.single.quantityText, 'Qty: 1');
  });

  test(
    'removing the final Collection Item returns detail to uncollected state',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = cardDetailControllerProvider('charizard-ex');

      container.read(provider.notifier).removeCollectionItem('item-charizard');
      final state = container.read(provider);

      expect(state.detail.isCollected, isFalse);
      expect(state.detail.quantity, 0);
      expect(state.collectionItemRows, isEmpty);
    },
  );

  test(
    'price tab exposes default range series, market rows, and sold listings',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(
        cardDetailControllerProvider('charizard-ex'),
      );

      expect(state.selectedPriceRange, CardPriceRange.thirty);
      expect(state.priceSeriesRows.last.dateLabel, 'Today');
      expect(state.priceSeriesRows.last.priceText, r'$780.00');
      expect(state.priceTabMarketRows.first.label, 'PSA 10');
      expect(state.priceTabMarketRows.first.changeText, startsWith('+'));
      expect(state.soldListingRows.first.platform, 'eBay');
      expect(state.soldListingRows.first.priceText, r'$780.00');
    },
  );

  test('selecting a price range changes only the visible series rows', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('charizard-ex');

    container.read(provider.notifier).selectPriceRange(CardPriceRange.seven);
    final state = container.read(provider);

    expect(state.selectedPriceRange, CardPriceRange.seven);
    expect(state.priceSeriesRows.first.dateLabel, '7 days ago');
    expect(state.priceSeriesRows.last.priceText, r'$780.00');
    expect(state.priceTabMarketRows.first.label, 'PSA 10');
  });

  test('repository failure shows failure state and refresh recovers', () {
    final repository = _FailingThenSuccessfulCardDetailRepository();
    final container = ProviderContainer(
      overrides: [cardDetailRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final provider = cardDetailControllerProvider('squirtle');

    final failed = container.read(provider);

    expect(failed.loadStatus, KandoLoadStatus.failure);
    expect(failed.isUnavailable, isTrue);
    expect(repository.calls, 1);

    container.read(provider.notifier).refresh();
    final restored = container.read(provider);

    expect(restored.loadStatus, KandoLoadStatus.content);
    expect(restored.isUnavailable, isFalse);
    expect(restored.detail.name, 'Squirtle');
    expect(repository.calls, 2);
  });
}

class _FailingThenSuccessfulCardDetailRepository
    implements CardDetailRepository {
  var calls = 0;

  @override
  CardDetail loadDetail(String cardId) {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock detail unavailable');
    }
    return const MockCardDetailRepository().loadDetail(cardId);
  }
}
