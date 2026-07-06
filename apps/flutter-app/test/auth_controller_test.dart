import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/auth_storage.dart';

void main() {
  const deviceId = 'test-device';

  test(
    'valid stored user session stays user so migration is not triggered',
    () async {
      final storedUser = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: 'user-1',
        email: 'person@example.com',
      );
      final repository = _FakeAuthRepository(
        storedSession: storedUser,
        validatedSession: storedUser,
      );

      final state = await _startAuth(repository, deviceId);

      expect(state.session, same(storedUser));
      expect(state.session!.ownerType, OwnerType.user);
      expect(repository.validatedSessions, [same(storedUser)]);
      expect(repository.createdDeviceIds, isEmpty);
      expect(repository.persistedSessions, isEmpty);
    },
  );

  test(
    'invalid stored user session creates and persists an anonymous session',
    () async {
      final staleUser = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'stale-access',
        refreshToken: 'stale-refresh',
        userId: 'user-1',
      );
      final anonymous = _anonymousSession('anon-new');
      final repository = _FakeAuthRepository(
        storedSession: staleUser,
        validatedSession: null,
        createdAnonymousSession: anonymous,
      );

      final state = await _startAuth(repository, deviceId);

      expect(state.session, same(anonymous));
      expect(state.session!.ownerType, OwnerType.anonymous);
      expect(repository.validatedSessions, [same(staleUser)]);
      expect(repository.createdDeviceIds, [deviceId]);
      expect(repository.persistedSessions, [same(anonymous)]);
    },
  );

  test(
    'missing stored session creates and persists an anonymous session',
    () async {
      final anonymous = _anonymousSession('anon-new');
      final repository = _FakeAuthRepository(
        createdAnonymousSession: anonymous,
      );

      final state = await _startAuth(repository, deviceId);

      expect(state.session, same(anonymous));
      expect(state.session!.ownerType, OwnerType.anonymous);
      expect(repository.validatedSessions, isEmpty);
      expect(repository.createdDeviceIds, [deviceId]);
      expect(repository.persistedSessions, [same(anonymous)]);
    },
  );

  test(
    'valid stored anonymous session remains anonymous for guest continuity',
    () async {
      final storedAnonymous = _anonymousSession('anon-existing');
      final repository = _FakeAuthRepository(
        storedSession: storedAnonymous,
        validatedSession: storedAnonymous,
      );

      final state = await _startAuth(repository, deviceId);

      expect(state.session, same(storedAnonymous));
      expect(state.session!.ownerType, OwnerType.anonymous);
      expect(state.session!.anonymousId, 'anon-existing');
      expect(repository.validatedSessions, [same(storedAnonymous)]);
      expect(repository.createdDeviceIds, isEmpty);
      expect(repository.persistedSessions, isEmpty);
    },
  );

  test(
    'user logout clears user session and persists a new anonymous session',
    () async {
      final storedUser = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: 'user-1',
      );
      final anonymous = _anonymousSession('anon-after-logout');
      final repository = _FakeAuthRepository(
        storedSession: storedUser,
        validatedSession: storedUser,
        createdAnonymousSessions: [anonymous],
      );
      final container = _createContainer(repository, deviceId);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      await container.read(authControllerProvider.notifier).logout();
      final state = container.read(authControllerProvider);

      expect(repository.clearedUserSessions, 1);
      expect(repository.clearedAnonymousSessions, 0);
      expect(repository.createdDeviceIds, [deviceId]);
      expect(repository.persistedSessions, [same(anonymous)]);
      expect(state.session, same(anonymous));
    },
  );

  test(
    'user logout restores previous anonymous session so guest continuity survives sign in',
    () async {
      final storedUser = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: 'user-1',
      );
      final previousAnonymous = _anonymousSession('anon-before-sign-in');
      final repository = _FakeAuthRepository(
        storedSession: storedUser,
        validatedSession: storedUser,
        previousAnonymousSession: previousAnonymous,
      );
      final container = _createContainer(repository, deviceId);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      await container.read(authControllerProvider.notifier).logout();
      final state = container.read(authControllerProvider);

      expect(repository.clearedUserSessions, 1);
      expect(repository.previousAnonymousReads, 1);
      expect(repository.createdDeviceIds, isEmpty);
      expect(repository.persistedSessions, [same(previousAnonymous)]);
      expect(state.session, same(previousAnonymous));
    },
  );

  test(
    'guest delete clears anonymous session and persists a fresh anonymous session',
    () async {
      final storedAnonymous = _anonymousSession('anon-existing');
      final freshAnonymous = _anonymousSession('anon-after-delete');
      final repository = _FakeAuthRepository(
        storedSession: storedAnonymous,
        validatedSession: storedAnonymous,
        createdAnonymousSessions: [freshAnonymous],
      );
      final container = _createContainer(repository, deviceId);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      await container.read(authControllerProvider.notifier).deleteAccount();
      final state = container.read(authControllerProvider);

      expect(repository.clearedUserSessions, 0);
      expect(repository.clearedAnonymousSessions, 1);
      expect(repository.createdDeviceIds, [deviceId]);
      expect(repository.persistedSessions, [same(freshAnonymous)]);
      expect(state.session, same(freshAnonymous));
    },
  );

  test(
    'guest delete removes deleted anonymous from real previous storage cache',
    () async {
      final storage = InMemoryAuthStorage();
      final repository = LocalPlaceholderAuthRepository(storage);
      final anonymousA = _anonymousSession('anon-a');
      final user = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: 'user-1',
      );
      await repository.persistSession(anonymousA);
      await repository.persistSession(user);
      final container = _createContainer(repository, deviceId);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      await container.read(authControllerProvider.notifier).logout();
      expect(container.read(authControllerProvider).session, same(anonymousA));

      await container.read(authControllerProvider.notifier).deleteAccount();
      final afterDelete = container.read(authControllerProvider).session!;
      expect(afterDelete.isAnonymous, isTrue);
      expect(afterDelete.anonymousId, isNot(anonymousA.anonymousId));

      await storage.clearAnonymousSession();
      await repository.persistSession(user);
      final laterContainer = _createContainer(repository, deviceId);
      addTearDown(laterContainer.dispose);
      await laterContainer
          .read(authControllerProvider.notifier)
          .startupComplete;

      await laterContainer.read(authControllerProvider.notifier).logout();
      final laterAnonymous = laterContainer
          .read(authControllerProvider)
          .session!;
      expect(laterAnonymous.isAnonymous, isTrue);
      expect(laterAnonymous.anonymousId, isNot(anonymousA.anonymousId));
    },
  );

  test(
    'duplicate guest delete only deletes the original anonymous session once',
    () async {
      final storedAnonymous = _anonymousSession('anon-existing');
      final firstFreshAnonymous = _anonymousSession('anon-after-delete-1');
      final secondFreshAnonymous = _anonymousSession('anon-after-delete-2');
      final repository = _FakeAuthRepository(
        storedSession: storedAnonymous,
        validatedSession: storedAnonymous,
        createdAnonymousSessions: [firstFreshAnonymous, secondFreshAnonymous],
      );
      final container = _createContainer(repository, deviceId);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      final controller = container.read(authControllerProvider.notifier);
      await Future.wait([
        controller.deleteAccount(),
        controller.deleteAccount(),
      ]);
      final state = container.read(authControllerProvider);

      expect(repository.clearedAnonymousSessions, 1);
      expect(repository.persistedSessions, [same(firstFreshAnonymous)]);
      expect(state.session, same(firstFreshAnonymous));
    },
  );

  for (final actionName in ['logout', 'delete']) {
    test(
      '$actionName during startup prevents the stored user session from replacing anonymous state',
      () async {
        final storedUser = AuthSession(
          ownerType: OwnerType.user,
          accessToken: 'user-access',
          refreshToken: 'user-refresh',
          userId: 'user-1',
        );
        final actionAnonymous = _anonymousSession('anon-from-action');
        final validation = Completer<AuthSession?>();
        final repository = _FakeAuthRepository(
          storedSession: storedUser,
          validationCompleter: validation,
          createdAnonymousSessions: [actionAnonymous],
        );
        final container = _createContainer(repository, deviceId);
        addTearDown(container.dispose);
        expect(container.read(authControllerProvider).isLoading, isTrue);

        final controller = container.read(authControllerProvider.notifier);
        final action = actionName == 'logout'
            ? controller.logout()
            : controller.deleteAccount();
        await Future<void>.delayed(Duration.zero);
        expect(repository.createdDeviceIds, isEmpty);

        validation.complete(storedUser);
        await action;
        await controller.startupComplete;
        final state = container.read(authControllerProvider);

        expect(repository.validatedSessions, [same(storedUser)]);
        expect(repository.persistedSessions, [same(actionAnonymous)]);
        expect(state.session, same(actionAnonymous));
        expect(state.session!.ownerType, OwnerType.anonymous);
      },
    );
  }

  test(
    'logout during startup anonymous fallback persist waits and then replaces startup state',
    () async {
      final startupAnonymous = _anonymousSession('anon-from-startup');
      final actionAnonymous = _anonymousSession('anon-from-logout');
      final startupPersist = Completer<void>();
      final repository = _FakeAuthRepository(
        validatedSession: null,
        createdAnonymousSessions: [startupAnonymous, actionAnonymous],
        persistResults: [startupPersist.future, Future<void>.value()],
      );
      final container = _createContainer(repository, deviceId);
      addTearDown(container.dispose);
      expect(container.read(authControllerProvider).isLoading, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(repository.createdDeviceIds, [deviceId]);
      expect(repository.persistedSessions, [same(startupAnonymous)]);

      final controller = container.read(authControllerProvider.notifier);
      final logout = controller.logout();
      await Future<void>.delayed(Duration.zero);
      expect(repository.createdDeviceIds, [deviceId]);
      expect(container.read(authControllerProvider).isLoading, isTrue);

      startupPersist.complete();
      await logout;
      await controller.startupComplete;
      final state = container.read(authControllerProvider);

      expect(repository.createdDeviceIds, [deviceId, deviceId]);
      expect(repository.persistedSessions, [
        same(startupAnonymous),
        same(actionAnonymous),
      ]);
      expect(state.session, same(actionAnonymous));
      expect(state.session, isNot(same(startupAnonymous)));
    },
  );
}

Future<AuthState> _startAuth(AuthRepository repository, String deviceId) async {
  final container = _createContainer(repository, deviceId);
  addTearDown(container.dispose);

  expect(container.read(authControllerProvider).isLoading, isTrue);
  await container.read(authControllerProvider.notifier).startupComplete;
  return container.read(authControllerProvider);
}

ProviderContainer _createContainer(AuthRepository repository, String deviceId) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      authDeviceIdProvider.overrideWithValue(deviceId),
    ],
  );
}

AuthSession _anonymousSession(String anonymousId) {
  return AuthSession(
    ownerType: OwnerType.anonymous,
    accessToken: '$anonymousId-access',
    refreshToken: '$anonymousId-refresh',
    anonymousId: anonymousId,
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.storedSession,
    this.validatedSession,
    this.validationCompleter,
    this.previousAnonymousSession,
    AuthSession? createdAnonymousSession,
    List<AuthSession>? createdAnonymousSessions,
    List<Future<AuthSession>>? createAnonymousResults,
    List<Future<void>>? persistResults,
  }) : _createAnonymousResults = [
         ...?createAnonymousResults,
         ...?createdAnonymousSessions?.map(Future<AuthSession>.value),
         if (createdAnonymousSession != null)
           Future<AuthSession>.value(createdAnonymousSession),
         if (createdAnonymousSession == null &&
             createAnonymousResults == null &&
             (createdAnonymousSessions == null ||
                 createdAnonymousSessions.isEmpty))
           Future<AuthSession>.value(_anonymousSession('anon-default')),
       ],
       _persistResults = [...?persistResults];

  final AuthSession? storedSession;
  final AuthSession? validatedSession;
  final Completer<AuthSession?>? validationCompleter;
  final AuthSession? previousAnonymousSession;
  final List<Future<AuthSession>> _createAnonymousResults;
  final List<Future<void>> _persistResults;

  final List<AuthSession> validatedSessions = [];
  final List<String> createdDeviceIds = [];
  final List<AuthSession> persistedSessions = [];
  var clearedUserSessions = 0;
  var clearedAnonymousSessions = 0;
  var previousAnonymousReads = 0;

  @override
  Future<AuthSession?> currentSessionFromStorage() async => storedSession;

  @override
  Future<AuthSession> createAnonymousSession(String deviceId) async {
    createdDeviceIds.add(deviceId);
    return _createAnonymousResults.removeAt(0);
  }

  @override
  Future<AuthSession?> validateStoredSession(AuthSession session) async {
    validatedSessions.add(session);
    if (validationCompleter != null) {
      return validationCompleter!.future;
    }
    return validatedSession;
  }

  @override
  Future<AuthSession?> previousAnonymousSessionFromStorage() async {
    previousAnonymousReads++;
    return previousAnonymousSession;
  }

  @override
  Future<void> persistSession(AuthSession session) async {
    persistedSessions.add(session);
    if (_persistResults.isNotEmpty) {
      await _persistResults.removeAt(0);
    }
  }

  @override
  Future<void> clearUserSession() async {
    clearedUserSessions++;
  }

  @override
  Future<void> clearAnonymousSession() async {
    clearedAnonymousSessions++;
  }

  @override
  Future<void> sendRegisterCode(String email) async {}

  @override
  Future<AuthSession> verifyRegister({
    required String email,
    required String code,
    required String password,
    String? anonymousId,
  }) async {
    return AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'user-access',
      refreshToken: 'user-refresh',
      userId: 'user-1',
      email: email,
    );
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    return AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'user-access',
      refreshToken: 'user-refresh',
      userId: 'user-1',
      email: email,
    );
  }

  @override
  Future<void> sendForgotPasswordCode(String email) async {}

  @override
  Future<String> verifyForgotPasswordCode({
    required String email,
    required String code,
  }) async {
    return 'reset-token';
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {}
}
