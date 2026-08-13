import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

import 'subscription_controller.dart';
import 'subscription_entitlement_cache.dart';

class PremiumTopEntry extends ConsumerWidget {
  const PremiumTopEntry({required this.source, super.key});

  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premiumState = ref.watch(
      subscriptionControllerProvider.select((state) => state.premiumState),
    );
    if (premiumState != AppPremiumState.free) {
      return const SizedBox.shrink();
    }

    return SizedBox.square(
      dimension: 42,
      child: IconButton(
        key: Key('$source-premium-top-entry'),
        tooltip: 'View Premium plans',
        style: IconButton.styleFrom(
          backgroundColor: KandoColors.accentGlow10,
          foregroundColor: KandoColors.accent,
          side: const BorderSide(color: KandoColors.borderFocus),
        ),
        onPressed: () => context.push(
          Uri(
            path: '/subscription',
            queryParameters: {
              'source': source,
              'entry_source': 'top_subscription_entry',
            },
          ).toString(),
        ),
        icon: const Icon(Icons.workspace_premium_outlined, size: 22),
      ),
    );
  }
}
