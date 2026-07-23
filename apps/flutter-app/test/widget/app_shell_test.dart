import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/shared/ui/app_shell.dart';

void main() {
  testWidgets(
    'Figma tab bar keeps the 390x844 Home Search Scan Collection Profile order',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: KandoTabScaffold(
            currentTab: KandoMainTab.home,
            body: SizedBox.expand(),
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

  testWidgets('tab scaffold extends content behind translucent tab bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KandoTabScaffold(
          currentTab: KandoMainTab.home,
          body: SizedBox.expand(),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBody, isTrue);
  });

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

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

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
      MaterialApp(
        theme: buildKandoTheme(),
        home: const KandoTabScaffold(
          currentTab: KandoMainTab.home,
          body: SizedBox.expand(),
        ),
      ),
    );

    await expectLater(
      find.byKey(const Key('kando-tab-bar')),
      matchesGoldenFile('goldens/rendered/figma_tab_bar_home_390x844.png'),
    );
  });
}
