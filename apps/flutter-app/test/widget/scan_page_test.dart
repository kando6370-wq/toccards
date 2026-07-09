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
  testWidgets(
    'Scan creates reviewable matches because scans are not saved automatically',
    (tester) async {
      await _pumpScanTestApp(tester);

      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Library'), findsOneWidget);
      expect(find.text('Review Your Matches'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(
        find.text(
          'Scan is coming soon. Use Search to find cards manually for now.',
        ),
        findsNothing,
      );

      await tester.tap(find.text('Take Photo'));
      await tester.pump();

      expect(find.text('Scanning'), findsOneWidget);
      final scanningDone = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done'),
      );
      expect(scanningDone.onPressed, isNull);

      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Matched'), findsOneWidget);
      expect(find.text('Mega Lucario ex'), findsWidgets);

      await tester.tap(find.text('Review Your Matches'));
      await tester.pumpAndSettle();

      expect(find.text('Adding to Main'), findsOneWidget);
      expect(find.text('Collection Item'), findsOneWidget);
      expect(find.text('Portfolio'), findsNothing);
      expect(find.text('Your Picture'), findsOneWidget);
      expect(find.text('Our Match'), findsOneWidget);
      expect(find.text('Top matched results'), findsOneWidget);
      expect(find.text('Near Mint (NM)'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add this card'));
      await tester.pumpAndSettle();

      expect(find.text('Added to Portfolio'), findsWidgets);
      expect(find.text('Mega Lucario ex'), findsWidgets);
    },
  );

  testWidgets(
    'No Match scan offers Search Manually because unmatched cards cannot enter review',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.text('Choose from Library'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No Match Found'), findsOneWidget);
      expect(find.text('Search Manually'), findsOneWidget);
      final noMatchDone = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done'),
      );
      expect(noMatchDone.onPressed, isNull);

      await tester.tap(find.text('Search Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Search cards, sets, or characters'), findsOneWidget);
      expect(find.text('Squirtle'), findsOneWidget);
    },
  );

  testWidgets(
    'Scan supports multiple results and only Matched items enter Add all review',
    (tester) async {
      await _pumpScanTestApp(tester);

      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      await tester.tap(find.text('Take Photo'));
      await tester.pump();
      await tester.tap(find.text('Choose from Library'));
      await tester.pump();

      expect(find.text('Scanning'), findsNWidgets(3));
      expect(find.text('Take Photo'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Mega Lucario ex'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('No Match Found'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Delete'), findsWidgets);
      expect(find.text('Search Manually'), findsOneWidget);

      final doneWithMatched = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done'),
      );
      expect(doneWithMatched.onPressed, isNotNull);

      await tester.tap(find.text('Take Photo'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Review Your Matches'), findsOneWidget);
      expect(find.text('Mega Lucario ex'), findsWidgets);
      expect(find.text('Charizard ex'), findsWidgets);
      expect(find.text('Failed'), findsNothing);
      expect(find.text('No Match Found'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Add all cards'), findsOneWidget);

      await tester.tap(find.text('Add all cards'));
      await tester.pumpAndSettle();

      expect(find.text('Added 2 cards to Portfolio'), findsOneWidget);
      expect(find.text('Mega Lucario ex'), findsWidgets);
      expect(find.text('Charizard ex'), findsWidgets);
    },
  );

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
