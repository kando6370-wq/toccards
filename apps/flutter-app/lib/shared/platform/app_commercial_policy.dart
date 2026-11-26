import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/subscription/google_play_controller.dart';

class AppCommercialPolicy {
  const AppCommercialPolicy({
    required bool isAndroidFreeLaunch,
    this.playMetered = false,
    this.playSales = false,
  }) : isAndroid = isAndroidFreeLaunch;

  factory AppCommercialPolicy.currentPlatform() {
    return AppCommercialPolicy(
      isAndroidFreeLaunch:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    );
  }

  final bool isAndroid;
  final bool playMetered;
  final bool playSales;
  bool get isAndroidFreeLaunch => isAndroid && !playMetered;

  bool get usesAppleSubscription => !isAndroid;
  bool get hasFreePremiumFeatures => isAndroidFreeLaunch;
}

// Authentication needs the device platform before a session (and its Play policy) exists.
final appCommercialPolicyProvider = Provider<AppCommercialPolicy>(
  (ref) => AppCommercialPolicy.currentPlatform(),
);

final subscriptionAccessPolicyProvider = Provider<AppCommercialPolicy>((ref) {
  final platform = ref.watch(appCommercialPolicyProvider);
  if (!platform.isAndroid) return platform;
  final play = ref.watch(
    playPolicyProvider.select(
      (state) => (state.current?.metered == true, state.current?.sales == true),
    ),
  );
  return AppCommercialPolicy(
    isAndroidFreeLaunch: true,
    playMetered: play.$1,
    playSales: play.$2,
  );
});
