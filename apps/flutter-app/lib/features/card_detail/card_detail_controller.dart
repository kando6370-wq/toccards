import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'card_detail_models.dart';
import 'card_detail_repository.dart';

final cardDetailRepositoryProvider = Provider<CardDetailRepository>((ref) {
  return HttpCardDetailRepository(
    api: ref.watch(portfolioApiClientProvider),
    cardDataApi: ref.watch(cardDataApiClientProvider),
  );
});

final cardDetailControllerProvider =
    NotifierProvider.family<CardDetailController, CardDetailState, String>(
      CardDetailController.new,
    );

const cardCollectionGraders = ['Raw', 'PSA', 'BGS', 'SGC', 'CGC', 'TAG', 'AGS'];
const cardCollectionConditions = [
  'Near Mint (NM)',
  'Lightly Played (LP)',
  'Moderately Played (MP)',
  'Heavily Played (HP)',
  'Damaged (D)',
];
const cardCollectionLanguages = [
  'English',
  'Japanese',
  'Chinese',
  'Korean',
  'French',
  'German',
  'Spanish',
  'Italian',
  'Portuguese',
];
const cardCollectionFinishes = [
  'Normal',
  'Holofoil',
  'Reverse Holofoil',
  'Cold Foil',
  'Foil',
  'Non-Foil',
];
const cardCollectionGradeValues = [
  '10',
  '9.5',
  '9',
  '8.5',
  '8',
  '7.5',
  '7',
  '6.5',
  '6',
  '5.5',
  '5',
  '4.5',
  '4',
  '3.5',
  '3',
  '2.5',
  '2',
  '1.5',
  '1',
];

const _defaultCondition = 'Near Mint (NM)';
const _defaultGrade = '10';
const _quantityRequiredText = 'Please enter a quantity.';
const _quantityMinText = 'Quantity must be at least 1.';
const _quantityWholeText = 'Quantity must be a whole number.';
const _invalidPriceText = 'Please enter a valid price.';
const _notesTooLongText = 'Notes must be 500 characters or less.';
const _priceSeriesFallbackText = 'No price data available.';
const _soldListingsFallbackText = 'No sold listings available.';
const _cardDetailStateUnset = Object();

String _gradeText(double grade) {
  return grade == grade.truncateToDouble()
      ? grade.toInt().toString()
      : grade.toString();
}

String _collectionOptionOrDefault(String value, List<String> options) {
  return options.contains(value) ? value : options.first;
}

int _compareListingDates(String left, String right) {
  final leftDate = DateTime.tryParse(left);
  final rightDate = DateTime.tryParse(right);
  if (leftDate != null && rightDate != null) {
    return leftDate.compareTo(rightDate);
  }
  return left.compareTo(right);
}

List<String> cardCollectionGradeLabelsFor(String grader) {
  return cardCollectionGradeValues.map((grade) => '$grader $grade').toList();
}

class CardCollectionItemDraft {
  const CardCollectionItemDraft({
    required this.quantityText,
    required this.portfolioName,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.language,
    required this.finish,
    required this.purchasePriceText,
    required this.notes,
  });

  final String quantityText;
  final String portfolioName;
  final String grader;
  final String condition;
  final String grade;
  final String language;
  final String finish;
  final String purchasePriceText;
  final String notes;

  bool get isRaw => grader == 'Raw';

  CardCollectionItemDraft copyWith({
    String? quantityText,
    String? portfolioName,
    String? grader,
    String? condition,
    String? grade,
    String? language,
    String? finish,
    String? purchasePriceText,
    String? notes,
  }) {
    return CardCollectionItemDraft(
      quantityText: quantityText ?? this.quantityText,
      portfolioName: portfolioName ?? this.portfolioName,
      grader: grader ?? this.grader,
      condition: condition ?? this.condition,
      grade: grade ?? this.grade,
      language: language ?? this.language,
      finish: finish ?? this.finish,
      purchasePriceText: purchasePriceText ?? this.purchasePriceText,
      notes: notes ?? this.notes,
    );
  }
}

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

class CardCollectionItemRow {
  const CardCollectionItemRow({
    required this.id,
    required this.portfolioName,
    required this.quantityText,
    required this.statusText,
    required this.languageText,
    required this.finishText,
    required this.purchasePriceText,
    required this.marketPriceText,
    required this.totalText,
    required this.notes,
  });

  final String id;
  final String portfolioName;
  final String quantityText;
  final String statusText;
  final String languageText;
  final String finishText;
  final String purchasePriceText;
  final String marketPriceText;
  final String totalText;
  final String notes;
}

class CardPricePointRow {
  const CardPricePointRow({required this.dateLabel, required this.priceText});

  final String dateLabel;
  final String priceText;
}

class CardSoldListingRow {
  const CardSoldListingRow({
    required this.dateText,
    required this.title,
    required this.priceText,
    required this.platform,
    required this.url,
  });

  final String dateText;
  final String title;
  final String priceText;
  final String platform;
  final String? url;
}

class CardDetailState {
  const CardDetailState({
    required this.cardId,
    required CardDetail detail,
    required this.currency,
    this.selectedPriceChartMode = CardPriceChartMode.raw,
    this.selectedPriceRange = CardPriceRange.oneMonth,
    this.selectedMarketPriceCategory = CardMarketPriceCategory.ungraded,
    this.selectedFinish,
    this.collectionItemDraft,
    this.editingCollectionItemId,
    this.collectionItemFormError,
    this.isSavingCollectionItemDraft = false,
    this.assetStateStatus = KandoLoadStatus.content,
    this.priceSeriesStatus = KandoLoadStatus.content,
    this.marketPricesStatus = KandoLoadStatus.content,
    this.soldListingsStatus = KandoLoadStatus.content,
  }) : _detail = detail,
       loadStatus = KandoLoadStatus.content;

  const CardDetailState.unavailable({
    required this.cardId,
    required this.currency,
    this.selectedPriceChartMode = CardPriceChartMode.raw,
    this.selectedPriceRange = CardPriceRange.oneMonth,
    this.selectedMarketPriceCategory = CardMarketPriceCategory.ungraded,
    this.selectedFinish,
    this.collectionItemDraft,
    this.editingCollectionItemId,
    this.collectionItemFormError,
    this.isSavingCollectionItemDraft = false,
  }) : _detail = null,
       loadStatus = KandoLoadStatus.failure,
       assetStateStatus = KandoLoadStatus.failure,
       priceSeriesStatus = KandoLoadStatus.failure,
       marketPricesStatus = KandoLoadStatus.failure,
       soldListingsStatus = KandoLoadStatus.failure;

  const CardDetailState.loading({
    required this.cardId,
    required this.currency,
    this.selectedPriceChartMode = CardPriceChartMode.raw,
    this.selectedPriceRange = CardPriceRange.oneMonth,
    this.selectedMarketPriceCategory = CardMarketPriceCategory.ungraded,
    this.selectedFinish,
    this.collectionItemDraft,
    this.editingCollectionItemId,
    this.collectionItemFormError,
    this.isSavingCollectionItemDraft = false,
  }) : _detail = null,
       loadStatus = KandoLoadStatus.loading,
       assetStateStatus = KandoLoadStatus.loading,
       priceSeriesStatus = KandoLoadStatus.loading,
       marketPricesStatus = KandoLoadStatus.loading,
       soldListingsStatus = KandoLoadStatus.loading;

  final String cardId;
  final CardDetail? _detail;
  final AppCurrency currency;
  final CardPriceChartMode selectedPriceChartMode;
  final CardPriceRange selectedPriceRange;
  final CardMarketPriceCategory selectedMarketPriceCategory;
  final String? selectedFinish;
  final CardCollectionItemDraft? collectionItemDraft;
  final String? editingCollectionItemId;
  final String? collectionItemFormError;
  final bool isSavingCollectionItemDraft;
  final KandoLoadStatus loadStatus;
  final KandoLoadStatus assetStateStatus;
  final KandoLoadStatus priceSeriesStatus;
  final KandoLoadStatus marketPricesStatus;
  final KandoLoadStatus soldListingsStatus;

  bool get isUnavailable => loadStatus == KandoLoadStatus.failure;
  bool get isLoading => loadStatus == KandoLoadStatus.loading;

  CardDetail get detail {
    final detail = _detail;
    if (detail == null) {
      throw StateError('Card detail is unavailable.');
    }
    return detail;
  }

  String get priceFinish =>
      selectedFinish ?? priceFinishes.firstOrNull ?? detail.finish;

  List<String> get priceFinishes {
    final finishes = detail.collectionFinishOptions;
    if (!finishes.contains(detail.finish)) return finishes;
    return [
      detail.finish,
      ...finishes.where((finish) => finish != detail.finish),
    ];
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

  List<CardCollectionItemRow> get collectionItemRows {
    return detail.collectionItems.map((item) {
      return CardCollectionItemRow(
        id: item.id,
        portfolioName: item.portfolioName,
        quantityText: 'Qty: ${item.quantity}',
        statusText: _collectionStatusText(item),
        languageText: item.language ?? '-',
        finishText: item.finish ?? '-',
        purchasePriceText: _formatter.formatUsd(item.purchasePriceUsd),
        marketPriceText: _formatter.formatUsd(
          _matchingCollectionMarketPrice(
            finish: item.finish,
            grader: item.grader,
            condition: item.condition,
            grade: item.grade,
          )?.priceUsd,
        ),
        totalText: _formatter.formatUsd(
          item.purchasePriceUsd == null
              ? null
              : item.purchasePriceUsd! * item.quantity,
        ),
        notes: item.notes,
      );
    }).toList();
  }

  String get collectionItemDraftTotalText {
    final draft = collectionItemDraft;
    if (draft == null) return _formatter.formatUsd(null);
    final quantity = int.tryParse(draft.quantityText.trim());
    if (quantity == null || quantity < 1) return _formatter.formatUsd(null);
    return _formatter.formatUsd(
      _collectionItemDraftMarketPrice?.priceUsd,
      quantity: quantity,
    );
  }

  String get collectionItemDraftSelectionText {
    final draft = collectionItemDraft;
    if (draft == null) return '';
    if (draft.isRaw) {
      return '${draft.finish} · Raw · ${_displayCondition(draft.condition)}';
    }
    return '${draft.finish} · ${draft.grader} ${draft.grade}';
  }

  String get collectionItemDraftMarketPriceText {
    return _formatter.formatUsd(_collectionItemDraftMarketPrice?.priceUsd);
  }

  CardMarketPrice? get _collectionItemDraftMarketPrice {
    final draft = collectionItemDraft;
    if (draft == null) return null;
    return _matchingCollectionMarketPrice(
      finish: draft.finish,
      grader: draft.grader,
      condition: draft.condition,
      grade: draft.grade,
    );
  }

  CardMarketPrice? _matchingCollectionMarketPrice({
    required String? finish,
    required String grader,
    required String? condition,
    required String? grade,
  }) {
    if (marketPricesStatus != KandoLoadStatus.content ||
        (finish ?? '').trim().toLowerCase() !=
            priceFinish.trim().toLowerCase()) {
      return null;
    }
    return detail.marketPrices.where((price) {
      if (price.grader.toLowerCase() != grader.toLowerCase()) {
        return false;
      }
      if (grader.toLowerCase() == 'raw') {
        return _normalizedCondition(price.condition) ==
            _normalizedCondition(condition);
      }
      final gradeValue = double.tryParse(grade ?? '');
      return gradeValue != null && price.grade == gradeValue;
    }).firstOrNull;
  }

  List<CardPricePoint> get selectedPriceSeries {
    return selectedPriceChartSeries
            .firstOrNull
            ?.seriesByRange[selectedPriceRange] ??
        const <CardPricePoint>[];
  }

  List<CardPriceChartSeries> get selectedPriceChartSeries {
    if (selectedPriceChartMode == CardPriceChartMode.raw) {
      if (detail.rawPriceSeries.isNotEmpty) return detail.rawPriceSeries;
      return [
        CardPriceChartSeries(
          label: 'Raw',
          seriesByRange: detail.priceSeriesByRange,
        ),
      ];
    }
    if (detail.gradedPriceSeries.isNotEmpty) {
      return detail.gradedPriceSeries;
    }
    if (detail.gradedPriceSeriesByRange.isEmpty) return const [];
    return [
      CardPriceChartSeries(
        label: 'Graded',
        seriesByRange: detail.gradedPriceSeriesByRange,
      ),
    ];
  }

  List<CardPricePointRow> get priceSeriesRows {
    return selectedPriceSeries.map((point) {
      return CardPricePointRow(
        dateLabel: point.dateLabel,
        priceText: _formatter.formatUsd(point.priceUsd),
      );
    }).toList();
  }

  bool get hasPriceSeriesRows {
    return priceSeriesRows.isNotEmpty;
  }

  String get priceSeriesFallbackText {
    return _priceSeriesFallbackText;
  }

  List<CardMarketRow> get priceTabMarketRows {
    return detail.marketPrices
        .where(
          (price) =>
              price.grader.toLowerCase() ==
              selectedMarketPriceCategory.grader.toLowerCase(),
        )
        .map((price) {
          return CardMarketRow(
            label:
                selectedMarketPriceCategory == CardMarketPriceCategory.ungraded
                ? _rawMarketRowLabel(price)
                : _gradedMarketRowLabel(price),
            priceText: _formatter.formatUsd(price.priceUsd),
            changeText: _marketChange7d(price).percentText,
          );
        })
        .toList();
  }

  List<CardMarketPriceCategory> get availableMarketPriceCategories {
    final available = CardMarketPriceCategory.values.where((category) {
      return detail.marketPrices.any(
        (price) => price.grader.toLowerCase() == category.grader.toLowerCase(),
      );
    }).toList();
    return available.isEmpty
        ? const [CardMarketPriceCategory.ungraded]
        : available;
  }

  List<CardSoldListingRow> get soldListingRows {
    final listings = [...detail.soldListings]
      ..sort(
        (left, right) => _compareListingDates(right.dateText, left.dateText),
      );
    return listings.map((listing) {
      return CardSoldListingRow(
        dateText: listing.dateText,
        title: listing.title,
        priceText: _formatter.formatUsd(listing.priceUsd),
        platform: listing.platform,
        url: listing.url,
      );
    }).toList();
  }

  bool get hasSoldListingRows {
    return soldListingRows.isNotEmpty;
  }

  String get soldListingsFallbackText {
    return _soldListingsFallbackText;
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

  MarketChange _marketChange7d(CardMarketPrice price) {
    if (price.increasePercent != null) {
      return MarketChange.fromPercent(price.increasePercent);
    }
    return MarketChange.fromPrices(
      current: price.priceUsd,
      previous: price.previous7dPriceUsd,
    );
  }

  String _gradedMarketRowLabel(CardMarketPrice price) {
    return price.gradeLabel ??
        (price.grade == null ? price.label : _gradeText(price.grade!));
  }

  String _rawMarketRowLabel(CardMarketPrice price) {
    final label =
        price.condition ??
        price.label.replaceFirst(RegExp(r'^Raw\s*'), '').trim();
    return label.isEmpty ? 'Raw' : label;
  }

  String _collectionStatusText(CardCollectionItem item) {
    if (item.grader == 'Raw') {
      return 'Raw / ${item.condition ?? '-'}';
    }

    return '${item.grader} ${item.grade ?? '-'}';
  }

  CardDetailState copyWith({
    CardDetail? detail,
    AppCurrency? currency,
    CardPriceChartMode? selectedPriceChartMode,
    CardPriceRange? selectedPriceRange,
    CardMarketPriceCategory? selectedMarketPriceCategory,
    String? selectedFinish,
    Object? collectionItemDraft = _cardDetailStateUnset,
    Object? editingCollectionItemId = _cardDetailStateUnset,
    Object? collectionItemFormError = _cardDetailStateUnset,
    bool? isSavingCollectionItemDraft,
    KandoLoadStatus? assetStateStatus,
    KandoLoadStatus? priceSeriesStatus,
    KandoLoadStatus? marketPricesStatus,
    KandoLoadStatus? soldListingsStatus,
  }) {
    return CardDetailState(
      cardId: cardId,
      detail: detail ?? this.detail,
      currency: currency ?? this.currency,
      selectedPriceChartMode:
          selectedPriceChartMode ?? this.selectedPriceChartMode,
      selectedPriceRange: selectedPriceRange ?? this.selectedPriceRange,
      selectedMarketPriceCategory:
          selectedMarketPriceCategory ?? this.selectedMarketPriceCategory,
      selectedFinish: selectedFinish ?? this.selectedFinish,
      collectionItemDraft: collectionItemDraft == _cardDetailStateUnset
          ? this.collectionItemDraft
          : collectionItemDraft as CardCollectionItemDraft?,
      editingCollectionItemId: editingCollectionItemId == _cardDetailStateUnset
          ? this.editingCollectionItemId
          : editingCollectionItemId as String?,
      collectionItemFormError: collectionItemFormError == _cardDetailStateUnset
          ? this.collectionItemFormError
          : collectionItemFormError as String?,
      isSavingCollectionItemDraft:
          isSavingCollectionItemDraft ?? this.isSavingCollectionItemDraft,
      assetStateStatus: assetStateStatus ?? this.assetStateStatus,
      priceSeriesStatus: priceSeriesStatus ?? this.priceSeriesStatus,
      marketPricesStatus: marketPricesStatus ?? this.marketPricesStatus,
      soldListingsStatus: soldListingsStatus ?? this.soldListingsStatus,
    );
  }
}

class CardDetailController extends Notifier<CardDetailState> {
  CardDetailController(this.cardId);

  final String cardId;
  Completer<void>? _loadCompleter;
  var _loadGeneration = 0;
  var _priceLoadGeneration = 0;

  Future<void> get loadComplete {
    return _loadCompleter?.future ?? Future<void>.value();
  }

  @override
  CardDetailState build() {
    ref.listen<AppCurrency>(selectedCurrencyProvider, (previous, next) {
      if (!state.isLoading && !state.isUnavailable) {
        state = state.copyWith(currency: next);
      }
    });

    final currency = ref.read(selectedCurrencyProvider);
    final authState = ref.watch(authControllerProvider);
    final session = authState.session;
    if (authState.isLoading || session == null) {
      _invalidateLoad();
      return CardDetailState.loading(cardId: cardId, currency: currency);
    }

    _startLoad(session: session, currency: currency);
    return CardDetailState.loading(cardId: cardId, currency: currency);
  }

  Future<void> refresh() {
    final session = ref.read(authControllerProvider).session;
    if (session == null) {
      _invalidateLoad();
      state = CardDetailState.loading(cardId: cardId, currency: state.currency);
      return Future<void>.value();
    }

    state = CardDetailState.loading(cardId: cardId, currency: state.currency);
    _startLoad(session: session, currency: state.currency);
    return loadComplete;
  }

  Future<void> refreshPriceSeries() {
    return _refreshSection(
      status: (value) => state = state.copyWith(priceSeriesStatus: value),
      load: (repository, isCurrent) async {
        final data = await repository.loadPriceSeries(
          cardId,
          finish: state.priceFinish,
        );
        if (!isCurrent()) return;
        state = state.copyWith(
          detail: state.detail.copyWith(
            marketPrices: _resolvedMarketPrices(data.marketPrices),
            priceSeriesByRange: data.rawSeriesByRange,
            rawPriceSeries: data.rawSeries,
            gradedPriceSeriesByRange: data.gradedSeriesByRange,
            gradedPriceSeries: data.gradedSeries,
          ),
        );
      },
    );
  }

  Future<void> refreshAssetState() {
    final session = _session;
    if (session == null) return Future<void>.value();
    return _refreshSection(
      status: (value) => state = state.copyWith(assetStateStatus: value),
      load: (repository, isCurrent) async {
        final detail = await repository.loadAssetState(session, state.detail);
        if (isCurrent()) {
          state = state.copyWith(
            detail: _detailWithAssetState(state.detail, detail),
          );
        }
      },
    );
  }

  Future<void> refreshMarketPrices() {
    return _refreshSection(
      status: (value) => state = state.copyWith(marketPricesStatus: value),
      load: (repository, isCurrent) async {
        final data = await repository.loadMarketPrices(
          cardId,
          finish: state.priceFinish,
        );
        if (!isCurrent()) return;
        state = state.copyWith(
          detail: state.detail.copyWith(
            marketPrices: _resolvedMarketPrices(data.marketPrices),
          ),
        );
      },
    );
  }

  Future<void> refreshSoldListings() {
    return _refreshSection(
      status: (value) => state = state.copyWith(soldListingsStatus: value),
      load: (repository, isCurrent) async {
        final listings = await repository.loadSoldListings(cardId);
        if (!isCurrent()) return;
        state = state.copyWith(
          detail: state.detail.copyWith(soldListings: listings),
        );
      },
    );
  }

  Future<void> quickCollect() async {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    final session = _session;
    if (session == null) {
      return;
    }
    final detail = state.detail;
    if (detail.isCollected) {
      return;
    }
    final mutationGeneration = _loadGeneration;

    final savedItem = await _repository.quickCollect(session, detail);
    if (!_canApplyMutation(session, mutationGeneration)) {
      return;
    }
    final currentDetail = state.detail;
    if (currentDetail.id != detail.id || currentDetail.isCollected) {
      return;
    }
    state = state.copyWith(
      detail: _detailWithCollectionItems(
        currentDetail,
        [...currentDetail.collectionItems, savedItem],
        isWishlisted: false,
        wishlistItemId: null,
      ),
    );
    _invalidateAssetConsumers();
  }

  Future<void> toggleWishlist() async {
    if (state.isUnavailable || state.isLoading || state.detail.isCollected) {
      return;
    }

    final session = _session;
    if (session == null) {
      return;
    }
    final detail = state.detail;
    if (detail.isWishlisted) {
      final wishlistItemId = detail.wishlistItemId;
      if (wishlistItemId == null) {
        return;
      }
      final mutationGeneration = _loadGeneration;
      await _repository.deleteWishlist(session, wishlistItemId);
      if (!_canApplyMutation(session, mutationGeneration)) {
        return;
      }
      final currentDetail = state.detail;
      if (!currentDetail.isWishlisted ||
          currentDetail.wishlistItemId != wishlistItemId) {
        return;
      }
      state = state.copyWith(
        detail: currentDetail.copyWith(
          isWishlisted: false,
          wishlistItemId: null,
        ),
      );
      _invalidateAssetConsumers();
      return;
    }

    final mutationGeneration = _loadGeneration;
    final wishlistItemId = await _repository.addWishlist(session, detail.id);
    if (!_canApplyMutation(session, mutationGeneration)) {
      return;
    }
    final currentDetail = state.detail;
    if (currentDetail.id != detail.id ||
        currentDetail.isCollected ||
        currentDetail.isWishlisted) {
      return;
    }
    state = state.copyWith(
      detail: currentDetail.copyWith(
        isWishlisted: true,
        wishlistItemId: wishlistItemId,
      ),
    );
    _invalidateAssetConsumers();
  }

  void selectPriceRange(CardPriceRange range) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(selectedPriceRange: range);
  }

  void selectPriceChartMode(CardPriceChartMode mode) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(selectedPriceChartMode: mode);
  }

  void selectMarketPriceCategory(CardMarketPriceCategory category) {
    if (state.isUnavailable || state.isLoading) return;
    state = state.copyWith(selectedMarketPriceCategory: category);
  }

  Future<void> selectPriceFinish(String finish) async {
    if (state.isLoading || state.isUnavailable || finish == state.priceFinish) {
      return;
    }
    final repository = _repository;
    if (repository is! CardDetailSectionRepository) return;
    final sectionRepository = repository as CardDetailSectionRepository;
    final generation = ++_priceLoadGeneration;
    state = state.copyWith(
      selectedFinish: finish,
      priceSeriesStatus: KandoLoadStatus.loading,
      marketPricesStatus: KandoLoadStatus.loading,
    );
    try {
      final market = await sectionRepository.loadMarketPrices(
        cardId,
        finish: finish,
      );
      final series = await sectionRepository.loadPriceSeries(
        cardId,
        market: market,
        finish: finish,
      );
      if (generation != _priceLoadGeneration || finish != state.priceFinish) {
        return;
      }
      state = state.copyWith(
        detail: state.detail.copyWith(
          marketPrices: _resolvedMarketPrices(series.marketPrices),
          priceSeriesByRange: series.rawSeriesByRange,
          rawPriceSeries: series.rawSeries,
          gradedPriceSeriesByRange: series.gradedSeriesByRange,
          gradedPriceSeries: series.gradedSeries,
        ),
        priceSeriesStatus: KandoLoadStatus.content,
        marketPricesStatus: KandoLoadStatus.content,
      );
    } catch (_) {
      if (generation != _priceLoadGeneration || finish != state.priceFinish) {
        return;
      }
      state = state.copyWith(
        priceSeriesStatus: KandoLoadStatus.failure,
        marketPricesStatus: KandoLoadStatus.failure,
      );
    }
  }

  void startAddingCollectionItem() {
    if (state.isUnavailable || state.isLoading) {
      return;
    }
    final defaultFolder = _initialPortfolioFolder(
      state.detail,
      ref.read(selectedPortfolioFolderProvider),
    );
    if (defaultFolder == null) {
      return;
    }

    state = state.copyWith(
      collectionItemDraft:
          const CardCollectionItemDraft(
            quantityText: '1',
            portfolioName: '',
            grader: 'Raw',
            condition: _defaultCondition,
            grade: '',
            language: '',
            finish: '',
            purchasePriceText: '',
            notes: '',
          ).copyWith(
            portfolioName: defaultFolder.name,
            language: _collectionOptionOrDefault(
              state.detail.language,
              state.detail.collectionLanguageOptions,
            ),
            finish: _collectionOptionOrDefault(
              state.detail.finish,
              state.detail.collectionFinishOptions,
            ),
          ),
      editingCollectionItemId: null,
      collectionItemFormError: null,
    );
  }

  void startEditingCollectionItem(String itemId) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    final item = _findCollectionItem(itemId);
    if (item == null) {
      return;
    }

    state = state.copyWith(
      collectionItemDraft: CardCollectionItemDraft(
        quantityText: item.quantity.toString(),
        portfolioName: item.portfolioName,
        grader: item.grader,
        condition: item.condition ?? _defaultCondition,
        grade: item.grade ?? _defaultGradeForGrader(item.grader),
        language: _collectionOptionOrDefault(
          item.language ?? state.detail.language,
          _optionsWithCurrent(
            state.detail.collectionLanguageOptions,
            item.language,
          ),
        ),
        finish: _collectionOptionOrDefault(
          item.finish ?? state.detail.finish,
          _optionsWithCurrent(
            state.detail.collectionFinishOptions,
            item.finish,
          ),
        ),
        purchasePriceText:
            _currencyFormatter
                .convertUsd(item.purchasePriceUsd)
                ?.toStringAsFixed(2) ??
            '',
        notes: item.notes,
      ),
      editingCollectionItemId: item.id,
      collectionItemFormError: null,
    );
  }

  List<String> _optionsWithCurrent(List<String> options, String? current) {
    if (current == null || current.isEmpty || options.contains(current)) {
      return options;
    }
    return [...options, current];
  }

  void updateCollectionItemDraft({
    String? quantityText,
    String? portfolioName,
    String? grader,
    String? condition,
    String? grade,
    String? language,
    String? finish,
    String? purchasePriceText,
    String? notes,
  }) {
    final draft = state.collectionItemDraft;
    if (state.isUnavailable || state.isLoading || draft == null) {
      return;
    }

    final nextGrader = grader ?? draft.grader;
    final nextIsRaw = nextGrader == 'Raw';
    state = state.copyWith(
      collectionItemDraft: draft.copyWith(
        quantityText: quantityText,
        portfolioName: portfolioName,
        grader: nextGrader,
        condition: nextIsRaw
            ? condition ?? (draft.isRaw ? draft.condition : _defaultCondition)
            : '',
        grade: nextIsRaw
            ? ''
            : grade ??
                  (draft.isRaw || grader != null
                      ? _defaultGradeForGrader(nextGrader)
                      : draft.grade),
        language: language,
        finish: finish,
        purchasePriceText: purchasePriceText,
        notes: notes,
      ),
      collectionItemFormError: null,
    );
  }

  void cancelCollectionItemEdit() {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(
      collectionItemDraft: null,
      editingCollectionItemId: null,
      collectionItemFormError: null,
    );
  }

  Future<bool> saveCollectionItemDraft() async {
    final draft = state.collectionItemDraft;
    if (state.isUnavailable ||
        state.isLoading ||
        state.isSavingCollectionItemDraft ||
        draft == null) {
      return false;
    }
    final session = _session;
    if (session == null) {
      return false;
    }

    final quantity = _parseQuantity(draft.quantityText);
    if (quantity.error != null) {
      _setCollectionItemFormError(quantity.error!);
      return false;
    }

    final purchasePrice = _parsePurchasePrice(draft.purchasePriceText);
    if (purchasePrice.error != null) {
      _setCollectionItemFormError(purchasePrice.error!);
      return false;
    }
    final purchasePriceUsd = _currencyFormatter.toUsd(purchasePrice.value);
    if (purchasePrice.value != null && purchasePriceUsd == null) {
      _setCollectionItemFormError(_invalidPriceText);
      return false;
    }

    if (draft.notes.length > 500) {
      _setCollectionItemFormError(_notesTooLongText);
      return false;
    }

    final detail = state.detail;
    final folderId = _folderIdForPortfolioName(
      detail.portfolioFolders,
      draft.portfolioName,
    );
    if (folderId == null) {
      _setCollectionItemFormError('Please select a portfolio.');
      return false;
    }
    final editingItemId = state.editingCollectionItemId;
    final mutationGeneration = _loadGeneration;
    final draftItem = CardCollectionItem(
      id: editingItemId ?? '',
      cardRef: detail.id,
      folderId: folderId,
      portfolioName: draft.portfolioName,
      quantity: quantity.value!,
      grader: draft.grader,
      condition: draft.isRaw ? draft.condition : null,
      grade: draft.isRaw ? null : draft.grade,
      language: draft.language,
      finish: draft.finish,
      purchasePriceUsd: purchasePriceUsd,
      notes: draft.notes,
    );
    state = state.copyWith(
      isSavingCollectionItemDraft: true,
      collectionItemFormError: null,
    );

    CardCollectionItem savedItem;
    try {
      savedItem = editingItemId == null
          ? await _repository.createCollectionItem(
              session,
              detail: detail,
              item: draftItem,
            )
          : await _repository.updateCollectionItem(
              session,
              detail: detail,
              item: draftItem,
            );
    } on PortfolioApiException catch (error) {
      if (_canApplyMutation(session, mutationGeneration) &&
          state.editingCollectionItemId == editingItemId &&
          state.collectionItemDraft != null &&
          state.detail.id == detail.id) {
        state = state.copyWith(
          isSavingCollectionItemDraft: false,
          collectionItemFormError:
              error.code == duplicateCollectionItemErrorCode
              ? duplicateCollectionItemMessage
              : state.collectionItemFormError,
        );
      }
      if (error.code == duplicateCollectionItemErrorCode) return false;
      rethrow;
    } catch (_) {
      if (_canApplyMutation(session, mutationGeneration) &&
          state.editingCollectionItemId == editingItemId &&
          state.collectionItemDraft != null &&
          state.detail.id == detail.id) {
        state = state.copyWith(isSavingCollectionItemDraft: false);
      }
      rethrow;
    }

    if (!_canApplyMutation(session, mutationGeneration) ||
        state.editingCollectionItemId != editingItemId ||
        state.collectionItemDraft == null ||
        state.detail.id != detail.id) {
      return false;
    }
    final currentDetail = state.detail;
    final nextItems = editingItemId == null
        ? [...currentDetail.collectionItems, savedItem]
        : [
            for (final item in currentDetail.collectionItems)
              if (item.id == editingItemId) savedItem else item,
          ];

    state = state.copyWith(
      detail: _detailWithCollectionItems(
        currentDetail,
        nextItems,
        isWishlisted: false,
        wishlistItemId: null,
      ),
      collectionItemDraft: null,
      editingCollectionItemId: null,
      collectionItemFormError: null,
      isSavingCollectionItemDraft: false,
    );
    _invalidateAssetConsumers();
    return true;
  }

  Future<void> removeCollectionItem(String itemId) async {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    final session = _session;
    if (session == null) {
      return;
    }
    final detail = state.detail;
    final mutationGeneration = _loadGeneration;
    await _repository.deleteCollectionItem(session, itemId);
    if (!_canApplyMutation(session, mutationGeneration)) {
      return;
    }
    final currentDetail = state.detail;
    if (currentDetail.id != detail.id ||
        !currentDetail.collectionItems.any((item) => item.id == itemId)) {
      return;
    }
    final nextItems = currentDetail.collectionItems
        .where((item) => item.id != itemId)
        .toList();

    state = state.copyWith(
      detail: _detailWithCollectionItems(currentDetail, nextItems),
      collectionItemDraft: null,
      editingCollectionItemId: null,
      collectionItemFormError: null,
    );
    _invalidateAssetConsumers();
  }

  CardDetailRepository get _repository =>
      ref.read(cardDetailRepositoryProvider);

  CurrencyFormatter get _currencyFormatter {
    return CurrencyFormatter(currency: state.currency);
  }

  AuthSession? get _session => ref.read(authControllerProvider).session;

  bool _canApplyMutation(AuthSession session, int generation) {
    return generation == _loadGeneration &&
        identical(_session, session) &&
        !state.isUnavailable &&
        !state.isLoading &&
        state.detail.id == cardId;
  }

  void _invalidateAssetConsumers() {
    ref.invalidate(homeControllerProvider);
    ref.invalidate(collectionControllerProvider);
    ref.invalidate(searchControllerProvider);
  }

  void _invalidateLoad() {
    _loadGeneration += 1;
    final completer = _loadCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _loadCompleter = null;
  }

  void _startLoad({
    required AuthSession session,
    required AppCurrency currency,
  }) {
    final completer = Completer<void>();
    final generation = ++_loadGeneration;
    _loadCompleter = completer;
    unawaited(_loadDetail(session, currency, generation, completer));
  }

  Future<void> _loadDetail(
    AuthSession session,
    AppCurrency currency,
    int generation,
    Completer<void> completer,
  ) async {
    final repository = _repository;
    if (repository is CardDetailSectionRepository) {
      final sectionRepository = repository as CardDetailSectionRepository;
      await _loadSectionedDetail(
        sectionRepository,
        session,
        currency,
        generation,
        completer,
      );
      return;
    }
    try {
      final detail = await repository.loadDetail(session, cardId);
      if (generation == _loadGeneration) {
        state = CardDetailState(
          cardId: cardId,
          detail: detail,
          currency: currency,
        );
      }
    } catch (_) {
      if (generation == _loadGeneration) {
        state = CardDetailState.unavailable(cardId: cardId, currency: currency);
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> _loadSectionedDetail(
    CardDetailSectionRepository repository,
    AuthSession session,
    AppCurrency currency,
    int generation,
    Completer<void> completer,
  ) async {
    try {
      final detail = await repository.loadCoreDetail(cardId);
      if (generation != _loadGeneration) return;
      state = CardDetailState(
        cardId: cardId,
        detail: detail,
        currency: currency,
        assetStateStatus: KandoLoadStatus.loading,
        priceSeriesStatus: KandoLoadStatus.loading,
        marketPricesStatus: KandoLoadStatus.loading,
        soldListingsStatus: KandoLoadStatus.loading,
      );
      if (!completer.isCompleted) completer.complete();

      final marketFuture = _loadMarketPrices(repository, generation);
      await Future.wait([
        _loadAssetState(repository, session, generation),
        marketFuture.then(
          (market) => _loadPriceSeries(repository, generation, market),
        ),
        _loadSoldListings(repository, generation),
      ]);
    } catch (_) {
      if (generation == _loadGeneration) {
        state = CardDetailState.unavailable(cardId: cardId, currency: currency);
      }
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _loadAssetState(
    CardDetailSectionRepository repository,
    AuthSession session,
    int generation,
  ) async {
    try {
      final detail = await repository.loadAssetState(session, state.detail);
      if (generation == _loadGeneration) {
        state = state.copyWith(
          detail: _detailWithAssetState(state.detail, detail),
          assetStateStatus: KandoLoadStatus.content,
        );
      }
    } catch (_) {
      if (generation == _loadGeneration) {
        state = state.copyWith(assetStateStatus: KandoLoadStatus.failure);
      }
    }
  }

  Future<CardDetailMarketData?> _loadMarketPrices(
    CardDetailSectionRepository repository,
    int generation,
  ) async {
    try {
      final data = await repository.loadMarketPrices(
        cardId,
        finish: state.priceFinish,
      );
      if (generation == _loadGeneration) {
        state = state.copyWith(
          detail: state.detail.copyWith(
            marketPrices: _resolvedMarketPrices(data.marketPrices),
          ),
          marketPricesStatus: KandoLoadStatus.content,
        );
      }
      return data;
    } catch (_) {
      if (generation == _loadGeneration) {
        state = state.copyWith(marketPricesStatus: KandoLoadStatus.failure);
      }
      return null;
    }
  }

  Future<void> _loadPriceSeries(
    CardDetailSectionRepository repository,
    int generation,
    CardDetailMarketData? market,
  ) async {
    try {
      final data = await repository.loadPriceSeries(
        cardId,
        market: market,
        finish: state.priceFinish,
      );
      if (generation == _loadGeneration) {
        state = state.copyWith(
          detail: state.detail.copyWith(
            marketPrices: _resolvedMarketPrices(data.marketPrices),
            priceSeriesByRange: data.rawSeriesByRange,
            rawPriceSeries: data.rawSeries,
            gradedPriceSeriesByRange: data.gradedSeriesByRange,
            gradedPriceSeries: data.gradedSeries,
          ),
          priceSeriesStatus: KandoLoadStatus.content,
        );
      }
    } catch (_) {
      if (generation == _loadGeneration) {
        state = state.copyWith(priceSeriesStatus: KandoLoadStatus.failure);
      }
    }
  }

  Future<void> _loadSoldListings(
    CardDetailSectionRepository repository,
    int generation,
  ) async {
    try {
      final listings = await repository.loadSoldListings(cardId);
      if (generation == _loadGeneration) {
        state = state.copyWith(
          detail: state.detail.copyWith(soldListings: listings),
          soldListingsStatus: KandoLoadStatus.content,
        );
      }
    } catch (_) {
      if (generation == _loadGeneration) {
        state = state.copyWith(soldListingsStatus: KandoLoadStatus.failure);
      }
    }
  }

  Future<void> _refreshSection({
    required void Function(KandoLoadStatus status) status,
    required Future<void> Function(
      CardDetailSectionRepository repository,
      bool Function() isCurrent,
    )
    load,
  }) async {
    if (state.isUnavailable || state.isLoading) return;
    final repository = _repository;
    if (repository is! CardDetailSectionRepository) return;
    final sectionRepository = repository as CardDetailSectionRepository;
    final generation = _loadGeneration;
    bool isCurrent() => generation == _loadGeneration;
    status(KandoLoadStatus.loading);
    try {
      await load(sectionRepository, isCurrent);
      if (isCurrent()) status(KandoLoadStatus.content);
    } catch (_) {
      if (isCurrent()) status(KandoLoadStatus.failure);
    }
  }

  List<CardMarketPrice> _resolvedMarketPrices(
    List<CardMarketPrice> marketPrices,
  ) {
    return marketPrices.isEmpty
        ? const [
            CardMarketPrice(
              label: 'Raw',
              priceUsd: null,
              previous30dPriceUsd: null,
            ),
          ]
        : marketPrices;
  }

  CardDetail _detailWithAssetState(CardDetail current, CardDetail assetState) {
    return current.copyWith(
      quantity: assetState.quantity,
      isWishlisted: assetState.isWishlisted,
      wishlistItemId: assetState.wishlistItemId,
      portfolioFolders: assetState.portfolioFolders,
      collectionItems: assetState.collectionItems,
    );
  }

  CardCollectionItem? _findCollectionItem(String itemId) {
    for (final item in state.detail.collectionItems) {
      if (item.id == itemId) {
        return item;
      }
    }

    return null;
  }

  void _setCollectionItemFormError(String error) {
    state = state.copyWith(collectionItemFormError: error);
  }

  _QuantityParseResult _parseQuantity(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const _QuantityParseResult(error: _quantityRequiredText);
    }

    final parsed = int.tryParse(trimmed);
    if (parsed == null) {
      return const _QuantityParseResult(error: _quantityWholeText);
    }
    if (parsed < 1) {
      return const _QuantityParseResult(error: _quantityMinText);
    }

    return _QuantityParseResult(value: parsed);
  }

  _PurchasePriceParseResult _parsePurchasePrice(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const _PurchasePriceParseResult();
    }

    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      return const _PurchasePriceParseResult(error: _invalidPriceText);
    }

    return _PurchasePriceParseResult(value: parsed);
  }

  CardDetail _detailWithCollectionItems(
    CardDetail detail,
    List<CardCollectionItem> items, {
    bool? isWishlisted,
    Object? wishlistItemId = _cardDetailStateUnset,
  }) {
    final quantity = items.fold<int>(0, (sum, item) => sum + item.quantity);
    return detail.copyWith(
      quantity: quantity,
      isWishlisted: isWishlisted ?? detail.isWishlisted,
      wishlistItemId: wishlistItemId,
      collectionItems: items,
    );
  }
}

String _defaultGradeForGrader(String grader) {
  return cardCollectionGraders.contains(grader) && grader != 'Raw'
      ? cardCollectionGradeValues.first
      : _defaultGrade;
}

String _normalizedCondition(String? value) {
  return (value ?? '').trim().toLowerCase().replaceFirst(
    RegExp(r'\s*\([^)]*\)\s*$'),
    '',
  );
}

String _displayCondition(String value) {
  return value.trim().replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
}

CardPortfolioFolder? _initialPortfolioFolder(
  CardDetail detail,
  String? selectedFolderId,
) {
  for (final folder in detail.portfolioFolders) {
    if (folder.id == selectedFolderId) {
      return folder;
    }
  }
  for (final folder in detail.portfolioFolders) {
    if (folder.isDefault) {
      return folder;
    }
  }
  return detail.portfolioFolders.firstOrNull;
}

String? _folderIdForPortfolioName(
  List<CardPortfolioFolder> folders,
  String portfolioName,
) {
  for (final folder in folders) {
    if (folder.name == portfolioName) {
      return folder.id;
    }
  }
  return null;
}

class _QuantityParseResult {
  const _QuantityParseResult({this.value, this.error});

  final int? value;
  final String? error;
}

class _PurchasePriceParseResult {
  const _PurchasePriceParseResult({this.value, this.error});

  final double? value;
  final String? error;
}
