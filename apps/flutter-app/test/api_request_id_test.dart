import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_request_id.dart';

void main() {
  test(
    'each HTTP attempt gets a new request id without changing idempotency',
    () async {
      final generated = <String>[
        '123e4567-e89b-42d3-a456-426614174000',
        '123e4567-e89b-42d3-a456-426614174001',
      ];
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
      addApiRequestIdInterceptor(
        dio,
        requestIdFactory: () => generated.removeAt(0),
      );
      dio.httpClientAdapter = _RecordingAdapter(requests);
      addTearDown(dio.close);

      await dio.get<Object?>('/cards');
      await dio.post<Object?>(
        '/portfolio/items',
        options: Options(headers: {'Idempotency-Key': 'business-operation-id'}),
      );

      expect(requests.map(apiRequestIdFromOptions), [
        '123e4567-e89b-42d3-a456-426614174000',
        '123e4567-e89b-42d3-a456-426614174001',
      ]);
      expect(requests.last.headers['Idempotency-Key'], 'business-operation-id');
    },
  );

  test('a transparent retry replaces the previous physical request id', () {
    final options = RequestOptions(
      path: '/portfolio/items',
      headers: {apiRequestIdHeader: '123e4567-e89b-42d3-a456-426614174000'},
    );

    assignNewApiRequestId(
      options,
      requestIdFactory: () => '123e4567-e89b-42d3-a456-426614174001',
    );

    expect(
      apiRequestIdFromOptions(options),
      '123e4567-e89b-42d3-a456-426614174001',
    );
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.requests);

  final List<RequestOptions> requests;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"success":true,"data":{}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
