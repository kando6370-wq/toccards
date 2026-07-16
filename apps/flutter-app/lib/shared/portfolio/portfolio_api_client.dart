import 'package:dio/dio.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

const portfolioApiBaseUrl = authApiBaseUrl;

Dio createPortfolioDio({String baseUrl = portfolioApiBaseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
}

class PortfolioApiException implements Exception {
  const PortfolioApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
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
    required this.game,
    required this.language,
    required this.finish,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.quantity,
    required this.marketPriceUsd,
    required this.previous30dPriceUsd,
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
  final String game;
  final String language;
  final String finish;
  final String grader;
  final String? condition;
  final double? grade;
  final int quantity;
  final double? marketPriceUsd;
  final double? previous30dPriceUsd;
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
    );
  }
}

class PortfolioFolderValuationDto {
  const PortfolioFolderValuationDto({
    required this.folderId,
    required this.currentValueUsd,
    required this.series,
    required this.mostValuable,
  });

  final String folderId;
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
    return PortfolioFolderValuationDto(
      folderId: _requiredString(json['folder_id']),
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
  });
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session);
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  });
  Future<PortfolioItemDto> createCollectionItem(
    AuthSession session,
    PortfolioItemDraftDto draft,
  );
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
  Future<PortfolioFolderDto> createFolder(AuthSession session, String name);
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
  const PortfolioApiClient(this._dio);

  final Dio _dio;

  @override
  Future<CollectionDashboardDto> getCollectionDashboard(
    AuthSession session,
  ) async {
    final data = await _requestData('GET', '/collection/dashboard', session);
    return CollectionDashboardDto.fromJson(data);
  }

  @override
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session) async {
    final data = await _requestData('GET', '/portfolio/folders', session);
    return _items(data).map(PortfolioFolderDto.fromJson).toList();
  }

  @override
  Future<PortfolioFolderDto> createFolder(
    AuthSession session,
    String name,
  ) async {
    final data = await _requestData(
      'POST',
      '/portfolio/folders',
      session,
      body: {'name': name},
    );
    return PortfolioFolderDto.fromJson(data);
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
    final data = await _requestData(
      'GET',
      '/portfolio/items',
      session,
      queryParameters: {'page_size': 100},
    );
    return _items(data).map(PortfolioItemDto.fromJson).toList();
  }

  @override
  Future<List<PortfolioFolderValuationDto>> getValuationHistory(
    AuthSession session, {
    int days = 90,
  }) async {
    final data = await _requestData(
      'GET',
      '/portfolio/valuation-history',
      session,
      queryParameters: {'days': days},
    );
    return _items(data).map(PortfolioFolderValuationDto.fromJson).toList();
  }

  @override
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session) async {
    final data = await _requestData(
      'GET',
      '/wishlist',
      session,
      queryParameters: {'page_size': 100},
    );
    return _items(data).map(WishlistItemDto.fromJson).toList();
  }

  @override
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  }) async {
    final data = await _requestData(
      'POST',
      '/cards/${Uri.encodeComponent(cardRef)}/collect',
      session,
      body: draft.toJson(includeCardRef: false),
    );
    return PortfolioItemDto.fromJson(data);
  }

  @override
  Future<PortfolioItemDto> createCollectionItem(
    AuthSession session,
    PortfolioItemDraftDto draft,
  ) async {
    final data = await _requestData(
      'POST',
      '/portfolio/items',
      session,
      body: draft.toJson(),
    );
    return PortfolioItemDto.fromJson(data);
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
    final data = await _requestData(
      'POST',
      '/wishlist',
      session,
      body: {'card_ref': cardRef},
    );
    return WishlistItemDto.fromJson(data);
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
  }) async {
    final response = await _dio.request<Object?>(
      path,
      data: body,
      queryParameters: queryParameters,
      options: Options(
        method: method,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        validateStatus: (_) => true,
      ),
    );
    final envelope = response.data;
    if (envelope is Map && envelope['success'] == true) {
      final data = envelope['data'];
      if (data is Map) {
        return Map<String, Object?>.from(data);
      }
      return <String, Object?>{};
    }

    throw _apiException(envelope);
  }

  PortfolioApiException _apiException(Object? envelope) {
    if (envelope is Map) {
      final error = envelope['error'];
      if (error is Map) {
        return PortfolioApiException(
          _nullableString(error['message']) ??
              'Something went wrong. Please try again.',
          code: _nullableString(error['code']),
        );
      }
    }
    return const PortfolioApiException(
      'Something went wrong. Please try again.',
    );
  }
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
