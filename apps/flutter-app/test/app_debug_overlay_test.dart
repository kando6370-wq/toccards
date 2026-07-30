import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/debug/app_debug_overlay.dart';

void main() {
  setUpAll(configureAppDebugOverlay);
  setUp(appDebugHttpBucket.clear);
  tearDown(appDebugHttpBucket.clear);

  test('captures Dio requests and successful responses', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..httpClientAdapter = _ResponseAdapter(
        statusCode: 200,
        body: {
          'success': true,
          'data': {'id': 'card-1'},
        },
      );
    addAppDebugHttpLogging(dio);

    await dio.post<Object?>(
      '/cards',
      queryParameters: {'language': 'en'},
      data: {'name': 'Charizard'},
    );

    final interaction = appDebugHttpBucket.entries.single;
    expect(interaction.method, 'POST');
    expect(
      interaction.uri,
      Uri.parse('https://api.example.test/cards?language=en'),
    );
    expect(interaction.request?.body, {'name': 'Charizard'});
    expect(interaction.response?.statusCode, 200);
    expect(interaction.response?.body, {
      'success': true,
      'data': {'id': 'card-1'},
    });
    expect(interaction.error, isNull);
  });

  test('captures response details for failed HTTP requests', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..httpClientAdapter = _ResponseAdapter(
        statusCode: 500,
        body: {'success': false, 'message': 'server failed'},
      );
    addAppDebugHttpLogging(dio);

    await expectLater(
      dio.get<Object?>('/cards/card-1'),
      throwsA(isA<DioException>()),
    );

    final interaction = appDebugHttpBucket.entries.single;
    expect(interaction.response?.statusCode, 500);
    expect(interaction.response?.body, {
      'success': false,
      'message': 'server failed',
    });
    expect(interaction.error, isNotNull);
  });

  test('captures multipart metadata without retaining file bytes', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..httpClientAdapter = const _ResponseAdapter(
        statusCode: 200,
        body: {'success': true},
      );
    addAppDebugHttpLogging(dio);

    await dio.post<Object?>(
      '/scan/recognize',
      data: FormData.fromMap({
        'platform': 'ios',
        'image': MultipartFile.fromBytes(
          [1, 2, 3, 4],
          filename: 'scan-card.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      }),
    );

    expect(appDebugHttpBucket.entries.single.request?.body, {
      'platform': 'ios',
      'files': [
        {
          'field': 'image',
          'filename': 'scan-card.jpg',
          'content_type': 'image/jpeg',
          'length': 4,
        },
      ],
    });
  });

  test('does not install duplicate interceptors on the same client', () {
    final dio = Dio();
    final initialInterceptorCount = dio.interceptors.length;

    addAppDebugHttpLogging(dio);
    addAppDebugHttpLogging(dio);

    expect(dio.interceptors, hasLength(initialInterceptorCount + 1));
  });
}

class _ResponseAdapter implements HttpClientAdapter {
  const _ResponseAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
