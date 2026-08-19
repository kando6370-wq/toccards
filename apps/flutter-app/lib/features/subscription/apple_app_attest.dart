import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../shared/security/secure_storage_keys.dart';
import '../auth/auth_models.dart';
import 'subscription_entitlement_api.dart';

abstract interface class AppleAppAttestBridge {
  Future<bool> isSupported();
  Future<String> generateKey();
  Future<String> attestKey({required String keyId, required String clientData});
  Future<String> generateAssertion({
    required String keyId,
    required String clientData,
  });
}

class MethodChannelAppleAppAttestBridge implements AppleAppAttestBridge {
  const MethodChannelAppleAppAttestBridge({
    MethodChannel channel = const MethodChannel(
      'com.cardai.tcg/apple-app-attest',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<bool> isSupported() async =>
      await _channel.invokeMethod<bool>('isSupported') ?? false;

  @override
  Future<String> generateKey() async =>
      _required(await _channel.invokeMethod<String>('generateKey'));

  @override
  Future<String> attestKey({
    required String keyId,
    required String clientData,
  }) async => _required(
    await _channel.invokeMethod<String>('attestKey', {
      'key_id': keyId,
      'client_data': clientData,
    }),
  );

  @override
  Future<String> generateAssertion({
    required String keyId,
    required String clientData,
  }) async => _required(
    await _channel.invokeMethod<String>('generateAssertion', {
      'key_id': keyId,
      'client_data': clientData,
    }),
  );
}

abstract interface class AppleAppAttestKeyStorage {
  Future<String?> read();
  Future<void> write(String keyId);
}

class SecureAppleAppAttestKeyStorage implements AppleAppAttestKeyStorage {
  const SecureAppleAppAttestKeyStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: appleAppAttestKeyIdStorageKey);

  @override
  Future<void> write(String keyId) =>
      _storage.write(key: appleAppAttestKeyIdStorageKey, value: keyId);
}

class AppleRestoreProofSync {
  const AppleRestoreProofSync({
    required this.api,
    required this.bridge,
    required this.storage,
  });

  final AppleRestoreProofApi api;
  final AppleAppAttestBridge bridge;
  final AppleAppAttestKeyStorage storage;

  Future<bool> sync(AuthSession session, String signedTransactionInfo) async {
    if (!await bridge.isSupported()) return false;
    var keyId = await storage.read();
    if (keyId == null) {
      keyId = await bridge.generateKey();
      final requestId = const Uuid().v4();
      final challenge = await api.createAppAttestChallenge(
        session,
        purpose: 'register',
        requestId: requestId,
        keyId: keyId,
      );
      final attestation = await bridge.attestKey(
        keyId: keyId,
        clientData: challenge.clientData,
      );
      await api.registerAppAttestKey(
        session,
        requestId: requestId,
        challenge: challenge.challenge,
        keyId: keyId,
        attestation: attestation,
      );
      await storage.write(keyId);
    }

    final requestId = const Uuid().v4();
    final challenge = await api.createAppAttestChallenge(
      session,
      purpose: 'restore',
      requestId: requestId,
      keyId: keyId,
      signedTransactionInfo: signedTransactionInfo,
    );
    final assertion = await bridge.generateAssertion(
      keyId: keyId,
      clientData: challenge.clientData,
    );
    await api.verifyRestore(
      session,
      requestId: requestId,
      challenge: challenge.challenge,
      keyId: keyId,
      assertion: assertion,
      signedTransactionInfo: signedTransactionInfo,
    );
    return true;
  }
}

String _required(String? value) {
  if (value != null && value.isNotEmpty) return value;
  throw PlatformException(code: 'apple_app_attest_invalid_response');
}
