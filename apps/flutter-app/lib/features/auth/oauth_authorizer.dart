import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

const googleIosClientId =
    '134647928937-abbkvdc4ntfsui9utm828bc1vhgabdmo.apps.googleusercontent.com';

typedef GoogleSignInInitializer =
    Future<void> Function({String? clientId, String? serverClientId});

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

abstract interface class AppleOAuthClient {
  Future<OAuthAuthorizationResult?> authorize();
}

class NativeAppleOAuthClient implements AppleOAuthClient {
  const NativeAppleOAuthClient();

  @override
  Future<OAuthAuthorizationResult?> authorize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      throw const OAuthAuthorizationUnavailable();
    }
    if (!await SignInWithApple.isAvailable()) {
      throw const OAuthAuthorizationUnavailable();
    }
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
      );
      final code = credential.authorizationCode.trim();
      final idToken = credential.identityToken?.trim();
      if (code.isEmpty || idToken == null || idToken.isEmpty) {
        throw const OAuthAuthorizationUnavailable();
      }
      return OAuthAuthorizationResult.apple(code: code, idToken: idToken);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return null;
      }
      rethrow;
    }
  }
}

class PlatformOAuthAuthorizer implements OAuthAuthorizer {
  PlatformOAuthAuthorizer._(this._appleClient)
    : _googleInitializer = _initializeGoogleSignIn;

  @visibleForTesting
  PlatformOAuthAuthorizer.testing({
    required AppleOAuthClient appleClient,
    GoogleSignInInitializer? googleInitializer,
  }) : _appleClient = appleClient,
       _googleInitializer = googleInitializer ?? _initializeGoogleSignIn;

  static final instance = PlatformOAuthAuthorizer._(
    const NativeAppleOAuthClient(),
  );
  final AppleOAuthClient _appleClient;
  final GoogleSignInInitializer _googleInitializer;
  Future<void>? _initialization;

  Future<void> initialize() {
    return _initialization ??= _googleInitializer(
      clientId: googleIosClientId,
      serverClientId: null,
    );
  }

  @override
  Future<OAuthAuthorizationResult?> authorize(OAuthProvider provider) async {
    if (provider == OAuthProvider.apple) {
      return _appleClient.authorize();
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

Future<void> _initializeGoogleSignIn({
  String? clientId,
  String? serverClientId,
}) {
  return GoogleSignIn.instance.initialize(
    clientId: clientId,
    serverClientId: serverClientId,
  );
}

class OAuthAuthorizationUnavailable implements Exception {
  const OAuthAuthorizationUnavailable();
}
