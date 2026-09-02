import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kando_app/shared/pagination/pagination.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/shared/api/api_dio_factory.dart';
import 'package:kando_app/shared/api/api_request_executor.dart';
import 'package:kando_app/shared/api/in_flight_request_coalescer.dart';
import 'package:uuid/uuid.dart';

const portfolioApiBaseUrl = authApiBaseUrl;
const duplicateCollectionItemErrorCode = 'DUPLICATE_COLLECTION_ITEM';
const duplicateCollectionItemMessage =
    'This card with the same finish, language, and grading is already in this portfolio.';
const portfolioRequestDeadline = Duration(seconds: 15);
const portfolioRequestTimeoutCode = 'REQUEST_TIMEOUT';
const portfolioRequestTimeoutMessage = 'Request timed out. Please try again.';

Dio createPortfolioDio({String baseUrl = portfolioApiBaseUrl}) {
  return createApiDio(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: portfolioRequestDeadline,
  );
}

class PortfolioApiException implements Exception {
  const PortfolioApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

bool _isAmbiguousCreateFailure(PortfolioApiException error) {
  final statusCode = error.statusCode;
  return statusCode == null ||
      statusCode == 408 ||
      (statusCode >= 500 && statusCode <= 599);
}

class PortfolioFolderDto {
  const PortfolioFolderDto({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final bool isDefault;
  final int sortOrder;

  factory PortfolioFolderDto.fromJson(Map<String, Object?> json) {
    return PortfolioFolderDto(
      id: _requiredString(json['id']),
      name: _requiredString(json['name']),
      isDefault: json['is_default'] == true,
      sortOrder: _requiredInt(json['sort_order']),
    );
  }
}

class UserPreferenceDto {
  const UserPreferenceDto({
    required this.currency,
    required this.amountHidden,
    required this.lastSelectedFolderId,
  });

  final String currency;
  final bool amountHidden;
  final String? lastSelectedFolderId;

  factory UserPreferenceDto.fromJson(Map<String, Object?> json) {
    return UserPreferenceDto(
      currency: _requiredString(json['currency']),
      amountHidden: json['amount_hidden'] == true,
      lastSelectedFolderId: _nullableString(json['last_selected_folder_id']),
    );
  }
}

class CollectionDashboardItemDto {
  const CollectionDashboardItemDto({
    required this.id,
    required this.cardRef,
    required this.folderId,
    required this.name,
    required this.setName,
    required this.cardNumber,
    required this.rarity,
    required this.game,
    required this.language,
    required this.finish,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.quantity,
    required this.marketPriceUsd,
    required this.previous30dPriceUsd,
    this.increasePercent,
    required this.folderJoinedAt,
    required this.createdAt,
    required this.imageUrl,
  });

  final String id;
  final String cardRef;
  final String? folderId;
  final String name;
  final String setName;
  final String cardNumber;
  final String rarity;
  final String game;
  final String language;
  final String finish;
  final String grader;
  final String? condition;
  final double? grade;
  final int quantity;
  final double? marketPriceUsd;
  final double? previous30dPriceUsd;
  final double? increasePercent;
  final DateTime folderJoinedAt;
  final DateTime createdAt;
  final String? imageUrl;

  factory CollectionDashboardItemDto.fromJson(Map<String, Object?> json) {
    return CollectionDashboardItemDto(
      id: _requiredString(json['id']),
      cardRef: _requiredString(json['card_ref']),
      folderId: _nullableString(json['folder_id']),
      name: _requiredString(json['name']),
      setName: _requiredString(json['set_name']),
      cardNumber: _stringOrEmpty(json['card_number']),
      rarity: _stringOrEmpty(json['rarity']),
      game: _requiredString(json['game']),
      language:
          _nullableString(json['language']) ??
          _nullableString(json['market_language']) ??
          'Unknown',
      finish:
          _nullableString(json['finish']) ??
          _nullableString(json['market_finish']) ??
          'Unknown',
      grader: _nullableString(json['grader']) ?? 'Raw',
      condition:
          _nullableString(json['condition']) ??
          _nullableString(json['market_condition']),
      grade: _nullableDouble(json['grade']),
      quantity: json['quantity'] is int ? json['quantity']! as int : 1,
      marketPriceUsd: _nullableDouble(json['market_price_usd']),
      previous30dPriceUsd: _nullableDouble(json['previous_30d_price_usd']),
      increasePercent: _nullableDouble(json['increase_percent']),
      folderJoinedAt: _requiredDateTime(
        json['folder_joined_at'] ?? json['created_at'],
      ),
      createdAt: _requiredDateTime(json['created_at']),
      imageUrl: _nullableString(json['image_url']),
    );
  }
}

class CollectionDashboardDto {
  const CollectionDashboardDto({
    required this.folders,
    required this.portfolioItems,
    required this.wishlistItems,
    required this.preference,
  });

  final List<PortfolioFolderDto> folders;
  final List<CollectionDashboardItemDto> portfolioItems;
  final List<CollectionDashboardItemDto> wishlistItems;
  final UserPreferenceDto preference;

  factory CollectionDashboardDto.fromJson(Map<String, Object?> json) {
    return CollectionDashboardDto(
      folders: _itemsFrom(
        json['folders'],
      ).map(PortfolioFolderDto.fromJson).toList(),
      portfolioItems: _itemsFrom(
        json['portfolio_items'],
      ).map(CollectionDashboardItemDto.fromJson).toList(),
      wishlistItems: _itemsFrom(
        json['wishlist_items'],
      ).map(CollectionDashboardItemDto.fromJson).toList(),
      preference: UserPreferenceDto.fromJson(_mapItem(json['preference'])),
    );
  }
}

class PortfolioItemDto {
  const PortfolioItemDto({
    required this.id,
    required this.folderId,
    required this.cardRef,
    required this.objectType,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.language,
    required this.finish,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseCurrency,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String folderId;
  final String cardRef;
  final String objectType;
  final String grader;
  final String? condition;
  final double? grade;
  final String? language;
  final String? finish;
  final int quantity;
  final double? purchasePrice;
  final String? purchaseCurrency;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PortfolioItemDto.fromJson(Map<String, Object?> json) {
    return PortfolioItemDto(
      id: _requiredString(json['id']),
      folderId: _requiredString(json['folder_id']),
      cardRef: _requiredString(json['card_ref']),
      objectType: _requiredString(json['object_type']),
      grader: _requiredString(json['grader']),
      condition: _nullableString(json['condition']),
      grade: _nullableDouble(json['grade']),
      language: _nullableString(json['language']),
      finish: _nullableString(json['finish']),
      quantity: _requiredInt(json['quantity']),
      purchasePrice: _nullableDouble(json['purchase_price']),
      purchaseCurrency: _nullableString(json['purchase_currency']),
      notes: _nullableString(json['notes']),
      createdAt: _requiredDateTime(json['created_at']),
      updatedAt: _requiredDateTime(json['updated_at']),
    );
  }
}

class PortfolioValuationPointDto {
  const PortfolioValuationPointDto({
    required this.date,
    required this.valueUsd,
  });

  final String date;
  final double valueUsd;

  factory PortfolioValuationPointDto.fromJson(Map<String, Object?> json) {
    return PortfolioValuationPointDto(
      date: _requiredString(json['date']),
      valueUsd: _requiredDouble(json['value_usd']),
    );
  }
}

class PortfolioMostValuableDto {
  const PortfolioMostValuableDto({
    required this.itemId,
    required this.cardRef,
    required this.name,
    required this.setName,
    required this.cardNumber,
    required this.finish,
    required this.imageUrl,
    required this.priceUsd,
    required this.previous30dPriceUsd,
    this.increasePercent,
  });

  final String itemId;
  final String cardRef;
  final String name;
  final String setName;
  final String cardNumber;
  final String? finish;
  final String? imageUrl;
  final double priceUsd;
  final double? previous30dPriceUsd;
  final double? increasePercent;

  factory PortfolioMostValuableDto.fromJson(Map<String, Object?> json) {
    return PortfolioMostValuableDto(
      itemId: _requiredString(json['item_id']),
      cardRef: _requiredString(json['card_ref']),
      name: _requiredString(json['name']),
      setName: _requiredString(json['set_name']),
      cardNumber: _stringOrEmpty(json['card_number']),
      finish: _nullableString(json['finish']),
      imageUrl: _nullableString(json['image_url']),
      priceUsd: _requiredDouble(json['price_usd']),
      previous30dPriceUsd: _nullableDouble(json['previous_30d_price_usd']),
      increasePercent: _nullableDouble(json['increase_percent']),
    );
  }
}

class PortfolioFolderValuationDto {
  const PortfolioFolderValuationDto({
    required this.folderId,
    required this.itemCount,
    required this.marketPriceStatus,
    required this.currentValueUsd,
    required this.series,
    required this.mostValuable,
  });

  final String folderId;
  final int itemCount;
  final MarketPriceStatus marketPriceStatus;
  final double currentValueUsd;
  final List<PortfolioValuationPointDto> series;
  final List<PortfolioMostValuableDto> mostValuable;

  factory PortfolioFolderValuationDto.fromJson(Map<String, Object?> json) {
    final series = json['series'];
    final mostValuable = json['most_valuable'];
    if (series is! List || mostValuable is! List) {
      throw const PortfolioApiException(
        'Something went wrong. Please try again.',
      );
    }
    final marketPriceStatus = switch (_requiredString(
      json['market_price_status'],
    )) {
      'available' => MarketPriceStatus.available,
      'missing' => MarketPriceStatus.missing,
      _ => throw const PortfolioApiException(
        'Something went wrong. Please try again.',
      ),
    };
    return PortfolioFolderValuationDto(
      folderId: _requiredString(json['folder_id']),
      itemCount: _requiredInt(json['item_count']),
      marketPriceStatus: marketPriceStatus,
      currentValueUsd: _requiredDouble(json['current_value_usd']),
      series: series
          .map(_mapItem)
          .map(PortfolioValuationPointDto.fromJson)
          .toList(),
      mostValuable: mostValuable
          .map(_mapItem)
          .map(PortfolioMostValuableDto.fromJson)
          .toList(),
    );
  }
}

enum PerformanceRange {
  oneDay('1D'),
  sevenDays('7D'),
  fifteenDays('15D'),
  oneMonth('1M'),
  threeMonths('3M'),
  oneYear('1Y');

  const PerformanceRange(this.apiValue);

  final String apiValue;
}

enum PurchasePriceStatus { complete, partial, missing }

enum MarketPriceStatus { available, missing }

class PortfolioTopPerformerDto {
  const PortfolioTopPerformerDto({
    required this.itemId,
    required this.cardRef,
    required this.name,
    required this.setName,
    required this.cardNumber,
    required this.imageUrl,
    required this.profitLossUsd,
    required this.returnPercent,
    required this.marketValueUsd,
  });

  final String itemId;
  final String cardRef;
  final String name;
  final String setName;
  final String cardNumber;
  final String? imageUrl;
  final double profitLossUsd;
  final double? returnPercent;
  final double marketValueUsd;

  factory PortfolioTopPerformerDto.fromJson(Map<String, Object?> json) {
    return PortfolioTopPerformerDto(
      itemId: _requiredString(json['item_id']),
      cardRef: _requiredString(json['card_ref']),
      name: _requiredString(json['name']),
      setName: _requiredString(json['set_name']),
      cardNumber: _stringOrEmpty(json['card_number']),
      imageUrl: _nullableString(json['image_url']),
      profitLossUsd: _requiredDouble(json['profit_loss_usd']),
      returnPercent: _nullableDouble(json['return_percent']),
      marketValueUsd: _requiredDouble(json['market_value_usd']),
    );
  }
}

class PerformancePointDto {
  const PerformancePointDto({
    required this.date,
    required this.marketValueUsd,
    required this.marketValueChangeUsd,
    required this.marketChangeUsd,
    required this.portfolioChangeUsd,
    required this.paidMarketValueUsd,
    required this.totalPaidUsd,
    required this.profitLossUsd,
    required this.profitLossChangeUsd,
    required this.returnPercent,
    required this.quantity,
    required this.quantityChange,
  });

  final String date;
  final double marketValueUsd;
  final double? marketValueChangeUsd;
  final double? marketChangeUsd;
  final double? portfolioChangeUsd;
  final double? paidMarketValueUsd;
  final double? totalPaidUsd;
  final double? profitLossUsd;
  final double? profitLossChangeUsd;
  final double? returnPercent;
  final int quantity;
  final int? quantityChange;

  factory PerformancePointDto.fromJson(Map<String, Object?> json) {
    return PerformancePointDto(
      date: _requiredString(json['date']),
      marketValueUsd: _requiredDouble(json['market_value_usd']),
      marketValueChangeUsd: _nullableDouble(json['market_value_change_usd']),
      marketChangeUsd: _nullableDouble(json['market_change_usd']),
      portfolioChangeUsd: _nullableDouble(json['portfolio_change_usd']),
      paidMarketValueUsd: _nullableDouble(json['paid_market_value_usd']),
      totalPaidUsd: _nullableDouble(json['total_paid_usd']),
      profitLossUsd: _nullableDouble(json['profit_loss_usd']),
      profitLossChangeUsd: _nullableDouble(json['profit_loss_change_usd']),
      returnPercent: _nullableDouble(json['return_percent']),
      quantity: _requiredInt(json['quantity']),
      quantityChange: _nullableInt(json['quantity_change']),
    );
  }
}

class PortfolioPerformanceDto {
  const PortfolioPerformanceDto({
    required this.range,
    required this.rangeStart,
    required this.rangeEnd,
    required this.historyAvailableFrom,
    required this.partialHistory,
    required this.itemCount,
    required this.marketPriceStatus,
    required this.purchasePriceStatus,
    required this.purchasePriceItemCount,
    this.topPerformerCount = 0,
    this.topPerformerItemIds = const [],
    this.topPerformers = const [],
    required this.current,
    required this.series,
  });

  final PerformanceRange range;
  final String rangeStart;
  final String rangeEnd;
  final String? historyAvailableFrom;
  final bool partialHistory;
  final int itemCount;
  final MarketPriceStatus marketPriceStatus;
  final PurchasePriceStatus purchasePriceStatus;
  final int purchasePriceItemCount;
  final int topPerformerCount;
  final List<String> topPerformerItemIds;
  final List<PortfolioTopPerformerDto> topPerformers;
  final PerformancePointDto current;
  final List<PerformancePointDto> series;

  factory PortfolioPerformanceDto.fromJson(Map<String, Object?> json) {
    final rangeValue = _requiredString(json['range']);
    final statusValue = _requiredString(json['purchase_price_status']);
    try {
      return PortfolioPerformanceDto(
        range: PerformanceRange.values.singleWhere(
          (range) => range.apiValue == rangeValue,
        ),
        rangeStart: _requiredString(json['range_start']),
        rangeEnd: _requiredString(json['range_end']),
        historyAvailableFrom: _nullableString(json['history_available_from']),
        partialHistory: json['partial_history'] == true,
        itemCount: _requiredInt(json['item_count']),
        marketPriceStatus: MarketPriceStatus.values.byName(
          _requiredString(json['market_price_status']),
        ),
        purchasePriceStatus: PurchasePriceStatus.values.byName(statusValue),
        purchasePriceItemCount: _requiredInt(json['purchase_price_item_count']),
        topPerformerCount: json['top_performer_count'] == null
            ? 0
            : _requiredInt(json['top_performer_count']),
        topPerformerItemIds: json['top_performer_item_ids'] == null
            ? const []
            : _stringsFrom(json['top_performer_item_ids']),
        topPerformers: json['top_performers'] == null
            ? const []
            : _itemsFrom(
                json['top_performers'],
              ).map(PortfolioTopPerformerDto.fromJson).toList(),
        current: PerformancePointDto.fromJson({
          'date': _requiredString(json['range_end']),
          ..._mapItem(json['current']),
        }),
        series: _itemsFrom(
          json['series'],
        ).map(PerformancePointDto.fromJson).toList(),
      );
    } on StateError {
      throw const PortfolioApiException(
        'Something went wrong. Please try again.',
      );
    } on ArgumentError {
      throw const PortfolioApiException(
        'Something went wrong. Please try again.',
      );
    }
  }
}

class WishlistItemDto {
  const WishlistItemDto({
    required this.id,
    required this.cardRef,
    required this.createdAt,
  });

  final String id;
  final String cardRef;
  final DateTime createdAt;

  factory WishlistItemDto.fromJson(Map<String, Object?> json) {
    return WishlistItemDto(
      id: _requiredString(json['id']),
      cardRef: _requiredString(json['card_ref']),
      createdAt: _requiredDateTime(json['created_at']),
    );
  }
}

class PortfolioItemDraftDto {
  const PortfolioItemDraftDto({
    required this.folderId,
    required this.cardRef,
    required this.objectType,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.language,
    required this.finish,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseCurrency,
    required this.notes,
  });

  final String folderId;
  final String cardRef;
  final String objectType;
  final String grader;
  final String? condition;
  final double? grade;
  final String? language;
  final String? finish;
  final int quantity;
  final double? purchasePrice;
  final String? purchaseCurrency;
  final String? notes;

  Map<String, Object?> toJson({bool includeCardRef = true}) {
    return {
      if (includeCardRef) 'card_ref': cardRef,
      'folder_id': folderId,
      'object_type': objectType,
      'grader': grader,
      'condition': condition,
      'grade': grade,
      'language': language,
      'finish': finish,
      'quantity': quantity,
      'purchase_price': purchasePrice,
      'purchase_currency': purchaseCurrency,
      'notes': notes,
    };
  }

  Map<String, Object?> toUpdateJson() {
    return {
      'folder_id': folderId,
      'grader': grader,
      'condition': condition,
      'grade': grade,
      'language': language,
      'finish': finish,
      'quantity': quantity,
      'purchase_price': purchasePrice,
      'purchase_currency': purchaseCurrency,
      'notes': notes,
    };
  }
}

abstract interface class PortfolioApi {
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session);
  Future<List<PortfolioItemDto>> listCollectionItems(AuthSession session);
  Future<List<PortfolioFolderValuationDto>> getValuationHistory(
    AuthSession session, {
    int days = 90,
    String? folderId,
    bool localPremiumVerified = false,
    ApiRequestDeadline? deadline,
  });
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
    ApiRequestDeadline? deadline,
  });
  Future<PortfolioPerformanceDto> getItemPerformance(
    AuthSession session, {
    required String itemId,
    required PerformanceRange range,
    bool localPremiumVerified = false,
    ApiRequestDeadline? deadline,
  });
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session);
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  });
  Future<PortfolioItemDto> createCollectionItem(
    AuthSession session,
    PortfolioItemDraftDto draft, {
    String? idempotencyKey,
  });
  Future<PortfolioItemDto> updateCollectionItem(
    AuthSession session, {
    required String itemId,
    required PortfolioItemDraftDto draft,
  });
  Future<void> deleteCollectionItem(AuthSession session, String itemId);
  Future<WishlistItemDto> addWishlist(AuthSession session, String cardRef);
  Future<void> deleteWishlist(AuthSession session, String itemId);
}

abstract interface class CollectionDashboardApi {
  Future<CollectionDashboardDto> getCollectionDashboard(AuthSession session);
}

abstract interface class PortfolioManagementApi {
  Future<PortfolioFolderDto> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  });
  Future<PortfolioFolderDto> renameFolder(
    AuthSession session,
    String folderId,
    String name,
  );
  Future<PortfolioFolderDto> setDefaultFolder(
    AuthSession session,
    String folderId,
  );
  Future<void> reorderFolders(AuthSession session, List<String> folderIds);
  Future<void> deleteFolder(AuthSession session, String folderId);
  Future<UserPreferenceDto> getPreferences(AuthSession session);
  Future<UserPreferenceDto> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  });
}

class PortfolioApiClient
    implements PortfolioApi, PortfolioManagementApi, CollectionDashboardApi {
  PortfolioApiClient(
    this._dio, {
    this.requestDeadline = portfolioRequestDeadline,
    this.readRetryPolicy = ApiRetryPolicy.transientRead,
    this.retrySleep,
    InFlightRequestCoalescer? inFlightReads,
  }) : _inFlightReads = inFlightReads ?? InFlightRequestCoalescer();

  final Dio _dio;
  final Duration requestDeadline;
  final ApiRetryPolicy readRetryPolicy;
  final ApiRequestSleep? retrySleep;
  final InFlightRequestCoalescer _inFlightReads;
  final Map<String, String> _pendingFolderRequestIds = {};
  final Map<String, String> _pendingItemRequestIds = {};
  final Map<String, String> _pendingWishlistRequestIds = {};

  @override
  Future<CollectionDashboardDto> getCollectionDashboard(
    AuthSession session,
  ) async {
    final data = await _requestReadData('/collection/dashboard', session);
    return CollectionDashboardDto.fromJson(data);
  }

  @override
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session) async {
    final data = await _requestReadData('/portfolio/folders', session);
    return _items(data).map(PortfolioFolderDto.fromJson).toList();
  }

  @override
  Future<PortfolioFolderDto> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  }) async {
    final ownerId =
        session.userId ?? session.anonymousId ?? session.accessToken;
    final operationKey =
        '${session.ownerType.name}\u0000$ownerId\u0000${name.trim()}';
    final requestId = _pendingFolderRequestIds.putIfAbsent(
      operationKey,
      () => const Uuid().v4(),
    );
    try {
      final data = await _requestData(
        'POST',
        '/portfolio/folders',
        session,
        body: {'name': name},
        headers: {
          'Idempotency-Key': requestId,
          if (localPremiumVerified) 'X-Local-Premium-State': 'verified',
        },
      );
      final folder = PortfolioFolderDto.fromJson(data);
      _pendingFolderRequestIds.remove(operationKey);
      return folder;
    } on PortfolioApiException catch (error) {
      if (!_isAmbiguousCreateFailure(error)) {
        _pendingFolderRequestIds.remove(operationKey);
      }
      rethrow;
    }
  }

  @override
  Future<PortfolioFolderDto> renameFolder(
    AuthSession session,
    String folderId,
    String name,
  ) async {
    final data = await _requestData(
      'PATCH',
      '/portfolio/folders/${Uri.encodeComponent(folderId)}',
      session,
      body: {'name': name},
    );
    return PortfolioFolderDto.fromJson(data);
  }

  @override
  Future<PortfolioFolderDto> setDefaultFolder(
    AuthSession session,
    String folderId,
  ) async {
    final data = await _requestData(
      'PATCH',
      '/portfolio/folders/${Uri.encodeComponent(folderId)}/set-default',
      session,
    );
    return PortfolioFolderDto.fromJson(data);
  }

  @override
  Future<void> reorderFolders(
    AuthSession session,
    List<String> folderIds,
  ) async {
    await _requestData(
      'PATCH',
      '/portfolio/folders/reorder',
      session,
      body: {
        'orders': [
          for (var index = 0; index < folderIds.length; index++)
            {'folder_id': folderIds[index], 'sort_order': (index + 1) * 100},
        ],
      },
    );
  }

  @override
  Future<void> deleteFolder(AuthSession session, String folderId) async {
    await _requestData(
      'DELETE',
      '/portfolio/folders/${Uri.encodeComponent(folderId)}',
      session,
    );
  }

  @override
  Future<UserPreferenceDto> getPreferences(AuthSession session) async {
    final data = await _requestData('GET', '/preferences', session);
    return UserPreferenceDto.fromJson(data);
  }

  @override
  Future<UserPreferenceDto> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    final data = await _requestData(
      'PATCH',
      '/preferences',
      session,
      body: {
        if (currency != null) 'currency': currency,
        if (amountHidden != null) 'amount_hidden': amountHidden,
        if (lastSelectedFolderId != null)
          'last_selected_folder_id': lastSelectedFolderId,
      },
    );
    return UserPreferenceDto.fromJson(data);
  }

  @override
  Future<List<PortfolioItemDto>> listCollectionItems(
    AuthSession session,
  ) async {
    final items = await _loadAllPages('/portfolio/items', session);
    return items.map(PortfolioItemDto.fromJson).toList();
  }

  @override
  Future<List<PortfolioFolderValuationDto>> getValuationHistory(
    AuthSession session, {
    int days = 90,
    String? folderId,
    bool localPremiumVerified = false,
    ApiRequestDeadline? deadline,
  }) async {
    final data = await _requestReadData(
      '/portfolio/valuation-history',
      session,
      queryParameters: {
        'days': days,
        if (folderId != null) 'folder_id': folderId,
      },
      headers: {if (localPremiumVerified) 'X-Local-Premium-State': 'verified'},
      deadline: deadline,
    );
    return _items(data).map(PortfolioFolderValuationDto.fromJson).toList();
  }

  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
    ApiRequestDeadline? deadline,
  }) async {
    final data = await _requestReadData(
      '/portfolio/performance',
      session,
      queryParameters: {
        'range': range.apiValue,
        if (folderId != null) 'folder_id': folderId,
      },
      headers: {if (localPremiumVerified) 'X-Local-Premium-State': 'verified'},
      deadline: deadline,
    );
    return PortfolioPerformanceDto.fromJson(data);
  }

  @override
  Future<PortfolioPerformanceDto> getItemPerformance(
    AuthSession session, {
    required String itemId,
    required PerformanceRange range,
    bool localPremiumVerified = false,
    ApiRequestDeadline? deadline,
  }) async {
    final data = await _requestReadData(
      '/portfolio/items/${Uri.encodeComponent(itemId)}/performance',
      session,
      queryParameters: {'range': range.apiValue},
      headers: {if (localPremiumVerified) 'X-Local-Premium-State': 'verified'},
      deadline: deadline,
    );
    return PortfolioPerformanceDto.fromJson(data);
  }

  @override
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session) async {
    final items = await _loadAllPages('/wishlist', session);
    return items.map(WishlistItemDto.fromJson).toList();
  }

  Future<List<Map<String, Object?>>> _loadAllPages(
    String path,
    AuthSession session,
  ) async {
    final result = <Map<String, Object?>>[];
    for (var page = 1; ; page += 1) {
      final data = await _requestReadData(
        path,
        session,
        queryParameters: {'page': page, 'page_size': kandoPageSize},
      );
      final pageItems = _items(data);
      result.addAll(pageItems);
      if (pageItems.length < kandoPageSize) return result;
    }
  }

  @override
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  }) async {
    return _createPortfolioItem(
      session,
      operation: 'quick_collect',
      path: '/cards/${Uri.encodeComponent(cardRef)}/collect',
      draft: draft,
      includeCardRef: false,
    );
  }

  @override
  Future<PortfolioItemDto> createCollectionItem(
    AuthSession session,
    PortfolioItemDraftDto draft, {
    String? idempotencyKey,
  }) async {
    return _createPortfolioItem(
      session,
      operation: 'create_item',
      path: '/portfolio/items',
      draft: draft,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<PortfolioItemDto> _createPortfolioItem(
    AuthSession session, {
    required String operation,
    required String path,
    required PortfolioItemDraftDto draft,
    String? idempotencyKey,
    bool includeCardRef = true,
  }) async {
    final ownerId =
        session.userId ?? session.anonymousId ?? session.accessToken;
    final operationKey = jsonEncode({
      'owner_type': session.ownerType.name,
      'owner_id': ownerId,
      'operation': operation,
      'draft': draft.toJson(),
    });
    final requestId =
        idempotencyKey ??
        _pendingItemRequestIds.putIfAbsent(
          operationKey,
          () => const Uuid().v4(),
        );
    try {
      final data = await _requestData(
        'POST',
        path,
        session,
        body: draft.toJson(includeCardRef: includeCardRef),
        headers: {'Idempotency-Key': requestId},
      );
      final item = PortfolioItemDto.fromJson(data);
      if (idempotencyKey == null) {
        _pendingItemRequestIds.remove(operationKey);
      }
      return item;
    } on PortfolioApiException catch (error) {
      if (idempotencyKey == null && !_isAmbiguousCreateFailure(error)) {
        _pendingItemRequestIds.remove(operationKey);
      }
      rethrow;
    }
  }

  @override
  Future<PortfolioItemDto> updateCollectionItem(
    AuthSession session, {
    required String itemId,
    required PortfolioItemDraftDto draft,
  }) async {
    final data = await _requestData(
      'PATCH',
      '/portfolio/items/${Uri.encodeComponent(itemId)}',
      session,
      body: draft.toUpdateJson(),
    );
    return PortfolioItemDto.fromJson(data);
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) async {
    await _requestData(
      'DELETE',
      '/portfolio/items/${Uri.encodeComponent(itemId)}',
      session,
    );
  }

  @override
  Future<WishlistItemDto> addWishlist(
    AuthSession session,
    String cardRef,
  ) async {
    final ownerId =
        session.userId ?? session.anonymousId ?? session.accessToken;
    final operationKey = jsonEncode({
      'owner_type': session.ownerType.name,
      'owner_id': ownerId,
      'card_ref': cardRef.trim(),
    });
    final requestId = _pendingWishlistRequestIds.putIfAbsent(
      operationKey,
      () => const Uuid().v4(),
    );
    try {
      final data = await _requestData(
        'POST',
        '/wishlist',
        session,
        body: {'card_ref': cardRef},
        headers: {'Idempotency-Key': requestId},
      );
      final item = WishlistItemDto.fromJson(data);
      _pendingWishlistRequestIds.remove(operationKey);
      return item;
    } on PortfolioApiException catch (error) {
      if (!_isAmbiguousCreateFailure(error)) {
        _pendingWishlistRequestIds.remove(operationKey);
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) async {
    await _requestData(
      'DELETE',
      '/wishlist/${Uri.encodeComponent(itemId)}',
      session,
    );
  }

  Future<Map<String, Object?>> _requestData(
    String method,
    String path,
    AuthSession session, {
    Map<String, Object?>? body,
    Map<String, Object?>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final cancelToken = CancelToken();
    late final Response<Object?> response;
    try {
      response = await _dio
          .request<Object?>(
            path,
            data: body,
            queryParameters: queryParameters,
            cancelToken: cancelToken,
            options: Options(
              method: method,
              headers: {
                'Authorization': 'Bearer ${session.accessToken}',
                ...?headers,
              },
              validateStatus: (_) => true,
            ),
          )
          .timeout(
            requestDeadline,
            onTimeout: () {
              cancelToken.cancel(portfolioRequestTimeoutCode);
              throw const PortfolioApiException(
                portfolioRequestTimeoutMessage,
                code: portfolioRequestTimeoutCode,
              );
            },
          );
    } on DioException {
      if (cancelToken.isCancelled) {
        throw const PortfolioApiException(
          portfolioRequestTimeoutMessage,
          code: portfolioRequestTimeoutCode,
        );
      }
      rethrow;
    }
    return _responseData(response);
  }

  Future<Map<String, Object?>> _requestReadData(
    String path,
    AuthSession session, {
    Map<String, Object?>? queryParameters,
    Map<String, String>? headers,
    ApiRequestDeadline? deadline,
  }) {
    final requestHeaders = <String, Object?>{
      'Authorization': 'Bearer ${session.accessToken}',
      ...?headers,
    };
    final key = jsonEncode({
      'method': 'GET',
      'path': path,
      'query': _sortedRequestValues(queryParameters),
      'headers': _sortedRequestValues(
        requestHeaders.map((key, value) => MapEntry(key.toLowerCase(), value)),
      ),
    });
    return _inFlightReads.run(key, () async {
      final response =
          await ApiRequestExecutor(
            requestDeadline: requestDeadline,
            retryPolicy: readRetryPolicy,
            sleep: retrySleep,
          ).execute(
            method: 'GET',
            request: (cancelToken, attempt) {
              return _dio.request<Object?>(
                path,
                queryParameters: queryParameters,
                cancelToken: cancelToken,
                options: Options(
                  method: 'GET',
                  headers: requestHeaders,
                  validateStatus: (_) => true,
                  extra: {apiRequestAttemptKey: attempt},
                ),
              );
            },
            timeoutException: () => const PortfolioApiException(
              portfolioRequestTimeoutMessage,
              code: portfolioRequestTimeoutCode,
            ),
            deadline: deadline,
          );
      return _responseData(response);
    });
  }

  Map<String, Object?> _responseData(Response<Object?> response) {
    final envelope = response.data;
    if (envelope is Map && envelope['success'] == true) {
      final data = envelope['data'];
      if (data is Map) {
        return Map<String, Object?>.from(data);
      }
      return <String, Object?>{};
    }

    throw _apiException(envelope, statusCode: response.statusCode);
  }

  PortfolioApiException _apiException(Object? envelope, {int? statusCode}) {
    if (envelope is Map) {
      final error = envelope['error'];
      if (error is Map) {
        return PortfolioApiException(
          _nullableString(error['message']) ??
              'Something went wrong. Please try again.',
          code: _nullableString(error['code']),
          statusCode: statusCode,
        );
      }
    }
    return PortfolioApiException(
      'Something went wrong. Please try again.',
      statusCode: statusCode,
    );
  }
}

Map<String, Object?> _sortedRequestValues(Map<String, Object?>? values) {
  if (values == null || values.isEmpty) return const {};
  final keys = values.keys.toList()..sort();
  return {for (final key in keys) key: values[key]};
}

List<Map<String, Object?>> _items(Map<String, Object?> data) {
  final items = data['items'];
  if (items is! List) {
    throw const PortfolioApiException(
      'Something went wrong. Please try again.',
    );
  }
  return items.map((item) {
    if (item is! Map) {
      throw const PortfolioApiException(
        'Something went wrong. Please try again.',
      );
    }
    return Map<String, Object?>.from(item);
  }).toList();
}

List<Map<String, Object?>> _itemsFrom(Object? items) {
  if (items is! List) {
    throw const PortfolioApiException(
      'Something went wrong. Please try again.',
    );
  }
  return items.map(_mapItem).toList();
}

List<String> _stringsFrom(Object? values) {
  if (values is! List<Object?>) {
    throw const FormatException('Expected a list of strings');
  }
  return values.map(_requiredString).toList();
}

String _requiredString(Object? value) {
  final normalized = _nullableString(value);
  if (normalized == null) {
    throw const PortfolioApiException(
      'Something went wrong. Please try again.',
    );
  }
  return normalized;
}

String _stringOrEmpty(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  throw const PortfolioApiException('Something went wrong. Please try again.');
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _requiredInt(Object? value) {
  if (value is int) return value;
  throw const PortfolioApiException('Something went wrong. Please try again.');
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  throw const PortfolioApiException('Something went wrong. Please try again.');
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is int) return value.toDouble();
  if (value is double) return value;
  throw const PortfolioApiException('Something went wrong. Please try again.');
}

double _requiredDouble(Object? value) {
  final parsed = _nullableDouble(value);
  if (parsed == null) {
    throw const PortfolioApiException(
      'Something went wrong. Please try again.',
    );
  }
  return parsed;
}

Map<String, Object?> _mapItem(Object? item) {
  if (item is! Map) {
    throw const PortfolioApiException(
      'Something went wrong. Please try again.',
    );
  }
  return Map<String, Object?>.from(item);
}

DateTime _requiredDateTime(Object? value) {
  final text = _requiredString(value);
  return DateTime.parse(text);
}
