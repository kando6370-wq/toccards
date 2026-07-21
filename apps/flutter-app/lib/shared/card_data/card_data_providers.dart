import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_request_log.dart';
import 'card_data_api_client.dart';

final cardDataDioProvider = Provider((ref) {
  final dio = createCardDataDio();
  dio.interceptors.add(
    ApiRequestTimingInterceptor(ref.read(apiRequestLogProvider.notifier)),
  );
  ref.onDispose(dio.close);
  return dio;
});

final cardDataApiClientProvider = Provider<CardDataApi>((ref) {
  return CardDataApiClient(ref.watch(cardDataDioProvider));
});

final setCatalogApiClientProvider = Provider<SetCatalogApi>((ref) {
  return CardDataApiClient(ref.watch(cardDataDioProvider));
});
