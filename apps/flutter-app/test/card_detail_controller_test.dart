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
