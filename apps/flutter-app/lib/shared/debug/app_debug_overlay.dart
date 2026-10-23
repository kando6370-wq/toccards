import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_debug_overlay/flutter_debug_overlay.dart';

import '../api/api_environment.dart';

final appDebugLogBucket = LogBucket(
  maxStoredEntries: 200,
  allowDuplicates: true,
);
final appDebugHttpBucket = HttpBucket(maxStoredEntries: 200);

const appDebugHiddenFields = <String>[
  'authorization',
  'password',
  'new_password',
  'token',
  'access_token',
  'refresh_token',
  'id_token',
  'code',
];

bool _errorHandlersInstalled = false;

void configureAppDebugOverlay() {
  DebugOverlay.enabled = AppConfig.isTestEnvironment;
}

void installAppDebugErrorHandlers() {
  if (!AppConfig.isTestEnvironment ||
      !DebugOverlay.enabled ||
      _errorHandlersInstalled) {
    return;
  }
  _errorHandlersInstalled = true;

  final previousFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    appDebugLogBucket.add(
      LogEvent(
        level: LogLevel.fatal,
        message: details.exceptionAsString(),
        error: details.toDiagnosticsNode().toStringDeep(),
        stackTrace: details.stack,
      ),
    );
    if (previousFlutterErrorHandler == null) {
      FlutterError.presentError(details);
    } else {
      previousFlutterErrorHandler(details);
    }
  };

  final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    appDebugLogBucket.add(
      LogEvent(
        level: LogLevel.fatal,
        message: 'Unhandled exception',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    return previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
  };
}

void addAppDebugHttpLogging(Dio dio) {
  if (!AppConfig.isTestEnvironment) return;
  final alreadyAdded = dio.interceptors.any(
    (interceptor) => interceptor is _AppDebugDioLogInterceptor,
  );
  if (!alreadyAdded) {
    dio.interceptors.add(_AppDebugDioLogInterceptor(appDebugHttpBucket));
  }
}

Widget buildAppDebugOverlay(Widget child) {
  if (!AppConfig.isTestEnvironment) return child;
  return AppDebugOverlay(child: child);
}

class AppDebugOverlay extends StatelessWidget {
  const AppDebugOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DebugOverlay(
      hiddenFields: appDebugHiddenFields,
      logBucket: appDebugLogBucket,
      httpBucket: appDebugHttpBucket,
      child: child,
    );
  }
}

class _AppDebugDioLogInterceptor extends DioLogInterceptor {
  _AppDebugDioLogInterceptor(super.httpBucket);

  @override
  HttpRequest convertRequest(RequestOptions options) {
    final request = super.convertRequest(options);
    final body = options.data;
    if (body is! FormData) return request;

    return request.copyWith(
      body: {
        for (final field in body.fields) field.key: field.value,
        if (body.files.isNotEmpty)
          'files': [
            for (final file in body.files)
              {
                'field': file.key,
                'filename': file.value.filename,
                'content_type': file.value.contentType?.toString(),
                'length': file.value.length,
              },
          ],
      },
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (DebugOverlay.enabled && response != null) {
      httpBucket.addResponse(
        err.requestOptions.hashCode,
        convertResponse(response),
      );
    }
    super.onError(err, handler);
  }
}
