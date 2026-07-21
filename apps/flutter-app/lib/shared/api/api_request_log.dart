import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const apiRequestLogRetention = Duration(hours: 1);

final apiRequestLogProvider =
    NotifierProvider<ApiRequestLogController, List<ApiRequestLogEntry>>(
      ApiRequestLogController.new,
    );

class ApiRequestLogEntry {
  const ApiRequestLogEntry({
    required this.startedAt,
    required this.method,
    required this.url,
    required this.durationMs,
    required this.succeeded,
    this.statusCode,
    this.errorSummary,
    this.errorDetails,
  });

  final DateTime startedAt;
  final String method;
  final Uri url;
  final int durationMs;
  final bool succeeded;
  final int? statusCode;
  final String? errorSummary;
  final String? errorDetails;

  bool get hasError =>
      !succeeded || errorSummary != null || errorDetails != null;
}

class ApiRequestLogController extends Notifier<List<ApiRequestLogEntry>> {
  @override
  List<ApiRequestLogEntry> build() => const [];

  void add(ApiRequestLogEntry entry) {
    final cutoff = DateTime.now().subtract(apiRequestLogRetention);
    state = [
      for (final item in state)
        if (!item.startedAt.isBefore(cutoff)) item,
      if (!entry.startedAt.isBefore(cutoff)) entry,
    ];
  }

  void prune() {
    final cutoff = DateTime.now().subtract(apiRequestLogRetention);
    state = [
      for (final item in state)
        if (!item.startedAt.isBefore(cutoff)) item,
    ];
  }

  void clear() {
    state = const [];
  }
}

class ApiRequestTimingInterceptor extends Interceptor {
  ApiRequestTimingInterceptor(this._log);

  static const _startedAtKey = 'kando.requestLog.startedAt';
  static const _stopwatchKey = 'kando.requestLog.stopwatch';

  final ApiRequestLogController _log;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now();
    options.extra[_stopwatchKey] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final statusCode = response.statusCode;
    final bodyFailed = _bodyFailed(response.data);
    final succeeded = (statusCode == null || statusCode < 400) && !bodyFailed;
    _record(
      response.requestOptions,
      succeeded: succeeded,
      statusCode: statusCode,
      errorSummary: succeeded
          ? null
          : bodyFailed
          ? 'API success=false'
          : 'HTTP $statusCode',
      errorDetails: succeeded ? null : _responseDetails(response.data),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(
      err.requestOptions,
      succeeded: false,
      statusCode: err.response?.statusCode,
      errorSummary: _errorSummary(err),
      errorDetails: _errorDetails(err),
    );
    handler.next(err);
  }

  void _record(
    RequestOptions options, {
    required bool succeeded,
    required int? statusCode,
    String? errorSummary,
    String? errorDetails,
  }) {
    final startedAt = options.extra[_startedAtKey] is DateTime
        ? options.extra[_startedAtKey] as DateTime
        : DateTime.now();
    final stopwatch = options.extra[_stopwatchKey];
    final durationMs = stopwatch is Stopwatch
        ? stopwatch.elapsedMilliseconds
        : DateTime.now().difference(startedAt).inMilliseconds;

    _log.add(
      ApiRequestLogEntry(
        startedAt: startedAt,
        method: options.method.toUpperCase(),
        url: options.uri,
        durationMs: durationMs < 0 ? 0 : durationMs,
        succeeded: succeeded,
        statusCode: statusCode,
        errorSummary: errorSummary,
        errorDetails: errorDetails,
      ),
    );
  }

  String _errorSummary(DioException err) {
    final statusCode = err.response?.statusCode;
    final message = err.message;
    final prefix = statusCode == null
        ? err.type.name
        : '${err.type.name} | HTTP $statusCode';
    if (message == null || message.trim().isEmpty) return prefix;
    return '$prefix | ${message.trim()}';
  }

  String _errorDetails(DioException err) {
    final parts = <String>[
      'type: ${err.type.name}',
      if (err.message != null && err.message!.trim().isNotEmpty)
        'message: ${err.message!.trim()}',
      if (err.error != null) 'error: ${err.error}',
      if (err.response?.statusCode != null)
        'statusCode: ${err.response!.statusCode}',
      if (err.response?.statusMessage != null)
        'statusMessage: ${err.response!.statusMessage}',
      if (err.response?.data != null)
        'response: ${_responseDetails(err.response!.data)}',
    ];
    return _truncate(parts.join('\n'));
  }
}

String _responseDetails(Object? data) {
  if (data == null) return 'No response body';
  try {
    return _truncate(jsonEncode(data));
  } on Object {
    return _truncate(data.toString());
  }
}

bool _bodyFailed(Object? data) {
  return data is Map && data['success'] == false;
}

String _truncate(String value) {
  const maxLength = 2000;
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}...';
}
