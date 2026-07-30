import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';
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

  test('api timing reports requests taking at least 3 seconds', () {
    final events = <(String, Map<String, Object?>)>[];
    final container = ProviderContainer(
      overrides: [
        analyticsProvider.overrideWithValue(
          AppAnalytics.recording(
            (event, properties) => events.add((event, properties)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final log = container.read(apiRequestLogProvider.notifier);
    final now = DateTime.now();
    final url = Uri.parse('https://api.example.test/cards');

    for (final durationMs in [2999, 3000, 3001]) {
      log.add(
        ApiRequestLogEntry(
          startedAt: now,
          method: 'GET',
          url: url,
          durationMs: durationMs,
          succeeded: true,
          statusCode: 200,
        ),
      );
    }

    final timingEvents = events
        .where((entry) => entry.$1 == AnalyticsEvent.apiTiming)
        .toList();
    expect(timingEvents, hasLength(2));
    expect(
      timingEvents.map((entry) => entry.$2[AnalyticsProperty.apiName]),
      everyElement('GET /cards'),
    );
    expect(timingEvents.map((entry) => entry.$2[AnalyticsProperty.timing]), [
      3.0,
      closeTo(3.001, 0.000001),
    ]);
  });

  test('fast request failures still report api errors', () {
    final events = <String>[];
    final container = ProviderContainer(
      overrides: [
        analyticsProvider.overrideWithValue(
          AppAnalytics.recording((event, _) => events.add(event)),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(apiRequestLogProvider.notifier)
        .add(
          ApiRequestLogEntry(
            startedAt: DateTime.now(),
            method: 'POST',
            url: Uri.parse('https://api.example.test/auth/login'),
            durationMs: 500,
            succeeded: false,
            statusCode: 500,
            errorSummary: 'HTTP 500',
          ),
        );

    expect(events, [AnalyticsEvent.apiError]);
  });
}
