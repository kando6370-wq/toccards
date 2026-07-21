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
  HttpCurrencyRateApi(this._dio);

  final Dio _dio;
  final Map<String, double> _cachedRates = {};
  DateTime? _cachedAt;
  Future<Map<String, double>>? _loadingRates;

  static const _cacheLifetime = Duration(hours: 6);
  static const _supportedTargets = [
    'EUR',
    'JPY',
    'GBP',
    'CAD',
    'AUD',
    'NZD',
    'SGD',
  ];

  @override
  Future<double> loadUsdRate(String targetCurrency) async {
    if (targetCurrency == 'USD') return 1;
    final cachedAt = _cachedAt;
    final cachedRate = _cachedRates[targetCurrency];
    if (cachedAt != null &&
        cachedRate != null &&
        DateTime.now().difference(cachedAt) < _cacheLifetime) {
      return cachedRate;
    }

    final loading = _loadingRates ??= _loadRates();
    try {
      final rates = await loading;
      final rate = rates[targetCurrency];
      if (rate != null) return rate;
      throw const CurrencyRateApiException();
    } finally {
      if (identical(_loadingRates, loading)) {
        _loadingRates = null;
      }
    }
  }

  Future<Map<String, double>> _loadRates() async {
    final response = await _dio.get<Object?>(
      '/rates',
      queryParameters: {'base': 'USD', 'targets': _supportedTargets.join(',')},
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
    if (rates is! Map) {
      throw const CurrencyRateApiException();
    }
    final parsed = <String, double>{};
    for (final target in _supportedTargets) {
      final rate = rates[target];
      if (rate is num && rate.isFinite && rate > 0) {
        parsed[target] = rate.toDouble();
      }
    }
    if (parsed.isEmpty) throw const CurrencyRateApiException();
    _cachedRates
      ..clear()
      ..addAll(parsed);
    _cachedAt = DateTime.now();
    return parsed;
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
