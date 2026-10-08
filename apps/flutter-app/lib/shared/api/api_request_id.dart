import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

const apiRequestIdHeader = 'X-Request-ID';
const _apiRequestIdExtraKey = 'kando.apiRequestId';

typedef ApiRequestIdFactory = String Function();

void addApiRequestIdInterceptor(
  Dio dio, {
  ApiRequestIdFactory requestIdFactory = _newApiRequestId,
}) {
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        assignNewApiRequestId(options, requestIdFactory: requestIdFactory);
        handler.next(options);
      },
    ),
  );
}

String ensureApiRequestId(
  RequestOptions options, {
  ApiRequestIdFactory requestIdFactory = _newApiRequestId,
}) {
  return apiRequestIdFromOptions(options) ??
      assignNewApiRequestId(options, requestIdFactory: requestIdFactory);
}

String assignNewApiRequestId(
  RequestOptions options, {
  ApiRequestIdFactory requestIdFactory = _newApiRequestId,
}) {
  final requestId = requestIdFactory();
  options.headers[apiRequestIdHeader] = requestId;
  options.extra[_apiRequestIdExtraKey] = requestId;
  return requestId;
}

String? apiRequestIdFromOptions(RequestOptions options) {
  final stored = options.extra[_apiRequestIdExtraKey];
  if (stored is String && stored.isNotEmpty) return stored;
  final header = options.headers[apiRequestIdHeader];
  return header is String && header.isNotEmpty ? header : null;
}

String _newApiRequestId() => const Uuid().v4();
