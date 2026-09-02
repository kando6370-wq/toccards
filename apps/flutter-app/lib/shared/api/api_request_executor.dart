import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

const apiRequestAttemptKey = 'kando.request.attempt';
const apiRequestTimeoutCancelReason = 'REQUEST_TIMEOUT';

typedef ApiRequestCall<T> =
    Future<Response<T>> Function(CancelToken cancelToken, int attempt);
typedef ApiRequestSleep = Future<void> Function(Duration duration);

class ApiRequestDeadline {
  ApiRequestDeadline(this.budget)
    : assert(budget > Duration.zero),
      _stopwatch = Stopwatch()..start();

  final Duration budget;
  final Stopwatch _stopwatch;

  Duration get remaining {
    final value = budget - _stopwatch.elapsed;
    return value > Duration.zero ? value : Duration.zero;
  }
}

Future<T> runWithinApiDeadline<T>(
  ApiRequestDeadline deadline,
  Future<T> Function() operation, {
  required Object Function() timeoutException,
}) {
  final remaining = deadline.remaining;
  if (remaining <= Duration.zero) {
    return Future<T>.error(timeoutException());
  }
  return Future<T>.sync(
    operation,
  ).timeout(remaining, onTimeout: () => throw timeoutException());
}

class ApiRetryPolicy {
  const ApiRetryPolicy({
    required this.maxAttempts,
    this.baseDelay = const Duration(milliseconds: 300),
    this.maxDelay = const Duration(seconds: 2),
    this.jitterRatio = 0.3,
    this.retryableMethods = const {'GET', 'HEAD'},
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
  }) : assert(maxAttempts >= 1),
       assert(jitterRatio >= 0);

  static const none = ApiRetryPolicy(maxAttempts: 1);
  static const transientRead = ApiRetryPolicy(maxAttempts: 2);

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final double jitterRatio;
  final Set<String> retryableMethods;
  final Set<int> retryableStatusCodes;

  bool canRetry(String method, int attempt) {
    return attempt < maxAttempts &&
        retryableMethods.contains(method.toUpperCase());
  }

  bool shouldRetryResponse(
    String method,
    int attempt,
    Response<Object?> value,
  ) {
    final statusCode = value.statusCode;
    return canRetry(method, attempt) &&
        statusCode != null &&
        retryableStatusCodes.contains(statusCode);
  }

  bool shouldRetryException(String method, int attempt, DioException error) {
    if (!canRetry(method, attempt)) return false;
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      DioExceptionType.badResponse =>
        error.response?.statusCode != null &&
            retryableStatusCodes.contains(error.response!.statusCode),
      _ => false,
    };
  }

  Duration? retryDelay({
    required int retryNumber,
    required Random random,
    Response<Object?>? response,
  }) {
    final retryAfterSeconds = int.tryParse(
      response?.headers.value('retry-after')?.trim() ?? '',
    );
    if (retryAfterSeconds != null && retryAfterSeconds >= 0) {
      final retryAfter = Duration(seconds: retryAfterSeconds);
      return retryAfter <= maxDelay ? retryAfter : null;
    }

    final multiplier = 1 << (retryNumber - 1);
    final baseMicroseconds = baseDelay.inMicroseconds * multiplier;
    final maxJitterMicroseconds = (baseMicroseconds * jitterRatio).round();
    final jitterMicroseconds = maxJitterMicroseconds == 0
        ? 0
        : random.nextInt(maxJitterMicroseconds + 1);
    final delay = Duration(microseconds: baseMicroseconds + jitterMicroseconds);
    return delay <= maxDelay ? delay : null;
  }
}

class ApiRequestExecutor {
  ApiRequestExecutor({
    required this.requestDeadline,
    this.retryPolicy = ApiRetryPolicy.none,
    ApiRequestSleep? sleep,
    Random? random,
  }) : _sleep = sleep ?? _defaultSleep,
       _random = random ?? Random();

  final Duration requestDeadline;
  final ApiRetryPolicy retryPolicy;
  final ApiRequestSleep _sleep;
  final Random _random;

  Future<Response<Object?>> execute({
    required String method,
    required ApiRequestCall<Object?> request,
    required Object Function() timeoutException,
    ApiRequestDeadline? deadline,
  }) async {
    final operationDeadline = deadline ?? ApiRequestDeadline(requestDeadline);
    var attempt = 1;

    while (true) {
      final remaining = operationDeadline.remaining;
      if (remaining <= Duration.zero) throw timeoutException();

      final cancelToken = CancelToken();
      try {
        final response = await request(cancelToken, attempt).timeout(
          remaining,
          onTimeout: () {
            cancelToken.cancel(apiRequestTimeoutCancelReason);
            throw timeoutException();
          },
        );
        if (!retryPolicy.shouldRetryResponse(method, attempt, response)) {
          return response;
        }
        if (!await _waitBeforeRetry(
          deadline: operationDeadline,
          retryNumber: attempt,
          response: response,
          timeoutException: timeoutException,
        )) {
          return response;
        }
      } on DioException catch (error) {
        if (cancelToken.isCancelled) throw timeoutException();
        if (!retryPolicy.shouldRetryException(method, attempt, error)) {
          rethrow;
        }
        if (!await _waitBeforeRetry(
          deadline: operationDeadline,
          retryNumber: attempt,
          response: error.response,
          timeoutException: timeoutException,
        )) {
          rethrow;
        }
      }
      attempt += 1;
    }
  }

  Future<bool> _waitBeforeRetry({
    required ApiRequestDeadline deadline,
    required int retryNumber,
    required Object Function() timeoutException,
    Response<Object?>? response,
  }) async {
    final delay = retryPolicy.retryDelay(
      retryNumber: retryNumber,
      random: _random,
      response: response,
    );
    final remaining = deadline.remaining;
    if (delay == null || delay >= remaining) return false;
    if (delay == Duration.zero) return true;

    await _sleep(
      delay,
    ).timeout(remaining, onTimeout: () => throw timeoutException());
    return deadline.remaining > Duration.zero;
  }
}

Future<void> _defaultSleep(Duration duration) => Future<void>.delayed(duration);
