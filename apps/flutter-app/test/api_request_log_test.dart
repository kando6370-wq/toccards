import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_request_log.dart';

void main() {
  test('request log keeps duplicate recent requests and drops old entries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final log = container.read(apiRequestLogProvider.notifier);
    final now = DateTime.now();
    final url = Uri.parse('https://api.example.test/cards');

    log
      ..add(
        ApiRequestLogEntry(
          startedAt: now.subtract(const Duration(minutes: 61)),
          method: 'GET',
          url: url,
          durationMs: 11,
          succeeded: true,
          statusCode: 200,
        ),
      )
      ..add(
        ApiRequestLogEntry(
          startedAt: now,
          method: 'GET',
          url: url,
          durationMs: 20,
          succeeded: true,
          statusCode: 200,
        ),
      )
      ..add(
        ApiRequestLogEntry(
          startedAt: now.add(const Duration(milliseconds: 1)),
          method: 'GET',
          url: url,
          durationMs: 35,
          succeeded: true,
          statusCode: 200,
        ),
      );

    final entries = container.read(apiRequestLogProvider);

    expect(entries, hasLength(2));
    expect(entries.map((entry) => entry.url), [url, url]);
    expect(entries.map((entry) => entry.durationMs), [20, 35]);
  });

  test('request log entries expose detailed error information', () {
    final entry = ApiRequestLogEntry(
      startedAt: DateTime.now(),
      method: 'POST',
      url: Uri.parse('https://api.example.test/auth/login'),
      durationMs: 48,
      succeeded: false,
      statusCode: 500,
      errorSummary: 'badResponse | HTTP 500',
      errorDetails: 'response: {"error":"server failed"}',
    );

    expect(entry.hasError, isTrue);
    expect(entry.errorSummary, contains('HTTP 500'));
    expect(entry.errorDetails, contains('server failed'));
  });
}
