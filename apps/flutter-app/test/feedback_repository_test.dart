import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/profile/feedback_repository.dart';

void main() {
  test(
    'submits feedback with the active session because support data must reach the authenticated API',
    () async {
      late RequestOptions recorded;
      final adapter = _RecordingAdapter((options) {
        recorded = options;
        return _json(201, {
          'success': true,
          'data': {'id': 'feedback-1', 'status': 'open'},
        });
      });
      final receipt = await HttpFeedbackRepository(_dio(adapter)).submit(
        _session,
        const FeedbackSubmission(
          email: 'person@example.com',
          types: ['Bug Report'],
          functions: ['Search'],
          message: 'Prices look stale.',
        ),
      );

      expect(receipt.id, 'feedback-1');
      expect(recorded.method, 'POST');
      expect(recorded.path, '/feedback');
      expect(recorded.headers['Authorization'], 'Bearer access-token');
      expect(recorded.data, {
        'email': 'person@example.com',
        'types': ['Bug Report'],
        'functions': ['Search'],
        'message': 'Prices look stale.',
      });
    },
  );

  test(
    'fails loudly on an API error because the page must preserve user input for retry',
    () async {
      final adapter = _RecordingAdapter(
        (_) => _json(422, {
          'success': false,
          'error': {'code': 'VALIDATION_ERROR', 'message': 'Invalid request.'},
        }),
      );

      expect(
        HttpFeedbackRepository(_dio(adapter)).submit(
          _session,
          const FeedbackSubmission(
            email: 'person@example.com',
            types: ['Other'],
            functions: ['Other'],
            message: 'Feedback',
          ),
        ),
        throwsA(
          isA<FeedbackApiException>()
              .having((error) => error.code, 'code', 'VALIDATION_ERROR')
              .having((error) => error.message, 'message', 'Invalid request.'),
        ),
      );
    },
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  anonymousId: 'anon-1',
);

Dio _dio(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
  dio.httpClientAdapter = adapter;
  return dio;
}

ResponseBody _json(int statusCode, Map<String, Object?> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
