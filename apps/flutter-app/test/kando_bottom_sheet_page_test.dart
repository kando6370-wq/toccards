import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_bottom_sheet_page.dart';

void main() {
  testWidgets('routed bottom sheet uses the requested height and dismisses', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/sheet'),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/sheet',
          pageBuilder: (context, state) => KandoBottomSheetPage<void>(
            key: state.pageKey,
            heightFactor: 0.5,
            child: const Material(
              child: SizedBox.expand(
                key: Key('sheet-body'),
                child: Center(child: Text('Sheet content')),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('sheet-body'));
    final handleArea = find.byKey(const Key('kando-bottom-sheet-handle-area'));
    final handle = find.byKey(const Key('kando-bottom-sheet-handle'));
    expect(sheet, findsOneWidget);
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
      isFalse,
    );
    final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
    final contentTop = tester.getTopLeft(sheet).dy;
    expect(tester.getSize(handleArea).height, 32);
    expect(tester.getSize(handle), const Size(32, 4));
    expect(tester.getTopLeft(handleArea).dy, sheetTop);
    expect(contentTop - sheetTop, 32);
    expect(
      tester.getSize(sheet).height,
      closeTo(
        (tester.view.physicalSize.height / tester.view.devicePixelRatio - 32) /
            2,
        1,
      ),
    );

    await tester.dragFrom(tester.getCenter(handleArea), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);

    await tester.drag(sheet, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(sheet, findsNothing);
    expect(find.text('Open sheet'), findsOneWidget);
  });

  testWidgets('long content scrolls below the stationary drag handle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/sheet'),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/sheet',
          pageBuilder: (context, state) => KandoBottomSheetPage<void>(
            key: state.pageKey,
            heightFactor: 0.6,
            child: Material(
              child: ListView.builder(
                key: const Key('sheet-list'),
                itemCount: 30,
                itemExtent: 56,
                itemBuilder: (context, index) =>
                    ListTile(title: Text('Row $index')),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('sheet-list'));
    final handleArea = find.byKey(const Key('kando-bottom-sheet-handle-area'));
    final handleTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
    final contentTop = tester.getTopLeft(list).dy;
    expect(tester.getSize(handleArea).height, 32);
    expect(contentTop - handleTop, 32);
    expect(find.text('Row 0'), findsOneWidget);

    await tester.drag(list, const Offset(0, -550));
    await tester.pumpAndSettle();

    expect(find.text('Row 0'), findsNothing);
    expect(find.text('Row 12'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(BottomSheet)).dy, handleTop);
    expect(tester.getTopLeft(handleArea).dy, handleTop);
    expect(tester.getTopLeft(list).dy, contentTop);
  });
}
