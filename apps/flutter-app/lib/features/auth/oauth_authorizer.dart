import 'package:google_sign_in/google_sign_in.dart';

const googleOAuthClientId =
    '134647928937-abbkvdc4ntfsui9utm828bc1vhgabdmo.apps.googleusercontent.com';

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

class GoogleOAuthAuthorizer implements OAuthAuthorizer {
  GoogleOAuthAuthorizer._();

  static final instance = GoogleOAuthAuthorizer._();
  Future<void>? _initialization;

  Future<void> initialize() {
    return _initialization ??= GoogleSignIn.instance.initialize(
      clientId: googleOAuthClientId,
    );
  }

  @override
  Future<OAuthAuthorizationResult?> authorize(OAuthProvider provider) async {
    if (provider == OAuthProvider.apple) {
      throw const OAuthAuthorizationUnavailable();
    }
    await initialize();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const OAuthAuthorizationUnavailable();
    }
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      return token == null
          ? null
          : OAuthAuthorizationResult.google(code: token);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
  }
}

class UnavailableOAuthAuthorizer implements OAuthAuthorizer {
  const UnavailableOAuthAuthorizer();

  @override
  Future<OAuthAuthorizationResult?> authorize(OAuthProvider provider) {
    throw const OAuthAuthorizationUnavailable();
  }
}

class OAuthAuthorizationUnavailable implements Exception {
  const OAuthAuthorizationUnavailable();
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
