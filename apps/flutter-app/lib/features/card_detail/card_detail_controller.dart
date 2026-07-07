import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'card_detail_models.dart';
import 'card_detail_repository.dart';

final cardDetailRepositoryProvider = Provider<CardDetailRepository>((ref) {
  return const MockCardDetailRepository();
});

final cardDetailControllerProvider =
    NotifierProvider.family<CardDetailController, CardDetailState, String>(
      CardDetailController.new,
    );

class CardMarketRow {
  const CardMarketRow({
    required this.label,
    required this.priceText,
    required this.changeText,
  });

  final String label;
  final String priceText;
  final String changeText;
}

class CardDetailState {
  const CardDetailState({
    required this.cardId,
    required CardDetail detail,
    required this.currency,
  }) : _detail = detail,
       loadStatus = KandoLoadStatus.content;

  const CardDetailState.unavailable({
    required this.cardId,
    required this.currency,
  }) : _detail = null,
       loadStatus = KandoLoadStatus.failure;

  final String cardId;
  final CardDetail? _detail;
  final AppCurrency currency;
  final KandoLoadStatus loadStatus;

  bool get isUnavailable => loadStatus == KandoLoadStatus.failure;

  CardDetail get detail {
    final detail = _detail;
    if (detail == null) {
      throw StateError('Card detail is unavailable.');
    }
    return detail;
  }

  String get marketPriceText {
    return _formatter.formatUsd(_primaryMarketPrice.priceUsd);
  }

  String get changeText {
    return _marketChange(_primaryMarketPrice).percentText;
  }

  List<CardMarketRow> get marketRows {
    return detail.marketPrices.map((price) {
      return CardMarketRow(
        label: price.label,
        priceText: _formatter.formatUsd(price.priceUsd),
        changeText: _marketChange(price).percentText,
      );
    }).toList();
  }

  CardMarketPrice get _primaryMarketPrice {
    return detail.marketPrices.first;
  }

  CurrencyFormatter get _formatter {
    return CurrencyFormatter(currency: currency);
  }

  MarketChange _marketChange(CardMarketPrice price) {
    return MarketChange.fromPrices(
      current: price.priceUsd,
      previous: price.previous30dPriceUsd,
    );
  }

  CardDetailState copyWith({CardDetail? detail, AppCurrency? currency}) {
    return CardDetailState(
      cardId: cardId,
      detail: detail ?? this.detail,
      currency: currency ?? this.currency,
    );
  }
}

class CardDetailController extends Notifier<CardDetailState> {
  CardDetailController(this.cardId);

  final String cardId;

  @override
  CardDetailState build() {
    final currency = ref.watch(selectedCurrencyProvider);
    return _load(currency: currency);
  }

  void refresh() {
    state = _load(currency: ref.read(selectedCurrencyProvider));
  }

  void quickCollect() {
    if (state.isUnavailable) {
      return;
    }

    state = state.copyWith(
      detail: state.detail.copyWith(quantity: 1, isWishlisted: false),
    );
  }

  void toggleWishlist() {
    if (state.isUnavailable || state.detail.isCollected) {
      return;
    }

    state = state.copyWith(
      detail: state.detail.copyWith(isWishlisted: !state.detail.isWishlisted),
    );
  }

  CardDetailState _load({required AppCurrency currency}) {
    try {
      final repository = ref.read(cardDetailRepositoryProvider);
      return CardDetailState(
        cardId: cardId,
        detail: repository.loadDetail(cardId),
        currency: currency,
      );
    } catch (_) {
      return CardDetailState.unavailable(cardId: cardId, currency: currency);
    }
  }
}
