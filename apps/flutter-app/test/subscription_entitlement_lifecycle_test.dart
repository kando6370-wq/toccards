import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_lifecycle.dart';

void main() {
  testWidgets(
    'returning to foreground silently refreshes Apple entitlement so expired Premium can lock in place',
    (tester) async {
      final controller = _LifecycleSubscriptionController();
      await tester.pumpWidget(_testApp(controller));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(controller.refreshCount, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(controller.refreshCount, 1);
      expect(controller.lastShowFailure, isFalse);
      expect(find.text('Current Page'), findsOneWidget);
    },
  );

  testWidgets(
    'foreground entitlement failure keeps the current page and never opens subscription UI',
    (tester) async {
      final controller = _LifecycleSubscriptionController(
        throwsOnRefresh: true,
      );
      await tester.pumpWidget(_testApp(controller));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(controller.refreshCount, 1);
      expect(find.text('Current Page'), findsOneWidget);
      expect(find.text('Choose Your Plan'), findsNothing);
    },
  );
}

Widget _testApp(_LifecycleSubscriptionController controller) {
  return ProviderScope(
    overrides: [subscriptionControllerProvider.overrideWith(() => controller)],
    child: const MaterialApp(
      home: SubscriptionEntitlementLifecycleObserver(
        child: Scaffold(body: Text('Current Page')),
      ),
    ),
  );
}

class _LifecycleSubscriptionController extends SubscriptionController {
  _LifecycleSubscriptionController({this.throwsOnRefresh = false});

  final bool throwsOnRefresh;
  var refreshCount = 0;
  bool? lastShowFailure;

  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.premium);

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async {
    refreshCount += 1;
    lastShowFailure = showFailure;
    if (throwsOnRefresh) throw StateError('offline');
    state = state.copyWith(premiumState: AppPremiumState.free);
    return AppPremiumState.free;
  }
}
