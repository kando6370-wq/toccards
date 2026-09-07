import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'subscription_controller.dart';

class SubscriptionEntitlementLifecycleObserver extends ConsumerStatefulWidget {
  const SubscriptionEntitlementLifecycleObserver({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  ConsumerState<SubscriptionEntitlementLifecycleObserver> createState() =>
      _SubscriptionEntitlementLifecycleObserverState();
}

class _SubscriptionEntitlementLifecycleObserverState
    extends ConsumerState<SubscriptionEntitlementLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshEntitlement());
    }
  }

  Future<void> _refreshEntitlement() async {
    try {
      await ref
          .read(subscriptionControllerProvider.notifier)
          .refreshEntitlement(showFailure: false);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Unable to refresh subscription entitlement on resume: '
        '$error\n$stackTrace',
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
