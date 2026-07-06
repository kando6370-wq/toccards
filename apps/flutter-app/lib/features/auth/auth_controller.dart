import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_models.dart';
import 'auth_repository.dart';
import 'auth_storage.dart';

final authStorageProvider = Provider<InMemoryAuthStorage>((ref) {
  return InMemoryAuthStorage();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return LocalPlaceholderAuthRepository(ref.watch(authStorageProvider));
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
      if (session?.isAnonymous ?? false) {
        await _repository.clearAnonymousSession();
        await _replaceWithAnonymous();
      } else {
        await _repository.clearUserSession();
        await _restorePreviousAnonymousOrCreate();
      }
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
