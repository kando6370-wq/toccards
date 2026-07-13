import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scan_api_client.dart';

final scanDioProvider = Provider((ref) {
  final dio = createScanDio();
  ref.onDispose(dio.close);
  return dio;
});

final scanApiClientProvider = Provider<ScanApi>((ref) {
  return ScanApiClient(ref.watch(scanDioProvider));
});
