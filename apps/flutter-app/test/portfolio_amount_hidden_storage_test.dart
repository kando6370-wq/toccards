import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('amount visibility survives a cold-start storage instance', () async {
    SharedPreferences.setMockInitialValues({});

    const firstLaunch = PreferencesPortfolioAmountHiddenStorage();
    expect(await firstLaunch.readAmountHidden(), isFalse);

    await firstLaunch.writeAmountHidden(true);

    const restartedApp = PreferencesPortfolioAmountHiddenStorage();
    expect(await restartedApp.readAmountHidden(), isTrue);
  });

  test('amount visibility is isolated by data space', () async {
    SharedPreferences.setMockInitialValues({});
    const storage = PreferencesPortfolioAmountHiddenStorage();

    await storage.writeAmountHiddenForScope('ios-space', true);

    expect(await storage.readAmountHiddenForScope('ios-space'), isTrue);
    expect(await storage.readAmountHiddenForScope('android-space'), isFalse);
  });

  test(
    'legacy iOS visibility follows the owner when scope is restored',
    () async {
      SharedPreferences.setMockInitialValues({
        PreferencesPortfolioAmountHiddenStorage.storageKey: true,
      });
      final auth = _StaticAuthController(_legacyIosSession('ios-owner'));
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => auth),
          appCommercialPolicyProvider.overrideWithValue(
            const AppCommercialPolicy(isAndroidFreeLaunch: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(portfolioAmountHiddenProvider);
      await pumpEventQueue();
      expect(container.read(portfolioAmountHiddenProvider), isTrue);

      auth.replace(_iosSession('ios-owner', 'ios-owner'));
      await pumpEventQueue();
      expect(container.read(portfolioAmountHiddenProvider), isTrue);

      auth.replace(_iosSession('other-owner', 'other-owner'));
      await pumpEventQueue();
      expect(container.read(portfolioAmountHiddenProvider), isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey(
          PreferencesPortfolioAmountHiddenStorage.storageKey,
        ),
        isFalse,
      );
    },
  );

  test('Android never inherits the legacy global visibility', () async {
    SharedPreferences.setMockInitialValues({
      PreferencesPortfolioAmountHiddenStorage.storageKey: true,
    });
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _StaticAuthController(_androidSession('android-space')),
        ),
        appCommercialPolicyProvider.overrideWithValue(
          const AppCommercialPolicy(isAndroidFreeLaunch: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(portfolioAmountHiddenProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(portfolioAmountHiddenProvider), isFalse);
  });

  test('legacy iOS visibility does not overwrite a scoped value', () async {
    SharedPreferences.setMockInitialValues({
      PreferencesPortfolioAmountHiddenStorage.storageKey: true,
      '${PreferencesPortfolioAmountHiddenStorage.storageKey}.ios-owner': false,
    });
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _StaticAuthController(_legacyIosSession('ios-owner')),
        ),
        appCommercialPolicyProvider.overrideWithValue(
          const AppCommercialPolicy(isAndroidFreeLaunch: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(portfolioAmountHiddenProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(portfolioAmountHiddenProvider), isFalse);
  });

  test('rapid legacy iOS scope changes cannot copy the global value', () async {
    final storage = _DeferredLegacyMigrationStorage();
    final auth = _StaticAuthController(_legacyIosSession('owner-a'));
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        appCommercialPolicyProvider.overrideWithValue(
          const AppCommercialPolicy(isAndroidFreeLaunch: false),
        ),
        portfolioAmountHiddenStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    container.read(portfolioAmountHiddenProvider);
    await pumpEventQueue();
    expect(storage.migrationCalls, ['owner-a']);

    auth.replace(_legacyIosSession('owner-b'));
    container.read(portfolioAmountHiddenProvider);
    await pumpEventQueue();
    expect(storage.migrationCalls, ['owner-a']);

    storage.firstMigration.complete();
    await storage.secondMigrationStarted.future;
    await pumpEventQueue();

    expect(storage.migrationCalls, ['owner-a', 'owner-b']);
    expect(storage.scopedValues, {'owner-a': true});
    expect(container.read(portfolioAmountHiddenProvider), isFalse);
  });

  test('a user selection wins over an in-flight legacy migration', () async {
    final storage = _DeferredFalseLegacyMigrationStorage();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _StaticAuthController(_legacyIosSession('ios-owner')),
        ),
        appCommercialPolicyProvider.overrideWithValue(
          const AppCommercialPolicy(isAndroidFreeLaunch: false),
        ),
        portfolioAmountHiddenStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    container.read(portfolioAmountHiddenProvider);
    await storage.migrationStarted.future;
    final selection = container
        .read(portfolioAmountHiddenProvider.notifier)
        .select(true);
    expect(container.read(portfolioAmountHiddenProvider), isTrue);
    expect(storage.scopedValues, isEmpty);

    storage.releaseMigration.complete();
    expect(await selection, isTrue);

    expect(storage.scopedValues['ios-owner'], isTrue);
    expect(await storage.readAmountHiddenForScope('ios-owner'), isTrue);
  });

  test(
    'a delayed scoped read cannot overwrite a newer user selection',
    () async {
      final storage = _DeferredScopedAmountStorage();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _StaticAuthController(_androidSession('space-a')),
          ),
          portfolioAmountHiddenStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      container.read(portfolioAmountHiddenProvider);
      await Future<void>.delayed(Duration.zero);
      final selection = container
          .read(portfolioAmountHiddenProvider.notifier)
          .select(true);
      storage.reads.single.complete(false);
      await Future.wait([selection, Future<void>.delayed(Duration.zero)]);

      expect(container.read(portfolioAmountHiddenProvider), isTrue);
    },
  );

  test('selected folder resets when the data space changes', () {
    final auth = _StaticAuthController(_androidSession('space-a'));
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(() => auth)],
    );
    addTearDown(container.dispose);

    container.read(selectedPortfolioFolderProvider.notifier).select('folder-a');
    expect(container.read(selectedPortfolioFolderProvider), 'folder-a');

    auth.replace(_androidSession('space-b'));

    expect(container.read(selectedPortfolioFolderProvider), isNull);
  });
}

AuthSession _androidSession(String dataSpaceId) => AuthSession(
  ownerType: OwnerType.user,
  accessToken: 'access-$dataSpaceId',
  refreshToken: 'refresh-$dataSpaceId',
  userId: 'shared-user',
  platform: AppPlatform.android,
  dataSpaceId: dataSpaceId,
);

AuthSession _legacyIosSession(String userId) => AuthSession(
  ownerType: OwnerType.user,
  accessToken: 'access-$userId',
  refreshToken: 'refresh-$userId',
  userId: userId,
  platform: AppPlatform.ios,
);

AuthSession _iosSession(String userId, String dataSpaceId) => AuthSession(
  ownerType: OwnerType.user,
  accessToken: 'access-$userId',
  refreshToken: 'refresh-$userId',
  userId: userId,
  platform: AppPlatform.ios,
  dataSpaceId: dataSpaceId,
);

class _StaticAuthController extends AuthController {
  _StaticAuthController(this.initialSession);

  final AuthSession initialSession;

  @override
  AuthState build() => AuthState.ready(session: initialSession);

  void replace(AuthSession session) {
    state = AuthState.ready(session: session);
  }
}

class _DeferredScopedAmountStorage
    implements ScopedPortfolioAmountHiddenStorage {
  final reads = <Completer<bool>>[];

  @override
  Future<bool> readAmountHidden() async => false;

  @override
  Future<bool> readAmountHiddenForScope(String scope) {
    final completer = Completer<bool>();
    reads.add(completer);
    return completer.future;
  }

  @override
  Future<void> writeAmountHidden(bool amountHidden) async {}

  @override
  Future<void> writeAmountHiddenForScope(
    String scope,
    bool amountHidden,
  ) async {}
}

class _DeferredLegacyMigrationStorage
    extends PreferencesPortfolioAmountHiddenStorage {
  final firstMigration = Completer<void>();
  final secondMigrationStarted = Completer<void>();
  final migrationCalls = <String>[];
  final scopedValues = <String, bool>{};
  var _legacyAvailable = true;

  @override
  Future<bool> migrateLegacyAmountHiddenToScope(String scope) async {
    migrationCalls.add(scope);
    if (migrationCalls.length == 1) await firstMigration.future;
    if (migrationCalls.length == 2) secondMigrationStarted.complete();
    if (!_legacyAvailable) return scopedValues[scope] ?? false;
    _legacyAvailable = false;
    scopedValues[scope] = true;
    return true;
  }

  @override
  Future<bool> readAmountHiddenForScope(String scope) async {
    return scopedValues[scope] ?? false;
  }
}

class _DeferredFalseLegacyMigrationStorage
    extends PreferencesPortfolioAmountHiddenStorage {
  final migrationStarted = Completer<void>();
  final releaseMigration = Completer<void>();
  final scopedValues = <String, bool>{};

  @override
  Future<bool> migrateLegacyAmountHiddenToScope(String scope) async {
    migrationStarted.complete();
    await releaseMigration.future;
    scopedValues[scope] = false;
    return false;
  }

  @override
  Future<bool> readAmountHiddenForScope(String scope) async {
    return scopedValues[scope] ?? false;
  }

  @override
  Future<void> writeAmountHiddenForScope(
    String scope,
    bool amountHidden,
  ) async {
    scopedValues[scope] = amountHidden;
  }
}
