import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';
import 'oauth_authorizer.dart';
import 'auth_repository.dart';
import 'auth_session_interceptor.dart';
import 'auth_storage.dart';
import '../../shared/api/api_request_log.dart';
import '../../shared/debug/app_debug_overlay.dart';

const authAuthorizationFailedMessage = oauthAuthorizationFailedMessage;
const authAccountActionFailedMessage =
    'Unable to complete this action. Please try again later.';

enum EmailAuthDestination { login, registerCode }

class AuthActionException implements Exception {
  const AuthActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

final authStorageProvider = Provider<AuthStorage>((ref) {
  return const SecureAuthStorage();
});

final authDioProvider = Provider((ref) {
  final dio = createAuthDio();
  dio.interceptors.add(
    ApiRequestTimingInterceptor(ref.read(apiRequestLogProvider.notifier)),
  );
  addAppDebugHttpLogging(dio);
  dio.interceptors.add(
    AuthSessionInterceptor(dio: dio, storage: ref.watch(authStorageProvider)),
  );
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
  return PlatformOAuthAuthorizer.instance;
});

final authDeviceIdProvider = Provider<String?>((ref) => null);

final authStartupRetryDelaysProvider = Provider<List<Duration>>((ref) {
  return const [Duration(seconds: 1), Duration(seconds: 3)];
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
  AuthStorage get _storage => ref.read(authStorageProvider);

  Future<void> get startupComplete {
    return _startupCompleter?.future ?? Future<void>.value();
  }

  @override
  AuthState build() {
    _startSessionLoad();
    return const AuthState.loading();
  }

  Future<void> retryStartup() {
    state = const AuthState.loading();
    _startSessionLoad();
    return startupComplete;
  }

  void _startSessionLoad() {
    final completer = Completer<void>();
    final generation = ++_generation;
    _startupCompleter = completer;
    final startup = _enqueueMutation(
      () => _loadInitialSessionWithRetry(generation),
    );
    unawaited(
      startup.then(completer.complete).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (generation == _generation) {
          state = const AuthState.failure();
        }
        completer.complete();
      }),
    );
  }

  Future<void> _loadInitialSessionWithRetry(int generation) async {
    final retryDelays = ref.read(authStartupRetryDelaysProvider);
    for (var attempt = 0; ; attempt += 1) {
      try {
        await _loadInitialSession(generation);
        return;
      } on AuthNetworkException {
        if (generation != _generation) return;
        if (attempt >= retryDelays.length) rethrow;
        await Future<void>.delayed(retryDelays[attempt]);
        if (generation != _generation) return;
      }
    }
  }

  Future<void> logout() async {
    _generation++;
    await _enqueueMutation(() async {
      final anonymousSession = await _validatedPreviousAnonymousOrCreate();
      await _repository.clearUserSession();
      await _repository.persistSession(anonymousSession);
      state = AuthState.ready(session: anonymousSession);
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
        final anonymousSession = await _validatedPreviousAnonymousOrCreate();
        await _repository.deleteCurrentAccount(session);
        await _repository.persistSession(anonymousSession);
        state = AuthState.ready(session: anonymousSession);
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

  Future<void> continueWithGoogle({void Function()? onCallbackStart}) {
    return _continueWithOAuth(
      OAuthProvider.google,
      onCallbackStart: onCallbackStart,
    );
  }

  Future<void> continueWithApple({void Function()? onCallbackStart}) {
    return _continueWithOAuth(
      OAuthProvider.apple,
      onCallbackStart: onCallbackStart,
    );
  }

  Future<void> sendRegisterCode(String email) {
    return _repository.sendRegisterCode(email);
  }

  Future<EmailAuthDestination> beginEmailAuth(String email) async {
    try {
      await _repository.sendRegisterCode(email);
      return EmailAuthDestination.registerCode;
    } on AuthApiException catch (error) {
      if (error.code == 'CONFLICT') {
        return EmailAuthDestination.login;
      }
      rethrow;
    }
  }

  Future<void> verifyRegisterCode({
    required String email,
    required String code,
  }) {
    return _repository.verifyRegisterCode(email: email, code: code);
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

  Future<void> _continueWithOAuth(
    OAuthProvider provider, {
    void Function()? onCallbackStart,
  }) async {
    final generation = _generation;
    final targetSession = state.session;
    final OAuthAuthorizationResult? authorization;
    try {
      authorization = await _oauthAuthorizer.authorize(provider);
    } catch (_) {
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
        onCallbackStart?.call();
        session = switch (provider) {
          OAuthProvider.google => await _repository.googleCallback(
            idToken: authorizationResult.code,
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
    final hasUsableAccessToken =
        storedSession != null && _hasUsableAccessToken(storedSession);
    final restoredAnonymousSession =
        hasUsableAccessToken &&
        storedSession.isAnonymous &&
        await _matchesPreviousAnonymousSession(storedSession);
    if (storedSession != null &&
        hasUsableAccessToken &&
        !restoredAnonymousSession) {
      if (generation == _generation) {
        state = AuthState.ready(session: storedSession);
      }
      return;
    }

    AuthSession? validSession;
    try {
      validSession = storedSession == null
          ? null
          : await _repository.validateStoredSession(storedSession);
    } on AuthNetworkException {
      if (generation == _generation && storedSession != null) {
        state = AuthState.ready(session: storedSession);
      }
      return;
    }

    if (generation != _generation) {
      return;
    }

    if (validSession != null) {
      state = AuthState.ready(session: validSession);
    } else {
      if (restoredAnonymousSession) {
        await _repository.clearAnonymousSession();
      }
      await _replaceWithAnonymous(expectedGeneration: generation);
    }
  }

  Future<bool> _matchesPreviousAnonymousSession(AuthSession session) async {
    final previousAnonymous = await _repository
        .previousAnonymousSessionFromStorage();
    return previousAnonymous?.refreshToken == session.refreshToken;
  }

  Future<void> _replaceWithAnonymous({int? expectedGeneration}) async {
    final anonymousSession = await _createAnonymousSession();
    if (!_isExpectedGeneration(expectedGeneration)) {
      return;
    }

    await _repository.persistSession(anonymousSession);
    if (!_isExpectedGeneration(expectedGeneration)) {
      return;
    }

    state = AuthState.ready(session: anonymousSession);
  }

  Future<AuthSession> _validatedPreviousAnonymousOrCreate() async {
    final previousAnonymous = await _repository
        .previousAnonymousSessionFromStorage();
    if (previousAnonymous != null) {
      final validated = await _repository.validateStoredSession(
        previousAnonymous,
      );
      if (validated != null) return validated;
      await _repository.clearAnonymousSession();
    }

    return _createAnonymousSession();
  }

  Future<AuthSession> _createAnonymousSession() async {
    final deviceId =
        ref.read(authDeviceIdProvider) ?? await _storage.readOrCreateDeviceId();
    return _repository.createAnonymousSession(deviceId);
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

bool _hasUsableAccessToken(AuthSession session, {DateTime? now}) {
  final parts = session.accessToken.split('.');
  if (parts.length != 3) return false;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map || payload['exp'] is! num) return false;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      (payload['exp'] as num).toInt() * 1000,
      isUtc: true,
    );
    return expiresAt.isAfter(
      (now ?? DateTime.now()).toUtc().add(const Duration(seconds: 30)),
    );
  } on FormatException {
    return false;
  } on RangeError {
    return false;
  }
}
