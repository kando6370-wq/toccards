import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/search/search_page.dart';

void main() {
  testWidgets('Home shows the M4-1 dashboard information hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _HomeTestApp()));

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('PORTFOLIO'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text(r'$12,840'), findsOneWidget);
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
      expect(find.text(r'$8,640'), findsOneWidget);
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
      await tester.tap(find.text('CNY').last);
      await tester.pumpAndSettle();

      expect(find.text('CNY'), findsOneWidget);
      expect(find.text('¥89,880'), findsOneWidget);
      expect(find.text('+3.38%'), findsOneWidget);
    },
  );

  testWidgets('amount visibility toggle masks asset values', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _HomeTestApp()));

    await tester.tap(find.byKey(const Key('home-hide-amount')));
    await tester.pumpAndSettle();

    expect(find.text('••••••'), findsWidgets);
    expect(find.text(r'$12,840'), findsNothing);
    expect(find.textContaining(r'$420'), findsNothing);
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
      const ProviderScope(child: _HomeTestAppWithRoutes()),
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
      const ProviderScope(child: _HomeTestAppWithRoutes()),
    );

    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();

    expect(find.text('Collection'), findsWidgets);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('This section is coming soon.'), findsNothing);
  });

  testWidgets('Search bottom tab navigates to Search page', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _HomeTestAppWithRoutes()),
    );

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });
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
