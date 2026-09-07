import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/subscription/startup_subscription_gate.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/features/subscription/subscription_page.dart';

void main() {
  testWidgets(
    'cold start shows the full Subscription Page only after Free is confirmed',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          _StartupSubscriptionController(AppPremiumState.free),
          source: 'cold_start',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionPage), findsOneWidget);
      expect(
        tester.widget<SubscriptionPage>(find.byType(SubscriptionPage)).source,
        'cold_start',
      );
      expect(find.text('Home ready'), findsNothing);
    },
  );

  testWidgets('cold start sends confirmed Premium directly to Home', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(_StartupSubscriptionController(AppPremiumState.premium)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home ready'), findsOneWidget);
    expect(find.byType(SubscriptionPage), findsNothing);
  });

  testWidgets(
    'cold start sends unresolved entitlement to Home without pretending it is Free',
    (tester) async {
      await tester.pumpWidget(
        _testApp(_StartupSubscriptionController(AppPremiumState.unknown)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home ready'), findsOneWidget);
      expect(find.byType(SubscriptionPage), findsNothing);
    },
  );

  testWidgets('startup keeps Home hidden while entitlement is unresolved', (
    tester,
  ) async {
    final result = Completer<AppPremiumState>();
    await tester.pumpWidget(
      _testApp(_PendingStartupSubscriptionController(result)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('startup-entitlement-loading')),
      findsOneWidget,
    );
    expect(find.text('Home ready'), findsNothing);

    result.complete(AppPremiumState.premium);
    await tester.pumpAndSettle();
    expect(find.text('Home ready'), findsOneWidget);
  });

  testWidgets(
    'onboarding purchase stays on Success until Start Exploring is tapped',
    (tester) async {
      final controller = _StartupSubscriptionController(AppPremiumState.free);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const StartupSubscriptionGate(
              source: 'onboarding',
              home: Text('Home ready'),
            ),
          ),
          GoRoute(
            path: '/subscription/success',
            builder: (_, state) => SubscriptionSuccessPage(
              source: state.uri.queryParameters['source'],
            ),
          ),
          GoRoute(path: '/home', builder: (_, _) => const Text('Home ready')),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionControllerProvider.overrideWith(() => controller),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SubscriptionPage), findsOneWidget);

      controller.emit(SubscriptionResultEvent.purchaseSuccess);
      controller.emit(SubscriptionResultEvent.externalPremium);
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionSuccessPage), findsOneWidget);
      expect(find.text('Home ready'), findsNothing);
      expect(find.byKey(const Key('premium-unlocked-toast')), findsNothing);

      final startExploring = find.byKey(
        const Key('subscription-success-continue'),
      );
      await tester.ensureVisible(startExploring);
      await tester.tap(startExploring);
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionSuccessPage), findsNothing);
      expect(find.text('Home ready'), findsOneWidget);
      expect(find.byKey(const Key('premium-unlocked-toast')), findsNothing);
    },
  );
}

Widget _testApp(
  SubscriptionController controller, {
  String source = 'cold_start',
}) {
  return ProviderScope(
    overrides: [subscriptionControllerProvider.overrideWith(() => controller)],
    child: MaterialApp(
      home: StartupSubscriptionGate(
        source: source,
        home: const Text('Home ready'),
      ),
    ),
  );
}

class _StartupSubscriptionController extends SubscriptionController {
  _StartupSubscriptionController(this.resolvedState);

  final AppPremiumState resolvedState;

  @override
  SubscriptionState build() => const SubscriptionState();

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async {
    state = state.copyWith(premiumState: resolvedState);
    return resolvedState;
  }

  void emit(SubscriptionResultEvent event) {
    state = state.copyWith(
      premiumState: AppPremiumState.premium,
      resultEvent: event,
      resultEventCount: state.resultEventCount + 1,
    );
  }
}

class _PendingStartupSubscriptionController extends SubscriptionController {
  _PendingStartupSubscriptionController(this.result);

  final Completer<AppPremiumState> result;

  @override
  SubscriptionState build() => const SubscriptionState();

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) =>
      result.future;
}
