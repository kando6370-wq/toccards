import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ui/kando_style.dart';
import 'subscription_controller.dart';
import 'subscription_entitlement_cache.dart';
import 'subscription_page.dart';

class StartupSubscriptionGate extends ConsumerStatefulWidget {
  const StartupSubscriptionGate({
    required this.home,
    required this.source,
    super.key,
  });

  final Widget home;
  final String source;

  @override
  ConsumerState<StartupSubscriptionGate> createState() =>
      _StartupSubscriptionGateState();
}

class _StartupSubscriptionGateState
    extends ConsumerState<StartupSubscriptionGate> {
  AppPremiumState? _resolvedState;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_resolveEntitlement);
  }

  Future<void> _resolveEntitlement() async {
    AppPremiumState resolved;
    try {
      resolved = await ref
          .read(subscriptionControllerProvider.notifier)
          .refreshEntitlement(showFailure: false)
          .timeout(const Duration(seconds: 15));
    } on Object {
      resolved = AppPremiumState.unknown;
    }
    if (mounted) setState(() => _resolvedState = resolved);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_resolvedState) {
      AppPremiumState.free => SubscriptionPage(source: widget.source),
      AppPremiumState.premium || AppPremiumState.unknown => widget.home,
      null => const _EntitlementStartupPage(),
    };
  }
}

class _EntitlementStartupPage extends StatelessWidget {
  const _EntitlementStartupPage();

  @override
  Widget build(BuildContext context) {
    return const Material(
      key: ValueKey('startup-entitlement-loading'),
      color: KandoColors.ink,
      child: Center(
        child: CircularProgressIndicator(color: KandoColors.accent),
      ),
    );
  }
}
