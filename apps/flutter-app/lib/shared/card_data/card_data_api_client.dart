import 'package:dio/dio.dart';
import 'package:kando_app/shared/pagination/pagination.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

const cardDataApiBaseUrl = authApiBaseUrl;
const cardDataResponseVersion = '2';

Dio createCardDataDio({String baseUrl = cardDataApiBaseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
}

class CardDataApiException implements Exception {
  const CardDataApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class CardDataCardDto {
  const CardDataCardDto({
    required this.cardRef,
    required this.name,
    required this.setName,
    required this.setCode,
    required this.cardNumber,
    required this.finish,
    required this.language,
    required this.objectType,
    this.game,
    required this.imageUrl,
    required this.rarity,
    this.priceUsd,
    this.previous30dPriceUsd,
    this.previous1dPriceUsd,
    this.priceChange1dPercent,
    this.priceAsOf,
    this.previousPriceAsOf,
  });

  final String cardRef;
  final String name;
  final String setName;
  final String setCode;
  final String cardNumber;
  final String? finish;
  final String? language;
  final String objectType;
  final String? game;
  final String? imageUrl;
  final String? rarity;
  final double? priceUsd;
  final double? previous30dPriceUsd;
  final double? previous1dPriceUsd;
  final double? priceChange1dPercent;
  final String? priceAsOf;
  final String? previousPriceAsOf;

  factory CardDataCardDto.fromJson(Map<String, Object?> json) {
    return CardDataCardDto(
      cardRef: _requiredString(json['card_ref']),
      name: _requiredString(json['name']),
      setName: _requiredString(json['set_name']),
      setCode: _requiredString(json['set_code']),
      cardNumber: _stringOrEmpty(json['card_number']),
      finish: _nullableString(json['finish']),
      language: _nullableString(json['language']),
      objectType: _requiredString(json['object_type']),
      game: _nullableString(json['game']),
      imageUrl: _nullableString(json['image_url']),
      rarity: _nullableString(json['rarity']),
      priceUsd: _nullableDouble(json['price_usd']),
      previous30dPriceUsd: _nullableDouble(json['previous_30d_price_usd']),
      previous1dPriceUsd: _nullableDouble(json['previous_1d_price_usd']),
      priceChange1dPercent: _nullableDouble(json['price_change_1d_percent']),
      priceAsOf: _nullableString(json['price_as_of']),
      previousPriceAsOf: _nullableString(json['previous_price_as_of']),
    );
  }
}

class CardDataSetDto {
  const CardDataSetDto({
    required this.setCode,
    required this.setName,
    this.game,
    required this.imageUrl,
    required this.cardCount,
  });

  final String setCode;
  final String setName;
  final String? game;
  final String? imageUrl;
  final int cardCount;

  factory CardDataSetDto.fromJson(Map<String, Object?> json) {
    return CardDataSetDto(
      setCode: _requiredString(json['set_code']),
      setName: _requiredString(json['set_name']),
      game: _nullableString(json['game']),
      imageUrl: _nullableString(json['image_url']),
      cardCount: _requiredInt(json['card_count']),
    );
  }
}

class CardDataGameDto {
  const CardDataGameDto({required this.id, required this.name});

  final String id;
  final String name;

  factory CardDataGameDto.fromJson(Map<String, Object?> json) {
    return CardDataGameDto(
      id: _requiredString(json['id']),
      name: _requiredString(json['name']),
    );
  }
}

abstract interface class SetCatalogApi {
  Future<List<CardDataGameDto>> listGames();
  Future<List<CardDataSetDto>> searchCatalogSets(String query, {String? game});
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page,
  });
}

class CardDataMarketPriceDto {
  const CardDataMarketPriceDto({
    required this.grader,
    required this.grade,
    required this.condition,
    required this.price,
  });

  final String grader;
  final double? grade;
  final String? condition;
  final double? price;

  factory CardDataMarketPriceDto.fromJson(Map<String, Object?> json) {
    return CardDataMarketPriceDto(
      grader: _requiredString(json['grader']),
      grade: _nullableDouble(json['grade']),
      condition: _nullableString(json['condition']),
      price: _nullableDouble(json['price']),
    );
  }
}

class CardDataPricePointDto {
  const CardDataPricePointDto({required this.date, required this.price});

  final String date;
  final double price;

  factory CardDataPricePointDto.fromJson(Map<String, Object?> json) {
    return CardDataPricePointDto(
      date: _requiredString(json['date']),
      price: _requiredDouble(json['price']),
    );
  }
}

class CardDataPriceSeriesQuery {
  const CardDataPriceSeriesQuery({
    required this.days,
    required this.grader,
    this.grade,
    this.condition,
  });

  final int days;
  final String grader;
  final double? grade;
  final String? condition;

  Map<String, Object?> toJson() => {
    'days': days,
    'grader': grader,
    'grade': grade,
    'condition': condition,
  };
}

class CardDataSoldListingDto {
  const CardDataSoldListingDto({
    required this.date,
    required this.title,
    required this.price,
    required this.platform,
    this.url,
  });

  final String date;
  final String title;
  final double price;
  final String platform;
  final String? url;

  factory CardDataSoldListingDto.fromJson(Map<String, Object?> json) {
    return CardDataSoldListingDto(
      date: _requiredString(json['date']),
      title: _requiredString(json['title']),
      price: _requiredDouble(json['price']),
      platform: _requiredString(json['platform']),
      url: _nullableString(json['url']),
    );
  }
}

abstract interface class CardDataApi {
  Future<List<CardDataCardDto>> searchCards(String query, {String? game});
  Future<List<CardDataSetDto>> searchSets(String query, {String? game});
  Future<List<CardDataCardDto>> trendingCards();
  Future<CardDataCardDto> getCard(String cardRef);
  Future<List<CardDataMarketPriceDto>> getMarketPrices(String cardRef);
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
  });
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef);
}

abstract interface class PaginatedCardDataApi {
  Future<List<CardDataCardDto>> searchCardPage(
    String query, {
    String? game,
    required int page,
  });
}

abstract interface class BatchCardDataApi {
  Future<List<List<CardDataPricePointDto>>> getPriceSeriesBatch(
    String cardRef,
    List<CardDataPriceSeriesQuery> requests,
  );
}

class CardDataApiClient
    implements
        CardDataApi,
        PaginatedCardDataApi,
        SetCatalogApi,
        BatchCardDataApi {
  const CardDataApiClient(this._dio);

  final Dio _dio;

  @override
  Future<List<CardDataCardDto>> searchCards(String query, {String? game}) {
    return searchCardPage(query, game: game, page: 1);
  }

  @override
  Future<List<CardDataCardDto>> searchCardPage(
    String query, {
    String? game,
    required int page,
  }) async {
    final data = await _requestData(
      'GET',
      '/cards/search',
      queryParameters: {
        'q': query,
        if (game != null) 'game': game,
        'page': page,
        'page_size': kandoPageSize,
      },
    );
    return _items(data).map(CardDataCardDto.fromJson).toList();
  }

  @override
  Future<List<CardDataSetDto>> searchSets(String query, {String? game}) async {
    final data = await _requestData(
      'GET',
      '/sets/search',
      queryParameters: {
        'q': query,
        if (game != null) 'game': game,
        'page_size': kandoPageSize,
      },
    );
    return _items(data).map(CardDataSetDto.fromJson).toList();
  }

  @override
  Future<List<CardDataGameDto>> listGames() async {
    final data = await _requestData('GET', '/games');
    return _items(data).map(CardDataGameDto.fromJson).toList();
  }

  @override
  Future<List<CardDataSetDto>> searchCatalogSets(
    String query, {
    String? game,
  }) async {
    final result = <CardDataSetDto>[];
    for (var page = 1; ; page += 1) {
      final data = await _requestData(
        'GET',
        '/sets/search',
        queryParameters: {
          'q': query,
          if (game != null) 'game': game,
          'page': page,
          'page_size': kandoPageSize,
        },
      );
      final items = _items(data).map(CardDataSetDto.fromJson).toList();
      result.addAll(items);
      if (items.length < kandoPageSize) return result;
    }
  }

  @override
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page = 1,
  }) async {
    final data = await _requestData(
      'GET',
      '/cards/search',
      queryParameters: {
        'game': game,
        'set_code': setCode,
        'page': page,
        'page_size': kandoPageSize,
      },
    );
    return _items(data).map(CardDataCardDto.fromJson).toList();
  }

  @override
  Future<List<CardDataCardDto>> trendingCards() async {
    final data = await _requestData('GET', '/cards/trending');
    return _items(data).map(CardDataCardDto.fromJson).toList();
  }

  @override
  Future<CardDataCardDto> getCard(String cardRef) async {
    final data = await _requestData(
      'GET',
      '/cards/${Uri.encodeComponent(cardRef)}',
    );
    return CardDataCardDto.fromJson(data);
  }

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(String cardRef) async {
    final data = await _requestData(
      'GET',
      '/cards/${Uri.encodeComponent(cardRef)}/market-prices',
      queryParameters: {'response_version': cardDataResponseVersion},
    );
    final prices = data['prices'];
    if (prices is! List) {
      throw const CardDataApiException(
        'Something went wrong. Please try again.',
      );
    }
    return prices.map(_mapItem).map(CardDataMarketPriceDto.fromJson).toList();
  }

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
  }) async {
    final data = await _requestData(
      'GET',
      '/cards/${Uri.encodeComponent(cardRef)}/price-series',
      queryParameters: {
        'response_version': cardDataResponseVersion,
        'days': days,
        'grader': grader,
        if (grade != null) 'grade': grade,
        if (condition != null) 'condition': condition,
      },
    );
    final series = data['series'];
    if (series is! List) {
      throw const CardDataApiException(
        'Something went wrong. Please try again.',
      );
    }
    return series.map(_mapItem).map(CardDataPricePointDto.fromJson).toList();
  }

  @override
  Future<List<List<CardDataPricePointDto>>> getPriceSeriesBatch(
    String cardRef,
    List<CardDataPriceSeriesQuery> requests,
  ) async {
    if (requests.isEmpty) return const [];
    final data = await _requestData(
      'POST',
      '/cards/${Uri.encodeComponent(cardRef)}/price-series/batch',
      queryParameters: {'response_version': cardDataResponseVersion},
      body: {'requests': requests.map((request) => request.toJson()).toList()},
    );
    final results = data['results'];
    if (results is! List || results.length != requests.length) {
      throw const CardDataApiException(
        'Something went wrong. Please try again.',
      );
    }
    return results.map((result) {
      final item = _mapItem(result);
      final series = item['series'];
      if (series is! List) {
        throw const CardDataApiException(
          'Something went wrong. Please try again.',
        );
      }
      return series.map(_mapItem).map(CardDataPricePointDto.fromJson).toList();
    }).toList();
  }

  @override
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef) async {
    final data = await _requestData(
      'GET',
      '/cards/${Uri.encodeComponent(cardRef)}/sold-listings',
      queryParameters: {'response_version': cardDataResponseVersion},
    );
    return _items(data).map(CardDataSoldListingDto.fromJson).toList();
  }

  Future<Map<String, Object?>> _requestData(
    String method,
    String path, {
    Map<String, Object?>? queryParameters,
    Object? body,
  }) async {
    final response = await _dio.request<Object?>(
      path,
      queryParameters: queryParameters,
      data: body,
      options: Options(method: method, validateStatus: (_) => true),
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

  CardDataApiException _apiException(Object? envelope) {
    if (envelope is Map) {
      final error = envelope['error'];
      if (error is Map) {
        return CardDataApiException(
          _nullableString(error['message']) ??
              'Something went wrong. Please try again.',
          code: _nullableString(error['code']),
        );
      }
    }
    return const CardDataApiException(
      'Something went wrong. Please try again.',
    );
  }
}

List<Map<String, Object?>> _items(Map<String, Object?> data) {
  final items = data['items'];
  if (items is! List) {
    throw const CardDataApiException('Something went wrong. Please try again.');
  }
  return items.map(_mapItem).toList();
}

Map<String, Object?> _mapItem(Object? item) {
  if (item is! Map) {
    throw const CardDataApiException('Something went wrong. Please try again.');
  }
  return Map<String, Object?>.from(item);
}

String _requiredString(Object? value) {
  final normalized = _nullableString(value);
  if (normalized == null) {
    throw const CardDataApiException('Something went wrong. Please try again.');
  }
  return normalized;
}

String _stringOrEmpty(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  throw const CardDataApiException('Something went wrong. Please try again.');
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _requiredInt(Object? value) {
  if (value is int) return value;
  throw const CardDataApiException('Something went wrong. Please try again.');
}

double _requiredDouble(Object? value) {
  final parsed = _nullableDouble(value);
  if (parsed == null) {
    throw const CardDataApiException('Something went wrong. Please try again.');
  }
  return parsed;
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is int) return value.toDouble();
  if (value is double) return value;
  throw const CardDataApiException('Something went wrong. Please try again.');
}
