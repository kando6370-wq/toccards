import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_environment.dart';

class CurrencyRateApiException implements Exception {
  const CurrencyRateApiException();
}

abstract interface class CurrencyRateApi {
  Future<double> loadUsdRate(String targetCurrency);
}

class HttpCurrencyRateApi implements CurrencyRateApi {
  const HttpCurrencyRateApi(this._dio);

  final Dio _dio;

  @override
  Future<double> loadUsdRate(String targetCurrency) async {
    final response = await _dio.get<Object?>(
      '/rates',
      queryParameters: {'base': 'USD', 'targets': targetCurrency},
      options: Options(validateStatus: (_) => true),
    );
    final envelope = response.data;
    if (envelope is! Map || envelope['success'] != true) {
      throw const CurrencyRateApiException();
    }
    final data = envelope['data'];
    if (data is! Map || data['base'] != 'USD') {
      throw const CurrencyRateApiException();
    }
    final rates = data['rates'];
    final rate = rates is Map ? rates[targetCurrency] : null;
    if (rate is num && rate.isFinite && rate > 0) {
      return rate.toDouble();
    }
    throw const CurrencyRateApiException();
  }
}

final currencyRateDioProvider = Provider((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kandoApiBaseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

final currencyRateApiProvider = Provider<CurrencyRateApi>((ref) {
  return HttpCurrencyRateApi(ref.watch(currencyRateDioProvider));
});
