import 'package:dio/dio.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

const cardDataApiBaseUrl = authApiBaseUrl;

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
    required this.imageUrl,
    required this.rarity,
  });

  final String cardRef;
  final String name;
  final String setName;
  final String setCode;
  final String cardNumber;
  final String? finish;
  final String? language;
  final String objectType;
  final String? imageUrl;
  final String? rarity;

  factory CardDataCardDto.fromJson(Map<String, Object?> json) {
    return CardDataCardDto(
      cardRef: _requiredString(json['card_ref']),
      name: _requiredString(json['name']),
      setName: _requiredString(json['set_name']),
      setCode: _requiredString(json['set_code']),
      cardNumber: _requiredString(json['card_number']),
      finish: _nullableString(json['finish']),
      language: _nullableString(json['language']),
      objectType: _requiredString(json['object_type']),
      imageUrl: _nullableString(json['image_url']),
      rarity: _nullableString(json['rarity']),
    );
  }
}

class CardDataSetDto {
  const CardDataSetDto({
    required this.setCode,
    required this.setName,
    required this.imageUrl,
    required this.cardCount,
  });

  final String setCode;
  final String setName;
  final String? imageUrl;
  final int cardCount;

  factory CardDataSetDto.fromJson(Map<String, Object?> json) {
    return CardDataSetDto(
      setCode: _requiredString(json['set_code']),
      setName: _requiredString(json['set_name']),
      imageUrl: _nullableString(json['image_url']),
      cardCount: _requiredInt(json['card_count']),
    );
  }
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

class CardDataSoldListingDto {
  const CardDataSoldListingDto({
    required this.date,
    required this.title,
    required this.price,
    required this.platform,
  });

  final String date;
  final String title;
  final double price;
  final String platform;

  factory CardDataSoldListingDto.fromJson(Map<String, Object?> json) {
    return CardDataSoldListingDto(
      date: _requiredString(json['date']),
      title: _requiredString(json['title']),
      price: _requiredDouble(json['price']),
      platform: _requiredString(json['platform']),
    );
  }
}

abstract interface class CardDataApi {
  Future<List<CardDataCardDto>> searchCards(String query);
  Future<List<CardDataSetDto>> searchSets(String query);
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

class CardDataApiClient implements CardDataApi {
  const CardDataApiClient(this._dio);

  final Dio _dio;

  @override
  Future<List<CardDataCardDto>> searchCards(String query) async {
    final data = await _requestData(
      'GET',
      '/cards/search',
      queryParameters: {'q': query, 'page_size': 40},
    );
    return _items(data).map(CardDataCardDto.fromJson).toList();
  }

  @override
  Future<List<CardDataSetDto>> searchSets(String query) async {
    final data = await _requestData(
      'GET',
      '/sets/search',
      queryParameters: {'q': query, 'page_size': 40},
    );
    return _items(data).map(CardDataSetDto.fromJson).toList();
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
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef) async {
    final data = await _requestData(
      'GET',
      '/cards/${Uri.encodeComponent(cardRef)}/sold-listings',
    );
    return _items(data).map(CardDataSoldListingDto.fromJson).toList();
  }

  Future<Map<String, Object?>> _requestData(
    String method,
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    final response = await _dio.request<Object?>(
      path,
      queryParameters: queryParameters,
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
