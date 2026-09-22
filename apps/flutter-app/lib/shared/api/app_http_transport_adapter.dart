import 'package:dio/dio.dart';

const isNativeAppHttpTransportPlatform = false;

HttpClientAdapter createAppHttpClientAdapter({required bool useNative}) {
  return HttpClientAdapter();
}
