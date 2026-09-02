import 'package:dio/dio.dart';

Dio createApiDio({
  required String baseUrl,
  required Duration connectTimeout,
  required Duration receiveTimeout,
}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    ),
  );
}
