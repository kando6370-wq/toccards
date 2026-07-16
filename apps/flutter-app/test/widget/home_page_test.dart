import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_collection_repository.dart';
import '../support/mock_home_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  test(
    'Figma Home card photo decodes at its design source aspect ratio',
    () async {
      final data = await rootBundle.load('assets/home/mega_lucario_ex.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      addTearDown(() {
        frame.image.dispose();
        codec.dispose();
      });

      expect(frame.image.width, 980);
      expect(frame.image.height, 1367);
    },
  );

  testWidgets('Figma Home card image emits a renderable Flutter image frame', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    final context = tester.element(find.byType(SizedBox).first);
    final stream = const AssetImage(
      'assets/home/mega_lucario_ex.png',
    ).resolve(createLocalImageConfiguration(context));
    final loaded = Completer<void>();
    final listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!loaded.isCompleted) {
          loaded.complete();
        }
      },
      onError: (error, stackTrace) {
        if (!loaded.isCompleted) {
          loaded.completeError(error, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    addTearDown(() => stream.removeListener(listener));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(loaded.isCompleted, isTrue);
  });

  testWidgets('Figma normal Home renders at the approved 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    await (FontLoader(
      'Fraunces',
    )..addFont(rootBundle.load('assets/fonts/Fraunces-Variable.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        ],
        child: MaterialApp(
          theme: buildKandoTheme(),
          home: const RepaintBoundary(
            key: Key('home-figma-golden'),
            child: HomePage(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('home-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_home_normal_131_21335_390x844.png',
      ),
    );
  });

  testWidgets('Figma partial Home failure renders at the 390x844 baseline', (
    tester,
  ) async {
    final repository = _SuccessfulThenFailingHomeRepository();
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    await (FontLoader(
      'Fraunces',
    )..addFont(rootBundle.load('assets/fonts/Fraunces-Variable.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: buildKandoTheme(),
          home: const RepaintBoundary(
            key: Key('home-failure-figma-golden'),
            child: HomePage(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    _refreshHome(tester);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('home-failure-figma-golden')),
      matchesGoldenFile(
        'goldens/rendered/figma_home_failure_131_21496_390x844.png',
      ),
    );
  });

  testWidgets('Home shows the M4-1 dashboard information hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('PORTFOLIO'), findsOneWidget);
    expect(find.text('PORTDOLIO'), findsNothing);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text(r'$12,450.80'), findsOneWidget);
    expect(find.text('1D'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('15D'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('3M'), findsOneWidget);
    expect(find.text('6M'), findsNothing);
    expect(find.text('MAX'), findsNothing);
    expect(find.text('Most Valuable'), findsOneWidget);
    expect(find.text('Pikachu'), findsWidgets);
    expect(find.byKey(const Key('home-most-valuable-list')), findsOneWidget);
    expect(
      find.byKey(const Key('home-most-valuable-card-main-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-most-valuable-card-main-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-most-valuable-card-main-2')),
      findsOneWidget,
    );
    expect(find.text('Trending Today'), findsOneWidget);
    expect(find.text('Ragavan, Nimble Pilferer'), findsOneWidget);
  });

  testWidgets('Overview uses the Figma filled 16px inverse label', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    final overview = tester.widget<Text>(find.text('Overview'));
    expect(overview.style?.fontSize, 16);
    expect(overview.style?.color, const Color(0xFF303126));
  });

  testWidgets('Figma Home headings and card names use Fraunces', (
    tester,
  ) async {
    await tester.pumpWidget(_mockHomeApp());

    expect(
      tester.widget<Text>(find.text('Most Valuable')).style?.fontFamily,
      'Fraunces',
    );
    expect(
      tester.widget<Text>(find.text('Pikachu').first).style?.fontFamily,
      'Fraunces',
    );
    expect(
      tester
          .widget<Text>(find.text('Ragavan, Nimble Pilferer'))
          .style
          ?.fontFamily,
      'Fraunces',
    );
  });

  testWidgets(
    'Figma Home arrow assets render without a Material Icons font dependency',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());

      expect(find.byKey(const Key('home-currency-chevron')), findsOneWidget);
      expect(find.byKey(const Key('home-view-all-arrow')), findsNWidgets(2));
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_forward), findsNothing);
    },
  );

  testWidgets(
    'folder picker changes portfolio sections but not Trending Today',
    (tester) async {
      final preferences = _TestPortfolioManagementApi();
      await tester.pumpWidget(_mockHomeApp(preferences));
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();

      expect(find.text('DRAG AND DROP TO CHANGE ORDER'), findsOneWidget);
      expect(find.byKey(const Key('collection-folder-add')), findsOneWidget);
      expect(
        find.byKey(const Key('collection-folder-edit-sealed')),
        findsOneWidget,
      );

      await tester.tap(find.text('Sealed').last);
      await tester.pumpAndSettle();

      expect(find.text('Sealed'), findsOneWidget);
      expect(find.text(r'$8,640.00'), findsOneWidget);
      expect(find.text('Evolving Skies Booster Box'), findsOneWidget);
      expect(find.text('Ragavan, Nimble Pilferer'), findsOneWidget);
      expect(preferences.selectedFolderIds, ['sealed']);
    },
  );

  testWidgets(
    'currency picker converts the Figma portfolio and card price surfaces',
    (tester) async {
      final preferences = _TestPortfolioManagementApi();
      await tester.pumpWidget(_mockHomeApp(preferences));
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(find.text('GBP'), findsOneWidget);
      expect(find.text('SGD'), findsOneWidget);

      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();

      expect(find.text('EUR'), findsOneWidget);
      expect(find.textContaining('11,330.23'), findsOneWidget);
      expect(find.textContaining('9,100,000'), findsWidgets);
      expect(preferences.currencyCodes, ['EUR']);
    },
  );

  testWidgets(
    'currency search filters by display name before the real rate and preference update',
    (tester) async {
      final preferences = _TestPortfolioManagementApi();
      await tester.pumpWidget(_mockHomeApp(preferences));
      await _waitForHomeAuth(tester);

      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('home-currency-search')),
        'pound',
      );
      await tester.pump();

      expect(find.text('GBP'), findsOneWidget);
      expect(find.text('EUR'), findsNothing);

      await tester.tap(find.text('GBP'));
      await tester.pumpAndSettle();

      expect(preferences.currencyCodes, ['GBP']);
      expect(find.text('GBP'), findsOneWidget);
    },
  );

  testWidgets('amount visibility toggle masks asset values', (tester) async {
    final preferences = _TestPortfolioManagementApi();
    await tester.pumpWidget(_mockHomeApp(preferences));
    await _waitForHomeAuth(tester);

    await tester.tap(find.byKey(const Key('home-hide-amount')));
    await tester.pumpAndSettle();

    expect(find.text(hiddenMoneyText), findsWidgets);
    expect(find.text(r'$12,450.80'), findsNothing);
    expect(find.textContaining(r'$420.00'), findsNothing);
    expect(preferences.amountHiddenValues, [true]);
  });

  testWidgets(
    'Most Valuable change badges stay tied to the displayed card data after a portfolio switch',
    (tester) async {
      await tester.pumpWidget(_mockHomeApp());
      await _waitForHomeAuth(tester);

      expect(find.text('+3.20%'), findsOneWidget);
      expect(find.text('0.001%'), findsNothing);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sealed').last);
      await tester.pumpAndSettle();

      expect(find.text('+5.40%'), findsOneWidget);
      expect(find.text('0.001%'), findsNothing);
    },
  );

  testWidgets(
    'page data failure keeps the Figma dashboard shell and refreshes local panels',
    (tester) async {
      final repository = _SuccessfulThenFailingHomeRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
          child: const _HomeTestApp(),
        ),
      );

      _refreshHome(tester);
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(find.text('Trending Today'), findsOneWidget);
      expect(find.text('Ragavan, Nimble Pilferer'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNWidgets(2));
      expect(find.byKey(const Key('home-failure-chart')), findsOneWidget);
      expect(
        find.byKey(const Key('home-failure-most-valuable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-failure-chart-refresh')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-failure-most-valuable-refresh')),
        findsOneWidget,
      );
      expect(find.text('Home'), findsOneWidget);
      expect(repository.calls, 2);

      await tester.tap(find.byKey(const Key('home-failure-chart-refresh')));
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);
      expect(repository.calls, 3);
    },
  );

  testWidgets(
    'Trending failure stays local because portfolio history remains usable',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeRepositoryProvider.overrideWithValue(
              const _TrendingUnavailableHomeRepository(),
            ),
          ],
          child: MaterialApp(theme: buildKandoTheme(), home: const HomePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(r'$12,450.80'), findsOneWidget);
      expect(find.byKey(const Key('home-failure-chart')), findsNothing);
      expect(find.byKey(const Key('home-most-valuable-list')), findsOneWidget);
      expect(find.byKey(const Key('home-failure-trending')), findsOneWidget);
      expect(
        find.byKey(const Key('home-failure-trending-refresh')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Most Valuable failure refresh independently restores dashboard content',
    (tester) async {
      final repository = _SuccessfulThenFailingHomeRepository();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeRepositoryProvider.overrideWithValue(repository)],
          child: const _HomeTestApp(),
        ),
      );

      _refreshHome(tester);
      await tester.pumpAndSettle();

      final refresh = find.byKey(
        const Key('home-failure-most-valuable-refresh'),
      );
      await tester.scrollUntilVisible(refresh, 120);
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(find.text(noContentAvailableText), findsNothing);
      expect(find.byKey(const Key('home-most-valuable-list')), findsOneWidget);
      expect(repository.calls, 3);
    },
  );

  testWidgets('failed dashboard uses Figma placeholders for every trend card', (
    tester,
  ) async {
    final repository = _SuccessfulThenFailingHomeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
        child: const _HomeTestApp(),
      ),
    );
    _refreshHome(tester);
    await tester.pumpAndSettle();

    for (var index = 0; index < 3; index += 1) {
      expect(
        find.byKey(Key('home-failure-trend-placeholder-$index')),
        findsOneWidget,
      );
    }
  });

  testWidgets('empty folder shows Most Valuable empty copy', (tester) async {
    await tester.pumpWidget(_mockHomeApp());
    await _waitForHomeAuth(tester);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Empty'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Empty').last);
    await tester.pumpAndSettle();

    expect(find.text('No cards in this portfolio yet'), findsOneWidget);
    expect(find.text('Trending Today'), findsOneWidget);
  });

  testWidgets('Profile bottom tab navigates to the existing Profile page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.byKey(const Key('kando-tab-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Sign in / Sign up'), findsOneWidget);
  });

  testWidgets('Collection opens with Home portfolio preferences', (
    tester,
  ) async {
    final preferences = _TestPortfolioManagementApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
          portfolioManagementApiProvider.overrideWithValue(preferences),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );
    await _waitForHomeAuth(tester);

    final homeContext = tester.element(find.byType(HomePage));
    final container = ProviderScope.containerOf(homeContext);
    expect(
      await container
          .read(homeControllerProvider.notifier)
          .selectFolder('sealed'),
      isTrue,
    );
    expect(
      await container
          .read(homeControllerProvider.notifier)
          .toggleAmountHidden(),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('kando-tab-collection')));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('This section is coming soon.'), findsNothing);
    final collection = container.read(collectionControllerProvider);
    expect(collection.selectedFolder.id, 'sealed');
    expect(collection.amountHidden, isTrue);
  });

  testWidgets(
    'Most Valuable View all opens the selected portfolio by value because Home only previews the top cards',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
          ],
          child: const _HomeTestAppWithRoutes(),
        ),
      );
      await _waitForHomeAuth(tester);

      await tester.tap(find.byKey(const Key('home-most-valuable-view-all')));
      await tester.pumpAndSettle();

      expect(find.byType(CollectionPage), findsOneWidget);
      final context = tester.element(find.byType(CollectionPage));
      final collection = ProviderScope.containerOf(
        context,
      ).read(collectionControllerProvider);
      expect(collection.selectedTab, CollectionTab.portfolio);
      expect(collection.selectedSort, CollectionSort.valueDesc);
      expect(collection.visibleItems.first.name, 'Charizard ex');
    },
  );

  testWidgets(
    'Trending View all opens Search because Search is backed by the live trending feed',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            homeRepositoryProvider.overrideWithValue(
              const MockHomeRepository(),
            ),
          ],
          child: const _HomeTestAppWithRoutes(),
        ),
      );

      final viewAll = find.byKey(const Key('home-trending-view-all'));
      await tester.ensureVisible(viewAll);
      await tester.tap(viewAll);
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.text('Squirtle'), findsOneWidget);
    },
  );

  testWidgets('Search bottom tab navigates to Search page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._searchOverrides(),
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.byKey(const Key('kando-tab-search')));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.byKey(const Key('kando-tab-scan')));
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });
}

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}

_localAuthOverrides() {
  final storage = InMemoryAuthStorage();
  return [
    authStorageProvider.overrideWithValue(storage),
    authRepositoryProvider.overrideWithValue(
      LocalPlaceholderAuthRepository(storage),
    ),
  ];
}

Widget _mockHomeApp([PortfolioManagementApi? managementApi]) {
  final portfolioManagement = managementApi ?? _TestPortfolioManagementApi();
  return ProviderScope(
    overrides: [
      ..._localAuthOverrides(),
      homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
      collectionRepositoryProvider.overrideWithValue(
        _HomeCollectionRepository(portfolioManagement),
      ),
      portfolioManagementApiProvider.overrideWithValue(portfolioManagement),
      currencyRateApiProvider.overrideWithValue(const _TestCurrencyRateApi()),
    ],
    child: const _HomeTestApp(),
  );
}

class _HomeCollectionRepository extends MockCollectionRepository {
  const _HomeCollectionRepository(this._managementApi);

  final PortfolioManagementApi _managementApi;

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    await _managementApi.updatePreferences(
      session,
      currency: currency,
      amountHidden: amountHidden,
      lastSelectedFolderId: lastSelectedFolderId,
    );
  }
}

class _TestCurrencyRateApi implements CurrencyRateApi {
  const _TestCurrencyRateApi();

  @override
  Future<double> loadUsdRate(String targetCurrency) async => 0.91;
}

class _TestPortfolioManagementApi implements PortfolioManagementApi {
  final List<String> currencyCodes = [];
  final List<bool> amountHiddenValues = [];
  final List<String> selectedFolderIds = [];

  @override
  Future<UserPreferenceDto> getPreferences(AuthSession session) async {
    return const UserPreferenceDto(
      currency: 'USD',
      amountHidden: false,
      lastSelectedFolderId: null,
    );
  }

  @override
  Future<UserPreferenceDto> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    if (currency != null) currencyCodes.add(currency);
    if (amountHidden != null) amountHiddenValues.add(amountHidden);
    if (lastSelectedFolderId != null) {
      selectedFolderIds.add(lastSelectedFolderId);
    }
    return UserPreferenceDto(
      currency: currency ?? 'USD',
      amountHidden: amountHidden ?? false,
      lastSelectedFolderId: lastSelectedFolderId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _refreshHome(WidgetTester tester) {
  final context = tester.element(find.byType(HomePage));
  ProviderScope.containerOf(
    context,
  ).read(homeControllerProvider.notifier).refresh();
}

Future<void> _waitForHomeAuth(WidgetTester tester) async {
  final context = tester.element(find.byType(HomePage));
  final container = ProviderScope.containerOf(context);
  await container.read(authControllerProvider.notifier).startupComplete;
  await tester.pumpAndSettle();
}

class _HomeTestApp extends StatelessWidget {
  const _HomeTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomePage());
  }
}

class _HomeTestAppWithRoutes extends StatelessWidget {
  const _HomeTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => const CollectionPage(),
          ),
          GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
    );
  }
}

class _SuccessfulThenFailingHomeRepository implements HomeRepository {
  var calls = 0;

  @override
  HomeDashboard loadDashboard() {
    calls += 1;
    if (calls == 2) {
      throw StateError('mock home unavailable');
    }
    return const MockHomeRepository().loadDashboard();
  }
}

class _TrendingUnavailableHomeRepository implements HomeRepository {
  const _TrendingUnavailableHomeRepository();

  @override
  HomeDashboard loadDashboard() {
    return mockHomeDashboard.copyWith(
      trending: const [],
      trendingUnavailable: true,
    );
  }
}
