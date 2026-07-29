import 'package:dio/dio.dart';

import '../api/api_environment.dart';

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
