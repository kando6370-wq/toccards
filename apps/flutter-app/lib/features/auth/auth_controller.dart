import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';
import 'oauth_authorizer.dart';
import 'auth_repository.dart';
import 'auth_storage.dart';

const authAuthorizationFailedMessage = oauthAuthorizationFailedMessage;
const authAccountActionFailedMessage =
    'Unable to complete this action. Please try again later.';
const _googleRedirectUri = 'kando://auth/google';

class AuthActionException implements Exception {
  const AuthActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

final authStorageProvider = Provider<InMemoryAuthStorage>((ref) {
  return InMemoryAuthStorage();
});

final authDioProvider = Provider((ref) {
  final dio = createAuthDio();
  ref.onDispose(dio.close);
  return dio;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return HttpAuthRepository(
    ref.watch(authDioProvider),
    ref.watch(authStorageProvider),
  );
});

final oauthAuthorizerProvider = Provider<OAuthAuthorizer>((ref) {
  return const MockOAuthAuthorizer();
});

final authDeviceIdProvider = Provider<String>((ref) {
  return 'local-device';
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  Completer<void>? _startupCompleter;
  Future<void> _mutationTail = Future<void>.value();
  var _generation = 0;

  AuthRepository get _repository => ref.read(authRepositoryProvider);
  OAuthAuthorizer get _oauthAuthorizer => ref.read(oauthAuthorizerProvider);
  String get _deviceId => ref.read(authDeviceIdProvider);

  Future<void> get startupComplete {
    return _startupCompleter?.future ?? Future<void>.value();
  }

  @override
  AuthState build() {
    final completer = Completer<void>();
    final generation = ++_generation;
    _startupCompleter = completer;
    final startup = _enqueueMutation(() => _loadInitialSession(generation));
    unawaited(
      startup.then(completer.complete).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        completer.completeError(error, stackTrace);
      }),
    );
    return const AuthState.loading();
  }

  Future<void> logout() async {
    _generation++;
    await _enqueueMutation(() async {
      await _repository.clearUserSession();
      await _restorePreviousAnonymousOrCreate();
    });
  }

  Future<void> deleteAccount() async {
    final targetSession = state.session;
    _generation++;
    await _enqueueMutation(() async {
      if (targetSession != null && !identical(state.session, targetSession)) {
        return;
      }

      final session = state.session;
      if (session == null) {
        await _replaceWithAnonymous();
      } else if (session.isAnonymous) {
        await _repository.deleteCurrentAccount(session);
        await _replaceWithAnonymous();
      } else {
        await _repository.deleteCurrentAccount(session);
        await _restorePreviousAnonymousOrCreate();
      }
    });
  }

  Future<void> login({required String email, required String password}) async {
    await _enqueueMutation(() async {
      final session = await _repository.login(email: email, password: password);
      await _repository.persistSession(session);
      state = AuthState.ready(session: session);
    });
  }

  Future<void> continueWithGoogle() {
    return _continueWithOAuth(OAuthProvider.google);
  }

  Future<void> continueWithApple() {
    return _continueWithOAuth(OAuthProvider.apple);
  }

  Future<void> sendRegisterCode(String email) {
    return _repository.sendRegisterCode(email);
  }

  Future<void> verifyRegister({
    required String email,
    required String code,
    required String password,
  }) async {
    await _enqueueMutation(() async {
      final anonymousId = state.session?.isAnonymous == true
          ? state.session?.anonymousId
          : null;
      final session = await _repository.verifyRegister(
        email: email,
        code: code,
        password: password,
        anonymousId: anonymousId,
      );
      await _repository.persistSession(session);
      state = AuthState.ready(session: session);
    });
  }

  Future<void> sendForgotPasswordCode(String email) {
    return _repository.sendForgotPasswordCode(email);
  }

  Future<String> verifyForgotPasswordCode({
    required String email,
    required String code,
  }) {
    return _repository.verifyForgotPasswordCode(email: email, code: code);
  }

  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) {
    return _repository.resetPassword(
      email: email,
      resetToken: resetToken,
      newPassword: newPassword,
    );
  }

  Future<void> _continueWithOAuth(OAuthProvider provider) async {
    final generation = _generation;
    final targetSession = state.session;

    final OAuthAuthorizationResult? authorization;
    try {
      authorization = await _oauthAuthorizer.authorize(provider);
    } on Exception {
      throw const AuthActionException(authAuthorizationFailedMessage);
    }
    if (authorization == null) {
      return;
    }
    final authorizationResult = authorization;

    await _enqueueMutation(() async {
      if (generation != _generation ||
          !identical(state.session, targetSession)) {
        return;
      }

      final anonymousId = targetSession?.isAnonymous == true
          ? targetSession?.anonymousId
          : null;
      final AuthSession session;
      try {
        session = switch (provider) {
          OAuthProvider.google => await _repository.googleCallback(
            code: authorizationResult.code,
            redirectUri: _googleRedirectUri,
            anonymousId: anonymousId,
          ),
          OAuthProvider.apple => await _repository.appleCallback(
            code: authorizationResult.code,
            idToken: authorizationResult.idToken!,
            anonymousId: anonymousId,
          ),
        };
      } on OAuthAuthorizationException {
        throw const AuthActionException(authAuthorizationFailedMessage);
      }
      await _repository.persistSession(session);
      state = AuthState.ready(session: session);
    });
  }

  Future<void> _loadInitialSession(int generation) async {
    final storedSession = await _repository.currentSessionFromStorage();
    final validSession = storedSession == null
        ? null
        : await _repository.validateStoredSession(storedSession);

    if (generation != _generation) {
      return;
    }

    if (validSession != null) {
      state = AuthState.ready(session: validSession);
    } else {
      await _replaceWithAnonymous(expectedGeneration: generation);
    }
  }

  Future<void> _replaceWithAnonymous({int? expectedGeneration}) async {
    final anonymousSession = await _repository.createAnonymousSession(
      _deviceId,
    );
    if (!_isExpectedGeneration(expectedGeneration)) {
      return;
    }

    await _repository.persistSession(anonymousSession);
    if (!_isExpectedGeneration(expectedGeneration)) {
      return;
    }

    state = AuthState.ready(session: anonymousSession);
  }

  Future<void> _restorePreviousAnonymousOrCreate() async {
    final previousAnonymous = await _repository
        .previousAnonymousSessionFromStorage();
    if (previousAnonymous == null) {
      await _replaceWithAnonymous();
      return;
    }

    await _repository.persistSession(previousAnonymous);
    state = AuthState.ready(session: previousAnonymous);
  }

  bool _isExpectedGeneration(int? expectedGeneration) {
    return expectedGeneration == null || expectedGeneration == _generation;
  }

  Future<void> _enqueueMutation(Future<void> Function() mutation) {
    final run = _mutationTail.then((_) => mutation());
    _mutationTail = run.catchError((Object _) {});
    return run;
  }
}
