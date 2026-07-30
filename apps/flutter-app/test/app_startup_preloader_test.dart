import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app_startup_preloader.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';

import 'support/mock_home_repository.dart';
import 'support/mock_collection_repository.dart';
import 'support/mock_search_repository.dart';

void main() {
  test('startup preloader initializes all data-backed main tabs', () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_ReadyAuthController.new),
        homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        collectionRepositoryProvider.overrideWithValue(
          const MockCollectionRepository(),
        ),
        searchRepositoryProvider.overrideWithValue(
          const MockSearchRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(appStartupPreloaderProvider.future);

    expect(container.read(homeControllerProvider).isLoading, isFalse);
    expect(container.read(collectionControllerProvider).isLoading, isFalse);
    expect(container.read(searchControllerProvider).isLoading, isFalse);
  });

  test('startup preloader prioritizes Home before secondary tabs', () async {
    final home = _PendingHomeRepository();
    final search = _CountingSearchRepository();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_ReadyAuthController.new),
        homeRepositoryProvider.overrideWithValue(home),
        collectionRepositoryProvider.overrideWithValue(
          const MockCollectionRepository(),
        ),
        searchRepositoryProvider.overrideWithValue(search),
      ],
    );
    addTearDown(container.dispose);

    final preload = container.read(appStartupPreloaderProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(search.loadCount, 0);
    expect(container.read(homeControllerProvider).isLoading, isTrue);

    home.result.complete(mockHomeDashboard);
    await preload;
    for (var attempt = 0; attempt < 10 && search.loadCount == 0; attempt++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(homeControllerProvider).isLoading, isFalse);
    expect(search.loadCount, 1);
    expect(container.read(collectionControllerProvider).isLoading, isFalse);
    expect(container.read(searchControllerProvider).isLoading, isFalse);
  });

  test(
    'startup preloader loads Home after authentication settles without a manual refresh',
    () async {
      final home = _CountingHomeRepository();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_DelayedAuthController.new),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
          homeRepositoryProvider.overrideWith((ref) {
            final authState = ref.watch(authControllerProvider);
            return authState.isLoading ? null : _DelegatingHomeRepository(home);
          }),
          searchRepositoryProvider.overrideWithValue(
            const MockSearchRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appStartupPreloaderProvider);
      expect(container.read(homeControllerProvider).isLoading, isTrue);
      expect(home.loadCount, 0);

      final authController =
          container.read(authControllerProvider.notifier)
              as _DelayedAuthController;
      authController.completeAuthentication();
      for (var attempt = 0; attempt < 10 && home.loadCount == 0; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(home.loadCount, 1);
      expect(container.read(homeControllerProvider).isLoading, isFalse);
      expect(
        container.read(homeControllerProvider).totalAmountText,
        r'$12,450.80',
      );

      authController.completeUserAuthentication();
      for (var attempt = 0; attempt < 10 && home.loadCount == 1; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(home.loadCount, 2);
    },
  );

  testWidgets(
    'startup timeout enters without cancelling Home and then warms secondary tabs',
    (tester) async {
      final home = _PendingHomeRepository();
      final search = _CountingSearchRepository();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          homeRepositoryProvider.overrideWithValue(home),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
          searchRepositoryProvider.overrideWithValue(search),
        ],
      );
      addTearDown(container.dispose);

      final preload = container.read(appStartupPreloaderProvider.future);
      await tester.pump(
        appStartupPreloadTimeout - const Duration(milliseconds: 1),
      );
      expect(search.loadCount, 0);

      await tester.pump(const Duration(milliseconds: 1));
      await preload;
      await tester.pump();

      expect(container.read(homeControllerProvider).isLoading, isTrue);
      expect(search.loadCount, 1);

      home.result.complete(mockHomeDashboard);
      await tester.pump();
      expect(container.read(homeControllerProvider).isLoading, isFalse);
    },
  );
}

class _PendingHomeRepository implements HomeRepository {
  final result = Completer<HomeDashboard>();

  @override
  Future<HomeDashboard> loadDashboard() => result.future;
}

class _CountingSearchRepository extends MockSearchRepository {
  int loadCount = 0;

  @override
  Future<SearchCatalog> loadCatalog() {
    loadCount++;
    return super.loadCatalog();
  }
}

class _CountingHomeRepository extends MockHomeRepository {
  var loadCount = 0;

  @override
  HomeDashboard loadDashboard() {
    loadCount++;
    return super.loadDashboard();
  }
}

class _DelegatingHomeRepository implements HomeRepository {
  const _DelegatingHomeRepository(this.delegate);

  final HomeRepository delegate;

  @override
  FutureOr<HomeDashboard> loadDashboard() => delegate.loadDashboard();
}

class _DelayedAuthController extends AuthController {
  @override
  AuthState build() => const AuthState.loading();

  void completeAuthentication() {
    state = const AuthState.ready(
      session: AuthSession(
        ownerType: OwnerType.anonymous,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        anonymousId: 'anonymous-id',
      ),
    );
  }

  void completeUserAuthentication() {
    state = const AuthState.ready(
      session: AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access-token',
        refreshToken: 'user-refresh-token',
        userId: 'user-id',
      ),
    );
  }
}

class _ReadyAuthController extends AuthController {
  @override
  AuthState build() {
    return const AuthState.ready(
      session: AuthSession(
        ownerType: OwnerType.anonymous,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        anonymousId: 'anonymous-id',
      ),
    );
  }
}
