import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../shared/api/api_environment.dart';

class AndroidIntegrityEvidence {
  const AndroidIntegrityEvidence({
    required this.token,
    required this.requestNonce,
  });

  final String? token;
  final String requestNonce;
}

abstract interface class AndroidPlayIntegrity {
  Future<AndroidIntegrityEvidence?> createEvidence({required String deviceId});
}

class MethodChannelAndroidPlayIntegrity implements AndroidPlayIntegrity {
  const MethodChannelAndroidPlayIntegrity();

  static const _channel = MethodChannel('dev.kando.cardvault/play-integrity');
  static const _requestTimeout = Duration(seconds: 15);
  static const _cloudProjectNumber = String.fromEnvironment(
    'ANDROID_PLAY_CLOUD_PROJECT_NUMBER',
  );

  @override
  Future<AndroidIntegrityEvidence?> createEvidence({
    required String deviceId,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    if (_cloudProjectNumber.trim().isEmpty) {
      if (AppConfig.isTestEnvironment) {
        return AndroidIntegrityEvidence(
          token: null,
          requestNonce: const Uuid().v4(),
        );
      }
      throw PlatformException(
        code: 'play_integrity_not_configured',
        message: 'Android integrity verification is not configured.',
      );
    }

    final requestNonce = const Uuid().v4();
    final response = await _channel
        .invokeMapMethod<String, String>('requestStandardIntegrityToken', {
          'cloud_project_number': _cloudProjectNumber,
          'request_payload': '$deviceId\nandroid\n$requestNonce',
        })
        .timeout(
          _requestTimeout,
          onTimeout: () => throw PlatformException(
            code: 'play_integrity_timeout',
            message: 'Android integrity verification timed out.',
          ),
        );
    final token = response?['integrity_token']?.trim();
    if (token == null || token.isEmpty) {
      throw PlatformException(
        code: 'play_integrity_empty_token',
        message: 'Android integrity verification did not return a token.',
      );
    }
    return AndroidIntegrityEvidence(token: token, requestNonce: requestNonce);
  }
}
