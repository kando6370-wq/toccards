import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  testWidgets('Home shows the M4-1 dashboard information hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _HomeTestApp()));

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('PORTFOLIO'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text(r'$12,840.00'), findsOneWidget);
    expect(find.text('1d'), findsOneWidget);
    expect(find.text('7d'), findsOneWidget);
    expect(find.text('15d'), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    expect(find.text('3m'), findsOneWidget);
    expect(find.text('6M'), findsNothing);
    expect(find.text('MAX'), findsNothing);
    expect(find.text('Most Valuable'), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Trending Today'), findsOneWidget);
    expect(find.text('Umbreon VMAX'), findsOneWidget);
  });

  testWidgets(
    'folder picker changes portfolio sections but not Trending Today',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: _HomeTestApp()));

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sealed').last);
      await tester.pumpAndSettle();

      expect(find.text('Sealed'), findsOneWidget);
      expect(find.text(r'$8,640.00'), findsOneWidget);
      expect(find.text('Evolving Skies Booster Box'), findsOneWidget);
      expect(find.text('Umbreon VMAX'), findsOneWidget);
    },
  );

  testWidgets(
    'currency picker converts money while percentages remain visible',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: _HomeTestApp()));

      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(find.text('GBP'), findsOneWidget);
      expect(find.text('SGD'), findsOneWidget);

      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();

      expect(find.text('EUR'), findsOneWidget);
      expect(find.textContaining('1,684.40'), findsOneWidget);
      expect(find.textContaining('382.20 in the last 30 days'), findsOneWidget);
      expect(find.text('+3.38%'), findsOneWidget);
    },
  );

  testWidgets('amount visibility toggle masks asset values', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _HomeTestApp()));

    await tester.tap(find.byKey(const Key('home-hide-amount')));
    await tester.pumpAndSettle();

    expect(find.text(hiddenMoneyText), findsWidgets);
    expect(find.text(r'$12,840.00'), findsNothing);
    expect(find.textContaining(r'$420.00'), findsNothing);
  });

  testWidgets('page failure shows Refresh and recovers without blanking nav', (
    tester,
  ) async {
    final repository = _FailingThenSuccessfulHomeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
        child: const _HomeTestApp(),
      ),
    );

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(repository.calls, 1);

    await tester.tap(find.text(refreshText));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text(r'$12,840.00'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('empty folder shows Most Valuable empty copy', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _HomeTestApp()));

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
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
        overrides: _localAuthOverrides(),
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Guest session'), findsOneWidget);
    expect(find.text('Sign in / Sign up'), findsOneWidget);
  });

  testWidgets('Collection bottom tab navigates to Collection page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();

    expect(find.text('Collection'), findsWidgets);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('This section is coming soon.'), findsNothing);
  });

  testWidgets('Search bottom tab navigates to Search page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _HomeTestAppWithRoutes(),
      ),
    );

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _HomeTestAppWithRoutes()),
    );

    await tester.tap(find.text('Scan'));
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
    authRepositoryProvider.overrideWithValue(
      LocalPlaceholderAuthRepository(storage),
    ),
  ];
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

class _FailingThenSuccessfulHomeRepository implements HomeRepository {
  var calls = 0;

  @override
  HomeDashboard loadDashboard() {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock home unavailable');
    }
    return const MockHomeRepository().loadDashboard();
  }
}
