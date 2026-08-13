import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/apple_app_attest.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_api.dart';

void main() {
  test(
    'first Restore registers the hardware key before signing the JWS-bound challenge',
    () async {
      final api = _Api();
      final bridge = _Bridge();
      final storage = _Storage();

      await AppleRestoreProofSync(
        api: api,
        bridge: bridge,
        storage: storage,
      ).sync(_session, 'apple-jws');

      expect(api.calls, [
        'challenge:register:generated-key:null',
        'register:generated-key:register-attestation',
        'challenge:restore:generated-key:apple-jws',
        'restore:generated-key:restore-assertion:apple-jws',
      ]);
      expect(bridge.calls, [
        'generateKey',
        'attest:register-client-data',
        'assert:restore-client-data',
      ]);
      expect(storage.keyId, 'generated-key');
    },
  );

  test(
    'unsupported App Attest exits without API calls because local Restore must not fabricate a server grant',
    () async {
      final api = _Api();
      final bridge = _Bridge(supported: false);
      await AppleRestoreProofSync(
        api: api,
        bridge: bridge,
        storage: _Storage(),
      ).sync(_session, 'apple-jws');
      expect(api.calls, isEmpty);
      expect(bridge.calls, isEmpty);
    },
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  anonymousId: 'anonymous-id',
);

class _Storage implements AppleAppAttestKeyStorage {
  String? keyId;
  @override
  Future<String?> read() async => keyId;
  @override
  Future<void> write(String keyId) async => this.keyId = keyId;
}

class _Bridge implements AppleAppAttestBridge {
  _Bridge({this.supported = true});
  final bool supported;
  final calls = <String>[];
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<String> generateKey() async {
    calls.add('generateKey');
    return 'generated-key';
  }

  @override
  Future<String> attestKey({
    required String keyId,
    required String clientData,
  }) async {
    calls.add('attest:$clientData');
    return 'register-attestation';
  }

  @override
  Future<String> generateAssertion({
    required String keyId,
    required String clientData,
  }) async {
    calls.add('assert:$clientData');
    return 'restore-assertion';
  }
}

class _Api implements AppleRestoreProofApi {
  final calls = <String>[];
  @override
  Future<AppAttestChallenge> createAppAttestChallenge(
    AuthSession session, {
    required String purpose,
    required String requestId,
    required String keyId,
    String? signedTransactionInfo,
  }) async {
    calls.add('challenge:$purpose:$keyId:$signedTransactionInfo');
    return AppAttestChallenge(
      challenge: '$purpose-challenge',
      clientData: '$purpose-client-data',
    );
  }

  @override
  Future<void> registerAppAttestKey(
    AuthSession session, {
    required String requestId,
    required String challenge,
    required String keyId,
    required String attestation,
  }) async {
    calls.add('register:$keyId:$attestation');
  }

  @override
  Future<void> verifyRestore(
    AuthSession session, {
    required String requestId,
    required String challenge,
    required String keyId,
    required String assertion,
    required String signedTransactionInfo,
  }) async {
    calls.add('restore:$keyId:$assertion:$signedTransactionInfo');
  }

}
