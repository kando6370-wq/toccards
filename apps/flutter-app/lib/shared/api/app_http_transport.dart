import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_environment.dart';
import 'app_http_transport_adapter.dart'
    if (dart.library.io) 'app_http_transport_adapter_io.dart';

enum AppHttpTransportMode { native, io }

bool get supportsNativeAppHttpTransport => isNativeAppHttpTransportPlatform;

AppHttpTransportMode parseAppHttpTransportMode(String value) => switch (value) {
  'native' => AppHttpTransportMode.native,
  'io' => AppHttpTransportMode.io,
  _ => throw StateError('Unsupported APP_HTTP_TRANSPORT "$value".'),
};

class AppHttpTransport {
  AppHttpTransport({required this.mode, HttpClientAdapter? adapter})
    : adapter = adapter ?? _createAdapter(mode);

  factory AppHttpTransport.fromEnvironment() {
    return AppHttpTransport(
      mode: parseAppHttpTransportMode(AppConfig.httpTransportName),
    );
  }

  final AppHttpTransportMode mode;
  final HttpClientAdapter adapter;

  bool get usesNativeTransport => mode == AppHttpTransportMode.native;

  Dio bind(Dio dio) {
    dio.httpClientAdapter = adapter;
    return dio;
  }

  void close() => adapter.close(force: true);

  static HttpClientAdapter _createAdapter(AppHttpTransportMode mode) {
    return createAppHttpClientAdapter(
      useNative: mode == AppHttpTransportMode.native,
    );
  }
}

final appHttpTransportProvider = Provider<AppHttpTransport>((ref) {
  final transport = AppHttpTransport.fromEnvironment();
  ref.onDispose(transport.close);
  return transport;
});

final appImageDioProvider = Provider<Dio>((ref) {
  return ref.watch(appHttpTransportProvider).bind(Dio());
});
