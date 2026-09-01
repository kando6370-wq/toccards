import 'package:dio/dio.dart';

import '../api/api_environment.dart';
import '../debug/app_debug_overlay.dart';

const mixpanelInitializationRetryDelays = <Duration>[
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 15),
];

Future<T?> initializeMixpanelWithRetry<T>({
  required Future<String?> Function() loadToken,
  required Future<T> Function(String token) initialize,
  Future<void> Function(Duration delay) wait = _waitForRetry,
}) async {
  for (
    var attempt = 0;
    attempt <= mixpanelInitializationRetryDelays.length;
    attempt++
  ) {
    if (attempt > 0) {
      await wait(mixpanelInitializationRetryDelays[attempt - 1]);
    }
    try {
      final token = await loadToken();
      if (token != null) return await initialize(token);
    } on Object {
      // Retry according to the current cold-start schedule.
    }
  }
  return null;
}

Future<void> _waitForRetry(Duration delay) => Future<void>.delayed(delay);

Future<String?> loadMixpanelProjectToken({Dio? dio}) async {
  final client =
      dio ??
      Dio(
        BaseOptions(
          baseUrl: kandoApiBaseUrl,
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
  addAppDebugHttpLogging(client);
  try {
    final response = await client.get<Object?>('/app-config');
    return mixpanelProjectTokenFromResponse(response.data);
  } on Object {
    return null;
  }
}

String? mixpanelProjectTokenFromResponse(Object? responseData) {
  if (responseData is! Map) return null;
  final data = responseData['data'];
  if (data is! Map) return null;
  final token = data['mixpanel_project_token'];
  if (token is! String || token.trim().isEmpty) return null;
  return token.trim();
}
