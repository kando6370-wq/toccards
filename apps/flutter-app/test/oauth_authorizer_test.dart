import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/oauth_authorizer.dart';

void main() {
  test(
    'uses the iOS client audience without misclassifying it as a server client',
    () async {
      String? configuredClientId;
      String? configuredServerClientId;
      final authorizer = PlatformOAuthAuthorizer.testing(
        appleClient: _AppleClient(result: null),
        googleInitializer: ({clientId, serverClientId}) async {
          configuredClientId = clientId;
          configuredServerClientId = serverClientId;
        },
      );

      await authorizer.initialize();

      expect(configuredClientId, googleIosClientId);
      expect(configuredServerClientId, isNull);
    },
  );

  test(
    'routes Apple authorization through the native client because Apple proof must reach Workers',
    () async {
      final client = _AppleClient(
        result: const OAuthAuthorizationResult.apple(
          code: 'real-authorization-code',
          idToken: 'real.identity.token',
        ),
      );
      final authorizer = PlatformOAuthAuthorizer.testing(appleClient: client);

      final result = await authorizer.authorize(OAuthProvider.apple);

      expect(client.calls, 1);
      expect(result?.provider, OAuthProvider.apple);
      expect(result?.code, 'real-authorization-code');
      expect(result?.idToken, 'real.identity.token');
    },
  );

  test(
    'preserves Apple cancellation because cancellation must not call the backend',
    () async {
      final client = _AppleClient(result: null);
      final authorizer = PlatformOAuthAuthorizer.testing(appleClient: client);

      expect(await authorizer.authorize(OAuthProvider.apple), isNull);
      expect(client.calls, 1);
    },
  );
}

class _AppleClient implements AppleOAuthClient {
  _AppleClient({required this.result});

  final OAuthAuthorizationResult? result;
  var calls = 0;

  @override
  Future<OAuthAuthorizationResult?> authorize() async {
    calls += 1;
    return result;
  }
}
