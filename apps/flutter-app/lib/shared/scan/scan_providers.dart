import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_session_interceptor.dart';

import '../api/api_request_log.dart';
import 'scan_api_client.dart';

final scanDioProvider = Provider((ref) {
  final dio = createScanDio();
  dio.interceptors.add(
    ApiRequestTimingInterceptor(ref.read(apiRequestLogProvider.notifier)),
  );
  dio.interceptors.add(
    AuthSessionInterceptor(dio: dio, storage: ref.watch(authStorageProvider)),
  );
  ref.onDispose(dio.close);
  return dio;
});

final scanApiClientProvider = Provider<ScanApi>((ref) {
  return ScanApiClient(ref.watch(scanDioProvider));
});
