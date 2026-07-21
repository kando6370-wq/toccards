import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/shared/ui/app_shell.dart';

void main() {
  testWidgets(
    'Figma tab bar keeps the 390x844 Home Search Scan collection Profile order',
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
      expect(tester.getBottomRight(bar), const Offset(370, 812));
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
      expect(find.text('collection'), findsOneWidget);
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

  testWidgets('Figma tab bar renders at the approved 390x844 baseline', (
    tester,
  ) async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
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
