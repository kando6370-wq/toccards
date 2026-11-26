import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/platform/app_commercial_policy.dart';
import '../../shared/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'google_play_controller.dart';
import 'subscription_controller.dart';
import 'subscription_display_config.dart';

final _entryVisibleProvider = Provider.family<bool, SubscriptionPageType>((
  ref,
  placement,
) {
  final policy = ref.watch(subscriptionAccessPolicyProvider);
  if (policy.usesAppleSubscription) return true;
  if (!policy.playSales) return false;
  final config = ref.watch(playDisplayConfigProvider(placement));
  return !config.isLoading && config.asData?.value != null;
});

final subscriptionPageEntryVisibleProvider = _entryVisibleProvider(
  SubscriptionPageType.page,
);
final subscriptionModalEntryVisibleProvider = _entryVisibleProvider(
  SubscriptionPageType.modal,
);

SubscriptionPageType _placement(Uri location) =>
    location.queryParameters['presentation'] == 'sheet'
    ? SubscriptionPageType.modal
    : SubscriptionPageType.page;

extension SubscriptionNavigation on BuildContext {
  Future<SubscriptionPaywallResult?> openSubscriptionPaywall(
    String location,
  ) async {
    final container = ProviderScope.containerOf(this, listen: false);
    if (!container.read(appCommercialPolicyProvider).isAndroid) {
      return push<SubscriptionPaywallResult>(location);
    }
    final owner = container.read(authControllerProvider).session?.dataSpaceId;
    final display = playDisplayConfigProvider(_placement(Uri.parse(location)));
    Map<String, dynamic>? config;
    try {
      config = await container.refresh(display.future);
    } on Exception {
      if (mounted && ModalRoute.of(this)?.isCurrent != false) {
        showKandoTopFailureToast(this);
      }
      return null;
    }
    if (!mounted ||
        ModalRoute.of(this)?.isCurrent == false ||
        owner != container.read(authControllerProvider).session?.dataSpaceId) {
      return null;
    }
    if (config == null) {
      showKandoTopToast(
        this,
        message: 'Premium offers are currently unavailable.',
        type: KandoTopToastType.info,
      );
      return null;
    }
    return push<SubscriptionPaywallResult>(location, extra: config);
  }
}

Future<String?> googlePlayEntryRedirect(Ref ref, GoRouterState state) async {
  final display = playDisplayConfigProvider(_placement(state.uri));
  try {
    // Reuse an in-app tap's current check. A direct or restored link checks the server.
    if (state.extra != null) {
      final cached = ref.read(display);
      if (!cached.isLoading && identical(state.extra, cached.asData?.value)) {
        return null;
      }
    }
    if (await ref.refresh(display.future) != null) return null;
    return ref.read(playPolicyProvider).current?.metered == false
        ? '/home'
        : '/profile';
  } on Exception {
    return '/profile';
  }
}
