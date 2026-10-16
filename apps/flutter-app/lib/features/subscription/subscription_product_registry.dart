import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/api/api_environment.dart';
import '../../shared/portfolio/portfolio_providers.dart';
import 'subscription_product_support.dart';

final subscriptionProductRegistryProvider = Provider(
  (ref) => SubscriptionProductRegistry(
    ref.watch(portfolioDioProvider),
    environment: AppConfig.environment,
    bundleId: () async => (await PackageInfo.fromPlatform()).packageName,
  ),
);

/// Server-approved products outlive their paywall cards. Cache is isolated by API, environment and Bundle.
class SubscriptionProductRegistry {
  SubscriptionProductRegistry(
    this.dio, {
    required this.environment,
    required this.bundleId,
  });
  final Dio dio;
  final AppEnvironment environment;
  final Future<String> Function() bundleId;
  Future<List<SupportedSubscriptionProduct>>? _pending;

  Future<List<SupportedSubscriptionProduct>> load() =>
      _pending ??= _load().whenComplete(() => _pending = null);

  Future<List<SupportedSubscriptionProduct>> _load() async {
    final bundle = await bundleId();
    final scope =
        '${environment == AppEnvironment.production ? 'production' : 'development'}:$bundle';
    final key = 'subscription.products:${dio.options.baseUrl}:$scope';
    final preferences = await SharedPreferences.getInstance();
    var cached = <SupportedSubscriptionProduct>[];
    try {
      cached = SupportedSubscriptionProduct.parse(
        preferences.getString(key) ?? '[]',
      );
    } on Object catch (error) {
      debugPrint('Invalid cached product registry: $error');
    }
    final cancel = CancelToken();
    try {
      final response = await dio
          .get<Object?>(
            '/subscription-supported-products',
            queryParameters: {'platform': 'ios'},
            cancelToken: cancel,
          )
          .timeout(const Duration(seconds: 3));
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw const FormatException('Invalid product registry');
      }
      final data = body['data'] as Map;
      if (data['scope'] != scope || data['products'] is! List) {
        throw const FormatException('Product registry scope mismatch');
      }
      final products = SupportedSubscriptionProduct.parse(
        jsonEncode(data['products']),
      );
      if (products.any((p) => p.singularEventName == null)) {
        throw const FormatException('Missing approved revenue mapping');
      }
      final merged = {for (final p in cached) p.productId: p};
      for (final p in products) {
        final previous = merged[p.productId];
        if (previous != null &&
            (previous.planId != p.planId || previous.type != p.type)) {
          throw const FormatException('A historical product mapping changed');
        }
        merged[p.productId] = p;
      }
      final encoded = jsonEncode(merged.values.map((p) => p.toJson()).toList());
      final validated = SupportedSubscriptionProduct.parse(encoded);
      await preferences.setString(key, encoded);
      return validated;
    } on Object catch (error) {
      debugPrint(
        'Product registry unavailable; retaining approved local products: $error',
      );
      if (cached.isNotEmpty) return cached;
      rethrow;
    } finally {
      cancel.cancel('Product registry lookup finished');
    }
  }
}
