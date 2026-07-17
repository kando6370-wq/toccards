import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card_data_api_client.dart';

final cardDataDioProvider = Provider((ref) {
  final dio = createCardDataDio();
  ref.onDispose(dio.close);
  return dio;
});

final cardDataApiClientProvider = Provider<CardDataApi>((ref) {
  return CardDataApiClient(ref.watch(cardDataDioProvider));
});

final setCatalogApiClientProvider = Provider<SetCatalogApi>((ref) {
  return CardDataApiClient(ref.watch(cardDataDioProvider));
});
