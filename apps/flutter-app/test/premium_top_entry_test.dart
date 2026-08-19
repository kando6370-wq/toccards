import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/subscription/premium_top_entry.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';

void main() {
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

  testWidgets(
    'only explicit Free shows the top entry and opens the source sheet',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/source',
        routes: [
          GoRoute(
            path: '/source',
            builder: (_, _) =>
                const Scaffold(body: PremiumTopEntry(source: 'search')),
          ),
          GoRoute(
            path: '/subscription',
            builder: (_, state) => Scaffold(body: Text(state.uri.query)),
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

      expect(find.byKey(const Key('search-premium-top-entry')), findsOneWidget);
      expect(find.byTooltip('View Premium plans'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('search-premium-top-entry'))),
        const Size(32, 32),
      );
      await tester.tap(find.byKey(const Key('search-premium-top-entry')));
      await tester.pumpAndSettle();
      expect(find.textContaining('source=search'), findsOneWidget);
      expect(
        find.textContaining('entry_source=top_subscription_entry'),
        findsOneWidget,
      );
      expect(find.textContaining('presentation=sheet'), findsOneWidget);
    },
  );

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
