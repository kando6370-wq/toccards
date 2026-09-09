import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/subscription/premium_top_entry.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/features/subscription/subscription_route_page.dart';
import 'package:kando_app/shared/ui/kando_bottom_sheet_page.dart';

void main() {
  test('full Subscription Page location keeps source without sheet mode', () {
    final uri = Uri.parse(
      subscriptionPageLocation(source: 'scan', entrySource: 'scan_pro_card'),
    );

    expect(uri.path, '/subscription');
    expect(uri.queryParameters['source'], 'scan');
    expect(uri.queryParameters['entry_source'], 'scan_pro_card');
    expect(uri.queryParameters.containsKey('presentation'), isFalse);
    final sheet = Uri.parse(
      subscriptionSheetLocation(scene: 'cardDetailPerformance'),
    );
    expect(sheet.queryParameters['presentation'], 'sheet');
    expect(sheet.queryParameters['scene'], 'cardDetailPerformance');
  });

  test('full page and sheet use the same subscription transition duration', () {
    final fullPage = KandoSubscriptionPage<void>(
      key: const ValueKey('subscription-full-page'),
      source: 'home',
      child: const SizedBox(),
    );
    const sheetPage = KandoBottomSheetPage<void>(
      child: SizedBox(),
      sheetAnimationStyle: subscriptionSheetAnimationStyle,
    );

    expect(fullPage.transitionDuration, subscriptionTransitionDuration);
    expect(fullPage.reverseTransitionDuration, subscriptionTransitionDuration);
    expect(
      sheetPage.sheetAnimationStyle?.duration,
      subscriptionTransitionDuration,
    );
    expect(
      sheetPage.sheetAnimationStyle?.reverseDuration,
      subscriptionTransitionDuration,
    );
  });

  testWidgets(
    'main Tab Subscription Page enters from the bottom and startup sources do not animate',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: '/subscription',
            pageBuilder: (_, state) => KandoSubscriptionPage<void>(
              key: state.pageKey,
              source: state.uri.queryParameters['source'],
              duration: const Duration(milliseconds: 500),
              child: const ColoredBox(
                key: Key('subscription-route-target'),
                color: Colors.black,
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.push('/subscription?source=home');
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .getTopLeft(find.byKey(const Key('subscription-route-target')))
            .dy,
        closeTo(844, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 250));
      final midpoint = tester
          .getTopLeft(find.byKey(const Key('subscription-route-target')))
          .dy;
      expect(midpoint, greaterThan(0));
      expect(midpoint, lessThan(844));
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(find.byKey(const Key('subscription-route-target')))
            .dy,
        closeTo(0, 0.01),
      );

      for (final source in const [
        'home',
        'search',
        'scan',
        'collection',
        'profile',
      ]) {
        expect(subscriptionPageEntersFromBottom(source), isTrue);
      }
      expect(subscriptionPageEntersFromBottom('cold_start'), isFalse);
      expect(subscriptionPageEntersFromBottom('onboarding'), isFalse);
      expect(subscriptionPageEntersFromBottom(null), isFalse);
    },
  );

  testWidgets('page header matches the shared Figma title and PRO layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionControllerProvider.overrideWith(
            _FreeSubscriptionController.new,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PremiumPageHeader(title: 'Search', source: 'search'),
          ),
        ),
      ),
    );

    final header = find.byKey(const Key('search-premium-page-header'));
    final title = tester.widget<Text>(
      find.byKey(const Key('search-premium-page-title')),
    );
    expect(tester.getSize(header).height, 32);
    expect(title.data, 'Search');
    expect(title.style?.fontFamily, 'Fraunces');
    expect(title.style?.fontSize, 24);
    expect(find.text('PRO'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('search-premium-top-entry'))).height,
      32,
    );
  });

  for (final source in ['home', 'search', 'collection', 'profile']) {
    testWidgets(
      'Free $source top entry opens the full source Subscription Page',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/source',
          routes: [
            GoRoute(
              path: '/source',
              builder: (_, _) =>
                  Scaffold(body: PremiumTopEntry(source: source)),
            ),
            GoRoute(
              path: '/subscription',
              builder: (_, state) => Scaffold(
                body: Text(
                  state.uri.query,
                  key: const Key('subscription-query'),
                ),
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              subscriptionControllerProvider.overrideWith(
                _FreeSubscriptionController.new,
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        final entry = find.byKey(Key('$source-premium-top-entry'));
        expect(entry, findsOneWidget);
        expect(find.byTooltip('View Premium plans'), findsOneWidget);
        expect(tester.getSize(entry), const Size(32, 32));
        await tester.tap(entry);
        await tester.pumpAndSettle();
        final query = tester
            .widget<Text>(find.byKey(const Key('subscription-query')))
            .data!;
        final parameters = Uri.splitQueryString(query);
        expect(parameters['source'], source);
        expect(parameters['entry_source'], 'top_subscription_entry');
        expect(parameters.containsKey('presentation'), isFalse);
      },
    );
  }

  for (final state in [AppPremiumState.unknown, AppPremiumState.premium]) {
    testWidgets('$state hides the top entry', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionControllerProvider.overrideWith(
              () => _FixedSubscriptionController(state),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: PremiumTopEntry(source: 'home')),
          ),
        ),
      );

      expect(find.byKey(const Key('home-premium-top-entry')), findsNothing);
    });
  }
}

class _FreeSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.free);
}

class _FixedSubscriptionController extends SubscriptionController {
  _FixedSubscriptionController(this.premiumState);

  final AppPremiumState premiumState;

  @override
  SubscriptionState build() => SubscriptionState(premiumState: premiumState);
}
