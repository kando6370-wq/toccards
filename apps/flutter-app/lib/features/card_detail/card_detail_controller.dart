import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'card_detail_models.dart';
import 'card_detail_repository.dart';

final cardDetailRepositoryProvider = Provider<CardDetailRepository>((ref) {
  return HttpCardDetailRepository(api: ref.watch(portfolioApiClientProvider));
});

final cardDetailControllerProvider =
    NotifierProvider.family<CardDetailController, CardDetailState, String>(
      CardDetailController.new,
    );

const cardCollectionPortfolioNames = ['Main', 'Sealed', 'Empty'];
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

const _defaultPortfolioName = 'Main';
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

  String get totalText {
    final quantity = int.tryParse(quantityText.trim());
    final price = double.tryParse(purchasePriceText.trim());

    if (quantity == null || quantity < 1 || price == null || price < 0) {
      return '--';
    }

    return r'$' + (quantity * price).toStringAsFixed(2);
  }

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
  });

  final String dateText;
  final String title;
  final String priceText;
  final String platform;
}

class CardDetailState {
  const CardDetailState({
    required this.cardId,
    required CardDetail detail,
    required this.currency,
    this.selectedPriceChartMode = CardPriceChartMode.raw,
    this.selectedPriceRange = CardPriceRange.oneMonth,
    this.collectionItemDraft,
    this.editingCollectionItemId,
    this.collectionItemFormError,
  }) : _detail = detail,
       loadStatus = KandoLoadStatus.content;

  const CardDetailState.unavailable({
    required this.cardId,
    required this.currency,
    this.selectedPriceChartMode = CardPriceChartMode.raw,
    this.selectedPriceRange = CardPriceRange.oneMonth,
    this.collectionItemDraft,
    this.editingCollectionItemId,
    this.collectionItemFormError,
  }) : _detail = null,
       loadStatus = KandoLoadStatus.failure;

  const CardDetailState.loading({
    required this.cardId,
    required this.currency,
    this.selectedPriceChartMode = CardPriceChartMode.raw,
    this.selectedPriceRange = CardPriceRange.oneMonth,
    this.collectionItemDraft,
    this.editingCollectionItemId,
    this.collectionItemFormError,
  }) : _detail = null,
       loadStatus = KandoLoadStatus.loading;

  final String cardId;
  final CardDetail? _detail;
  final AppCurrency currency;
  final CardPriceChartMode selectedPriceChartMode;
  final CardPriceRange selectedPriceRange;
  final CardCollectionItemDraft? collectionItemDraft;
  final String? editingCollectionItemId;
  final String? collectionItemFormError;
  final KandoLoadStatus loadStatus;

  bool get isUnavailable => loadStatus == KandoLoadStatus.failure;
  bool get isLoading => loadStatus == KandoLoadStatus.loading;

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
        totalText: _formatter.formatUsd(
          item.purchasePriceUsd == null
              ? null
              : item.purchasePriceUsd! * item.quantity,
        ),
        notes: item.notes,
      );
    }).toList();
  }

  List<CardPricePointRow> get priceSeriesRows {
    final seriesByRange = selectedPriceChartMode == CardPriceChartMode.raw
        ? detail.priceSeriesByRange
        : detail.gradedPriceSeriesByRange;
    final points =
        seriesByRange[selectedPriceRange] ?? const <CardPricePoint>[];
    return points.map((point) {
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
    return detail.marketPrices.map((price) {
      return CardMarketRow(
        label: price.label,
        priceText: _formatter.formatUsd(price.priceUsd),
        changeText: _marketChange7d(price).percentText,
      );
    }).toList();
  }

  List<CardSoldListingRow> get soldListingRows {
    return detail.soldListings.map((listing) {
      return CardSoldListingRow(
        dateText: listing.dateText,
        title: listing.title,
        priceText: _formatter.formatUsd(listing.priceUsd),
        platform: listing.platform,
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
    return MarketChange.fromPrices(
      current: price.priceUsd,
      previous: price.previous7dPriceUsd,
    );
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
    Object? collectionItemDraft = _cardDetailStateUnset,
    Object? editingCollectionItemId = _cardDetailStateUnset,
    Object? collectionItemFormError = _cardDetailStateUnset,
  }) {
    return CardDetailState(
      cardId: cardId,
      detail: detail ?? this.detail,
      currency: currency ?? this.currency,
      selectedPriceChartMode:
          selectedPriceChartMode ?? this.selectedPriceChartMode,
      selectedPriceRange: selectedPriceRange ?? this.selectedPriceRange,
      collectionItemDraft: collectionItemDraft == _cardDetailStateUnset
          ? this.collectionItemDraft
          : collectionItemDraft as CardCollectionItemDraft?,
      editingCollectionItemId: editingCollectionItemId == _cardDetailStateUnset
          ? this.editingCollectionItemId
          : editingCollectionItemId as String?,
      collectionItemFormError: collectionItemFormError == _cardDetailStateUnset
          ? this.collectionItemFormError
          : collectionItemFormError as String?,
    );
  }
}

class CardDetailController extends Notifier<CardDetailState> {
  CardDetailController(this.cardId);

  final String cardId;
  Completer<void>? _loadCompleter;
  var _loadGeneration = 0;

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

    final currency = ref.watch(selectedCurrencyProvider);
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

  void startAddingCollectionItem() {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(
      collectionItemDraft: const CardCollectionItemDraft(
        quantityText: '1',
        portfolioName: _defaultPortfolioName,
        grader: 'Raw',
        condition: _defaultCondition,
        grade: '',
        language: '',
        finish: '',
        purchasePriceText: '',
        notes: '',
      ).copyWith(language: state.detail.language, finish: state.detail.finish),
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
        language: item.language ?? state.detail.language,
        finish: item.finish ?? state.detail.finish,
        purchasePriceText: item.purchasePriceUsd?.toStringAsFixed(2) ?? '',
        notes: item.notes,
      ),
      editingCollectionItemId: item.id,
      collectionItemFormError: null,
    );
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
    if (state.isUnavailable || state.isLoading || draft == null) {
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

    if (draft.notes.length > 500) {
      _setCollectionItemFormError(_notesTooLongText);
      return false;
    }

    final detail = state.detail;
    final editingItemId = state.editingCollectionItemId;
    final mutationGeneration = _loadGeneration;
    final draftItem = CardCollectionItem(
      id: editingItemId ?? '',
      cardRef: detail.id,
      folderId: _folderIdForPortfolioName(draft.portfolioName),
      portfolioName: draft.portfolioName,
      quantity: quantity.value!,
      grader: draft.grader,
      condition: draft.isRaw ? draft.condition : null,
      grade: draft.isRaw ? null : draft.grade,
      language: draft.language,
      finish: draft.finish,
      purchasePriceUsd: purchasePrice.value,
      notes: draft.notes,
    );
    final savedItem = editingItemId == null
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
    );
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
  }

  CardDetailRepository get _repository =>
      ref.read(cardDetailRepositoryProvider);

  AuthSession? get _session => ref.read(authControllerProvider).session;

  bool _canApplyMutation(AuthSession session, int generation) {
    return generation == _loadGeneration &&
        identical(_session, session) &&
        !state.isUnavailable &&
        !state.isLoading &&
        state.detail.id == cardId;
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
    try {
      final detail = await _repository.loadDetail(session, cardId);
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

String _folderIdForPortfolioName(String portfolioName) {
  return switch (portfolioName) {
    'Sealed' => 'sealed',
    'Empty' => 'empty',
    _ => 'main',
  };
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
