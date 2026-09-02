import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_request_executor.dart';

const _immediateRetry = ApiRetryPolicy(
  maxAttempts: 2,
  baseDelay: Duration.zero,
  maxDelay: Duration.zero,
  jitterRatio: 0,
);

void main() {
  test('badResponse 503 retries when Dio validates status codes', () async {
    var calls = 0;
    final response =
        await ApiRequestExecutor(
          requestDeadline: const Duration(seconds: 1),
          retryPolicy: _immediateRetry,
        ).execute(
          method: 'GET',
          request: (_, attempt) async {
            calls += 1;
            final options = RequestOptions(
              path: '/catalog',
              extra: {apiRequestAttemptKey: attempt},
            );
            if (calls == 1) {
              throw DioException(
                requestOptions: options,
                response: Response<Object?>(
                  requestOptions: options,
                  statusCode: 503,
                ),
                type: DioExceptionType.badResponse,
              );
            }
            return Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: const {'success': true},
            );
          },
          timeoutException: _RequestTimeout.new,
        );

    expect(calls, 2);
    expect(response.statusCode, 200);
  });

  test('badResponse 409 remains terminal', () async {
    var calls = 0;
    final executor = ApiRequestExecutor(
      requestDeadline: const Duration(seconds: 1),
      retryPolicy: _immediateRetry,
    );

    await expectLater(
      executor.execute(
        method: 'GET',
        request: (_, _) async {
          calls += 1;
          final options = RequestOptions(path: '/premium');
          throw DioException(
            requestOptions: options,
            response: Response<Object?>(
              requestOptions: options,
              statusCode: 409,
            ),
            type: DioExceptionType.badResponse,
          );
        },
        timeoutException: _RequestTimeout.new,
      ),
      throwsA(isA<DioException>()),
    );

    expect(calls, 1);
  });

  test('badResponse 429 does not retry past the Retry-After cap', () async {
    var calls = 0;
    final options = RequestOptions(path: '/rate-limited');
    final error = DioException(
      requestOptions: options,
      response: Response<Object?>(
        requestOptions: options,
        statusCode: 429,
        headers: Headers.fromMap({
          'retry-after': ['10'],
        }),
      ),
      type: DioExceptionType.badResponse,
    );

    await expectLater(
      ApiRequestExecutor(
        requestDeadline: const Duration(seconds: 15),
        retryPolicy: _immediateRetry,
      ).execute(
        method: 'GET',
        request: (_, _) async {
          calls += 1;
          throw error;
        },
        timeoutException: _RequestTimeout.new,
      ),
      throwsA(same(error)),
    );

    expect(calls, 1);
  });

  test('sequential work shares one absolute deadline', () async {
    final deadline = ApiRequestDeadline(const Duration(milliseconds: 50));

    await runWithinApiDeadline(
      deadline,
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
      timeoutException: _RequestTimeout.new,
    );

    await expectLater(
      runWithinApiDeadline(
        deadline,
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
        timeoutException: _RequestTimeout.new,
      ),
      throwsA(isA<_RequestTimeout>()),
    );
  });
}

class _RequestTimeout implements Exception {}
