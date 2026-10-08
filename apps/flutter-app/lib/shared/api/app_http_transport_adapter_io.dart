import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

final isNativeAppHttpTransportPlatform = Platform.isIOS || Platform.isAndroid;

HttpClientAdapter createAppHttpClientAdapter({required bool useNative}) {
  if (!useNative || !isNativeAppHttpTransportPlatform) {
    return IOHttpClientAdapter();
  }

  return NativeAdapter(
    createCronetEngine: () => CronetEngine.build(
      cacheMode: CacheMode.disabled,
      enableHttp2: true,
      enableQuic: true,
    ),
    createCupertinoConfiguration: () {
      final configuration =
          URLSessionConfiguration.ephemeralSessionConfiguration();
      configuration
        ..allowsCellularAccess = true
        ..allowsConstrainedNetworkAccess = true
        ..allowsExpensiveNetworkAccess = true
        ..cache = null
        ..httpShouldSetCookies = false;
      return configuration;
    },
    createFallbackAdapter: (_, _) => IOHttpClientAdapter(),
  );
}
