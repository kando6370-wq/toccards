import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
