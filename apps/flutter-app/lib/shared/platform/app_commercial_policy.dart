import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppCommercialPolicy {
  const AppCommercialPolicy({required this.isAndroidFreeLaunch});

  factory AppCommercialPolicy.currentPlatform() {
    return AppCommercialPolicy(
      isAndroidFreeLaunch:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    );
  }

  final bool isAndroidFreeLaunch;

  bool get usesAppleSubscription => !isAndroidFreeLaunch;
  bool get hasFreePremiumFeatures => isAndroidFreeLaunch;
}

final appCommercialPolicyProvider = Provider<AppCommercialPolicy>((ref) {
  return AppCommercialPolicy.currentPlatform();
});
