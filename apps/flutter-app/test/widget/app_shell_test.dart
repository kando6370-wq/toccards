import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/shared/portfolio/pending_collection.dart';
import 'package:kando_app/shared/ui/app_shell.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

void main() {
  testWidgets(
    'Android bottom navigation avoids the side safe area after resizing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: KandoTabScaffold(
              currentTab: KandoMainTab.search,
              body: SizedBox.expand(),
            ),
          ),
        ),
      );
      for (final size in [const Size(951, 669), const Size(466, 678)]) {
        tester.view.physicalSize = size;
        tester.view.padding = const FakeViewPadding(right: 108);
        await tester.pump();
        final bar = tester.getRect(find.byKey(const Key('kando-tab-bar')));
        final scan = tester.getRect(find.byKey(const Key('kando-tab-scan')));
        final overflow = tester.getRect(
          find.byKey(const Key('kando-tab-scan-overflow-hit-region')),
        );
        expect(bar.right, lessThanOrEqualTo(size.width - 108 - 20));
        expect(bar.left, greaterThanOrEqualTo(20));
        expect(bar.width, lessThanOrEqualTo(480));
        expect(bar.center.dx, closeTo((size.width - 108) / 2, 0.01));
        expect(overflow.topLeft, scan.topLeft);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Duo side navigation keeps all five destinations reachable while folding',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(951, 669);
      tester.view.padding = const FakeViewPadding(right: 84);
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          for (final tab in KandoMainTab.values)
            GoRoute(
              path: '/${tab.name}',
              builder: (context, state) => KandoTabScaffold(
                currentTab: tab,
                body: Text('page-${tab.name}'),
              ),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: ThemeData(platform: TargetPlatform.iOS),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final size in [
        const Size(951, 669),
        const Size(466, 678),
        const Size(951, 669),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final bar = tester.getRect(find.byKey(const Key('kando-tab-bar')));
        expect(bar.size, const Size(68, 380));
        expect(bar.left, greaterThanOrEqualTo(size.width - 84 + 8));
        expect(bar.right, lessThanOrEqualTo(size.width - 8));
        expect(bar.top, greaterThanOrEqualTo(200));
        expect(
          find.byKey(const Key('kando-tab-scan-overflow-hit-region')),
          findsNothing,
        );
        for (final tab in [
          KandoMainTab.search,
          KandoMainTab.scan,
          KandoMainTab.collection,
          KandoMainTab.profile,
          KandoMainTab.home,
        ]) {
          await tester.tap(find.byKey(Key('kando-tab-${tab.name}')));
          await tester.pumpAndSettle();
          expect(find.text('page-${tab.name}'), findsOneWidget);
          if (tab != KandoMainTab.scan) {
            expect(
              tester.getCenter(
                find.byKey(const Key('kando-tab-selected-background')),
              ),
              tester.getCenter(find.byKey(Key('kando-tab-${tab.name}'))),
            );
          }
        }
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(951, 480);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kando-side-navigation')), findsNothing);
      final fallback = tester.getRect(find.byKey(const Key('kando-tab-bar')));
      expect(fallback.height, 62);
      expect(fallback.right, lessThanOrEqualTo(951 - 84 - 20));
      await tester.tap(find.byKey(const Key('kando-tab-search')));
      await tester.pumpAndSettle();
      expect(find.text('page-search'), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('kando-tab-bar'))),
        const Size(350, 62),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('Kando color scheme is reused across scaffold rebuilds', () {
    expect(buildKandoColorScheme(), same(buildKandoColorScheme()));
  });

  testWidgets(
    'Figma tab bar keeps the 390x844 Home Search Scan Collection Profile order',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: KandoTabScaffold(
              currentTab: KandoMainTab.home,
              body: SizedBox.expand(),
            ),
          ),
        ),
      );

      final bar = find.byKey(const Key('kando-tab-bar'));
      final home = find.byKey(const Key('kando-tab-home'));
      final search = find.byKey(const Key('kando-tab-search'));
      final scan = find.byKey(const Key('kando-tab-scan'));
      final collection = find.byKey(const Key('kando-tab-collection'));
      final profile = find.byKey(const Key('kando-tab-profile'));

      expect(tester.getSize(bar), const Size(350, 62));
      expect(tester.getBottomRight(bar), const Offset(370, 822));
      expect(tester.getSize(scan), const Size.square(64));
      expect(
        tester.getTopLeft(scan).dx,
        closeTo(tester.getBottomRight(search).dx, 0.01),
      );
      expect(
        tester.getBottomRight(scan).dx,
        closeTo(tester.getTopLeft(collection).dx, 0.01),
      );
      expect(tester.getTopLeft(home).dx, 20);
      expect(tester.getBottomRight(profile).dx, 370);
      expect(tester.getCenter(home).dx, lessThan(tester.getCenter(search).dx));
      expect(tester.getCenter(search).dx, lessThan(tester.getCenter(scan).dx));
      expect(
        tester.getCenter(scan).dx,
        lessThan(tester.getCenter(collection).dx),
      );
      expect(
        tester.getCenter(collection).dx,
        lessThan(tester.getCenter(profile).dx),
      );
      expect(
        tester.getCenter(home).dx - tester.getTopLeft(bar).dx,
        closeTo(
          tester.getBottomRight(bar).dx - tester.getCenter(profile).dx,
          0.01,
        ),
      );
      expect(
        tester.getCenter(scan).dx - tester.getCenter(search).dx,
        closeTo(
          tester.getCenter(collection).dx - tester.getCenter(scan).dx,
          0.01,
        ),
      );
      expect(
        tester.getCenter(search).dx - tester.getCenter(home).dx,
        closeTo(
          tester.getCenter(profile).dx - tester.getCenter(collection).dx,
          0.01,
        ),
      );
      expect(find.text('Scan'), findsNothing);
      expect(find.text('Collection'), findsOneWidget);
    },
  );

  testWidgets('the visible top of the Scan button opens Scan', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const KandoTabScaffold(
            currentTab: KandoMainTab.home,
            body: SizedBox.expand(),
          ),
        ),
        GoRoute(
          path: '/scan',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('Scan target'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );

    final scanRect = tester.getRect(find.byKey(const Key('kando-tab-scan')));
    final overflowRect = tester.getRect(
      find.byKey(const Key('kando-tab-scan-overflow-hit-region')),
    );
    expect(overflowRect.size, const Size(64, 21));
    expect(overflowRect.topLeft, scanRect.topLeft);
    await tester.tapAt(Offset(scanRect.center.dx, scanRect.top + 4));
    await tester.pumpAndSettle();

    expect(find.text('Scan target'), findsOneWidget);
  });

  testWidgets('tab selection does not pass a page transition context', (
    tester,
  ) async {
    Object? searchTransition;
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const KandoTabScaffold(
            currentTab: KandoMainTab.home,
            body: SizedBox.expand(),
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (_, state) {
            searchTransition = state.extra;
            return const KandoTabScaffold(
              currentTab: KandoMainTab.search,
              body: SizedBox.expand(),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.tap(find.byKey(const Key('kando-tab-search')));
    await tester.pumpAndSettle();

    expect(searchTransition, isNull);
  });

  testWidgets('tab scaffold extends content behind translucent tab bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: KandoTabScaffold(
            currentTab: KandoMainTab.home,
            body: SizedBox.expand(),
          ),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBody, isTrue);
  });

  testWidgets(
    'pending collection notice stays visible across the four non-Scan tabs',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(pendingCollectionProvider.notifier)
          .add(
            const PendingCollectionCard(
              id: 'card-1',
              name: 'Card 1',
              game: 'Pokemon',
              setName: 'Set',
              metadataLine: '#1',
              variantLine: 'Normal',
            ),
          );

      for (final tab in const [
        KandoMainTab.home,
        KandoMainTab.search,
        KandoMainTab.scan,
        KandoMainTab.collection,
        KandoMainTab.profile,
      ]) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: KandoTabScaffold(
                currentTab: tab,
                body: const SizedBox.expand(),
              ),
            ),
          ),
        );
        final shouldShowNotice = tab != KandoMainTab.scan;
        expect(
          find.byKey(const Key('pending-collection-notice')),
          shouldShowNotice ? findsOneWidget : findsNothing,
        );
      }
    },
  );

  testWidgets(
    'updating a pending draft does not rebuild the Search page body when the notice count is unchanged',
    (tester) async {
      var bodyBuildCount = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: KandoTabScaffold(
              currentTab: KandoMainTab.search,
              body: _ThemeDependentBuildCounter(
                onBuild: () => bodyBuildCount += 1,
              ),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KandoTabScaffold)),
        listen: false,
      );
      container
          .read(pendingCollectionProvider.notifier)
          .add(
            const PendingCollectionCard(
              id: 'card-1',
              name: 'Card 1',
              game: 'Pokemon',
              setName: 'Set',
              metadataLine: '#1',
              variantLine: 'Normal',
            ),
          );
      await tester.pump();
      final buildCountAfterNoticeAppears = bodyBuildCount;
      final pendingItem = container.read(pendingCollectionProvider).single;
      final scaffoldElement = tester.element(find.byType(KandoTabScaffold));

      container
          .read(pendingCollectionProvider.notifier)
          .updateDraft(
            pendingItem.id,
            const PendingCollectionDraft(
              quantityText: '1',
              portfolioName: 'Main',
              grader: 'Raw',
              condition: 'Near Mint (NM)',
              grade: '10',
              language: 'English',
              finish: 'Normal',
              purchasePriceText: '',
              notes: '',
            ),
          );
      expect(
        scaffoldElement.dirty,
        isFalse,
        reason: 'The notice only depends on the pending item count.',
      );
      await tester.pump();

      expect(bodyBuildCount, buildCountAfterNoticeAppears);
      expect(
        find.byKey(const Key('pending-collection-notice')),
        findsOneWidget,
      );
      expect(find.text('1 card waiting for details'), findsOneWidget);
    },
  );

  testWidgets('selected tab background slides from the previous active tab', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/collection',
      routes: [
        GoRoute(
          path: '/collection',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: KandoTabScaffold(
              currentTab: KandoMainTab.collection,
              body: SizedBox.expand(),
            ),
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => const NoTransitionPage<void>(
            child: KandoTabScaffold(
              currentTab: KandoMainTab.profile,
              body: SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );

    final background = find.byKey(const Key('kando-tab-selected-background'));
    final collection = find.byKey(const Key('kando-tab-collection'));
    final profile = find.byKey(const Key('kando-tab-profile'));
    final collectionCenter = tester.getCenter(collection).dx;
    final profileCenter = tester.getCenter(profile).dx;

    expect(tester.getCenter(background).dx, closeTo(collectionCenter, 0.01));

    await tester.tap(profile);
    await tester.pump();

    expect(tester.getCenter(background).dx, closeTo(collectionCenter, 0.01));

    await tester.pump(const Duration(milliseconds: 110));
    final midAnimationCenter = tester.getCenter(background).dx;
    expect(midAnimationCenter, greaterThan(collectionCenter));
    expect(midAnimationCenter, lessThan(profileCenter));

    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.getCenter(background).dx, closeTo(profileCenter, 0.01));
  });

  testWidgets('Figma tab bar renders at the approved 390x844 baseline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildKandoTheme(),
          home: const KandoTabScaffold(
            currentTab: KandoMainTab.home,
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('kando-tab-bar')),
      matchesGoldenFile('goldens/rendered/figma_tab_bar_home_390x844.png'),
    );
  });
}

class _ThemeDependentBuildCounter extends StatelessWidget {
  const _ThemeDependentBuildCounter({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    onBuild();
    return const SizedBox.expand();
  }
}
