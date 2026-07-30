import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'fresh app sandbox clears Keychain authentication left by an iOS uninstall',
    () async {
      const storage = SecureAuthStorage();
      const anonymous = AuthSession(
        ownerType: OwnerType.anonymous,
        accessToken: 'anonymous-access',
        refreshToken: 'anonymous-refresh',
        anonymousId: 'anonymous-1',
      );
      const user = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: 'user-1',
      );
      await storage.writeSession(anonymous);
      await storage.writeSession(user);
      final previousDeviceId = await storage.readOrCreateDeviceId();

      await storage.prepareForCurrentInstallation();

      expect(await storage.readSession(), isNull);
      expect(await storage.readPreviousAnonymousSession(), isNull);
      expect(await storage.readOrCreateDeviceId(), isNot(previousDeviceId));
    },
  );

  test(
    'installation marker preserves authentication across app restarts',
    () async {
      const storage = SecureAuthStorage();
      const user = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: 'user-1',
      );
      await storage.prepareForCurrentInstallation();
      await storage.writeSession(user);

      await const SecureAuthStorage().prepareForCurrentInstallation();

      expectSession(await storage.readSession(), user);
    },
  );

  test(
    'first marker rollout preserves an existing installation session',
    () async {
      SharedPreferences.setMockInitialValues({'onboarding.completed': true});
      const storage = SecureAuthStorage();
      const user = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: 'user-1',
      );
      await storage.writeSession(user);

      await storage.prepareForCurrentInstallation();

      expectSession(await storage.readSession(), user);
    },
  );

  test(
    'keeps one installation id because anonymous ownership is device scoped',
    () async {
      const storage = SecureAuthStorage();

      final first = await storage.readOrCreateDeviceId();
      final second = await const SecureAuthStorage().readOrCreateDeviceId();

      expect(second, first);
      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );

  test('restores sessions because login must survive an app restart', () async {
    const storage = SecureAuthStorage();
    const anonymous = AuthSession(
      ownerType: OwnerType.anonymous,
      accessToken: 'anonymous-access',
      refreshToken: 'anonymous-refresh',
      anonymousId: 'anonymous-1',
    );
    const user = AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'user-access',
      refreshToken: 'user-refresh',
      userId: 'user-1',
      email: 'user@example.com',
      loginMethod: LoginMethod.google,
    );

    await storage.writeSession(anonymous);
    await storage.writeSession(user);
    const restartedStorage = SecureAuthStorage();

    expectSession(await restartedStorage.readSession(), user);
    expectSession(
      await restartedStorage.readPreviousAnonymousSession(),
      anonymous,
    );
  });
}

void expectSession(AuthSession? actual, AuthSession expected) {
  expect(actual?.ownerType, expected.ownerType);
  expect(actual?.accessToken, expected.accessToken);
  expect(actual?.refreshToken, expected.refreshToken);
  expect(actual?.anonymousId, expected.anonymousId);
  expect(actual?.userId, expected.userId);
  expect(actual?.email, expected.email);
  expect(actual?.loginMethod, expected.loginMethod);
}
