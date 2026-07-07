enum OAuthProvider { google, apple }

class OAuthAuthorizationResult {
  const OAuthAuthorizationResult.google({required this.code})
    : provider = OAuthProvider.google,
      idToken = null;

  const OAuthAuthorizationResult.apple({
    required this.code,
    required this.idToken,
  }) : provider = OAuthProvider.apple;

  final OAuthProvider provider;
  final String code;
  final String? idToken;
}

abstract class OAuthAuthorizer {
  Future<OAuthAuthorizationResult?> authorize(OAuthProvider provider);
}

class MockOAuthAuthorizer implements OAuthAuthorizer {
  const MockOAuthAuthorizer();

  @override
  Future<OAuthAuthorizationResult?> authorize(OAuthProvider provider) async {
    return switch (provider) {
      OAuthProvider.google => const OAuthAuthorizationResult.google(
        code: 'mock-google:flutter-google-user:flutter.google@example.com',
      ),
      OAuthProvider.apple => const OAuthAuthorizationResult.apple(
        code: 'apple-auth-code',
        idToken: 'mock-apple:flutter-apple-user:flutter.apple@example.com',
      ),
    };
  }
}
