import 'package:dio/dio.dart';

import '../api/api_environment.dart';
import '../debug/app_debug_overlay.dart';

class SingularCredentials {
  const SingularCredentials({required this.apiKey, required this.secretKey});

  final String apiKey;
  final String secretKey;
}

Future<SingularCredentials?> loadSingularCredentials({Dio? dio}) async {
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
    return singularCredentialsFromResponse(response.data);
  } on Object {
    return null;
  }
}

SingularCredentials? singularCredentialsFromResponse(Object? responseData) {
  if (responseData is! Map) return null;
  final data = responseData['data'];
  if (data is! Map) return null;
  final apiKey = data['singular_api_key'];
  final secretKey = data['singular_secret_key'];
  if (apiKey is! String || secretKey is! String) return null;
  final normalizedApiKey = apiKey.trim();
  final normalizedSecretKey = secretKey.trim();
  if (normalizedApiKey.isEmpty || normalizedSecretKey.isEmpty) return null;
  return SingularCredentials(
    apiKey: normalizedApiKey,
    secretKey: normalizedSecretKey,
  );
}
