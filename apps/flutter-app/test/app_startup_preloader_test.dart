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

  test(
    'startup preloader warms only the first 20 Search card images',
    () async {
      final preloadedUrls = <String>[];
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
          searchRepositoryProvider.overrideWithValue(
            _SearchImageCatalogRepository(cardCount: 25),
          ),
          networkImagePreloaderProvider.overrideWithValue((imageUrls) async {
            preloadedUrls.addAll(imageUrls);
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appStartupPreloaderProvider.future);
      await container.read(searchControllerProvider.notifier).loadComplete;
      await Future<void>.delayed(Duration.zero);

      expect(preloadedUrls, [
        for (var index = 0; index < searchImagePreloadLimit; index++)
          'https://img.example/card-$index.jpg',
      ]);
      expect(preloadedUrls, isNot(contains('https://img.example/card-20.jpg')));
    },
  );

  test(
    'startup preloader skips image warming without Home or Search network images',
    () async {
      var preloadCalls = 0;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
          searchRepositoryProvider.overrideWithValue(
            _SearchImageCatalogRepository(cardCount: 0),
          ),
          networkImagePreloaderProvider.overrideWithValue((_) async {
            preloadCalls++;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appStartupPreloaderProvider.future);
      await container.read(searchControllerProvider.notifier).loadComplete;
      await Future<void>.delayed(Duration.zero);

      expect(preloadCalls, 0);
    },
  );

  test(
    'startup preloader warms visible Home Most Valuable and Trending images',
    () async {
      final preloadedBatches = <List<String>>[];
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          homeRepositoryProvider.overrideWithValue(
            const _HomeImageRepository(),
          ),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
          searchRepositoryProvider.overrideWithValue(
            const MockSearchRepository(),
          ),
          networkImagePreloaderProvider.overrideWithValue((imageUrls) async {
            preloadedBatches.add(imageUrls);
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appStartupPreloaderProvider.future);
      await container
          .read(homeControllerProvider.notifier)
          .trendingLoadComplete;
      await Future<void>.delayed(Duration.zero);

      expect(preloadedBatches.expand((batch) => batch), [
        'https://img.example/home-most-valuable-1.jpg',
        'https://img.example/home-most-valuable-2.jpg',
        'https://img.example/home-trending-1.jpg',
        'https://img.example/home-trending-2.jpg',
      ]);
      expect(
        preloadedBatches.expand((batch) => batch),
        isNot(contains('https://img.example/other-folder.jpg')),
      );
    },
  );

  test('Home image warming never delays startup completion', () async {
    final imagePreload = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_ReadyAuthController.new),
        homeRepositoryProvider.overrideWithValue(const _HomeImageRepository()),
        collectionRepositoryProvider.overrideWithValue(
          const MockCollectionRepository(),
        ),
        searchRepositoryProvider.overrideWithValue(
          const MockSearchRepository(),
        ),
        networkImagePreloaderProvider.overrideWithValue(
          (_) => imagePreload.future,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(appStartupPreloaderProvider.future);
    expect(imagePreload.isCompleted, isFalse);

    imagePreload.complete();
  });
}

class _HomeImageRepository implements ProgressiveHomeRepository {
  const _HomeImageRepository();

  @override
  Future<HomeDashboard> loadCoreDashboard() async {
    return HomeDashboard(
      folders: mockHomeDashboard.folders,
      portfoliosByFolderId: mockHomeDashboard.portfoliosByFolderId,
      mostValuableByFolderId: const {
        'main': HomeCardHighlight(
          title: 'Home Card 1',
          subtitle: 'Set',
          priceUsd: 10,
          previousPriceUsd: 9,
          imageUrl: 'https://img.example/home-most-valuable-1.jpg',
        ),
      },
      mostValuableCardsByFolderId: const {
        'main': [
          HomeCardHighlight(
            title: 'Home Card 1',
            subtitle: 'Set',
            priceUsd: 10,
            previousPriceUsd: 9,
            imageUrl: 'https://img.example/home-most-valuable-1.jpg',
          ),
          HomeCardHighlight(
            title: 'Home Card 2',
            subtitle: 'Set',
            priceUsd: 20,
            previousPriceUsd: 18,
            imageUrl: 'https://img.example/home-most-valuable-2.jpg',
          ),
        ],
        'sealed': [
          HomeCardHighlight(
            title: 'Other Folder Card',
            subtitle: 'Set',
            priceUsd: 30,
            previousPriceUsd: 27,
            imageUrl: 'https://img.example/other-folder.jpg',
          ),
        ],
      },
      trending: const [],
    );
  }

  @override
  Future<List<TrendingCard>> loadTrending() async {
    return const [
      TrendingCard(
        title: 'Trending 1',
        subtitle: 'Set',
        priceUsd: 11,
        increaseRate: 1,
        imageUrl: 'https://img.example/home-trending-1.jpg',
      ),
      TrendingCard(
        title: 'Trending 2',
        subtitle: 'Set',
        priceUsd: 22,
        increaseRate: 2,
        imageUrl: 'https://img.example/home-trending-2.jpg',
      ),
    ];
  }

  @override
  Future<HomeDashboard> loadDashboard() async {
    final dashboard = await loadCoreDashboard();
    return dashboard.copyWith(trending: await loadTrending());
  }
}

class _SearchImageCatalogRepository extends MockSearchRepository {
  _SearchImageCatalogRepository({required this.cardCount});

  final int cardCount;

  @override
  Future<SearchCatalog> loadCatalog() async {
    return SearchCatalog(
      games: const [SearchGame(id: 'pokemon', label: 'Pokemon')],
      cards: [
        for (var index = 0; index < cardCount; index++)
          SearchCard(
            id: 'card-$index',
            gameId: 'pokemon',
            type: SearchCardType.tcg,
            name: 'Card $index',
            priceUsd: index.toDouble(),
            previous30dPriceUsd: index.toDouble(),
            setName: 'Set',
            metadataLine: 'Rare',
            variantLine: 'Normal',
            quantity: 0,
            isWishlisted: false,
            changePercent: 0,
            imageUrl: 'https://img.example/card-$index.jpg',
          ),
      ],
      sets: const [],
    );
  }
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
