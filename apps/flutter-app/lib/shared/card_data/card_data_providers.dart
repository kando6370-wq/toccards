import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_session_interceptor.dart';

import '../api/api_request_log.dart';
import '../debug/app_debug_overlay.dart';
import 'card_data_api_client.dart';

final cardDataDioProvider = Provider((ref) {
  final dio = createCardDataDio();
  dio.interceptors.add(
    ApiRequestTimingInterceptor(ref.read(apiRequestLogProvider.notifier)),
  );
  addAppDebugHttpLogging(dio);
  dio.interceptors.add(
    AuthSessionInterceptor(dio: dio, storage: ref.watch(authStorageProvider)),
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
