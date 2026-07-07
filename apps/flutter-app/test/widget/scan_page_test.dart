import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_page.dart';

void main() {
  testWidgets('Scan placeholder guides users to Search', (tester) async {
    await _pumpScanTestApp(tester);

    expect(find.text('扫描功能即将上线'), findsOneWidget);
    expect(
      find.text(
        'Scan is coming soon. Use Search to find cards manually for now.',
      ),
      findsOneWidget,
    );
    expect(find.text('Search Cards'), findsOneWidget);

    await tester.tap(find.text('Search Cards'));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets('Scan bottom navigation can open app sections', (tester) async {
    await _pumpScanTestApp(tester);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);

    await _pumpScanTestApp(tester);
    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    expect(find.text('Portfolio'), findsWidgets);

    await _pumpScanTestApp(tester);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Squirtle'), findsOneWidget);

    await _pumpScanTestApp(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Guest session'), findsOneWidget);
  });
}

Future<void> _pumpScanTestApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: _ScanTestAppWithRoutes()));
  await tester.pumpAndSettle();
}

class _ScanTestAppWithRoutes extends StatelessWidget {
  const _ScanTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/scan',
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
