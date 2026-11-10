import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';

void main() {
  test(
    'Android free launch opens existing premium features without Apple billing',
    () {
      const policy = AppCommercialPolicy(isAndroidFreeLaunch: true);

      expect(policy.hasFreePremiumFeatures, isTrue);
      expect(policy.usesAppleSubscription, isFalse);
    },
  );

  test('iOS keeps the existing Apple subscription policy', () {
    const policy = AppCommercialPolicy(isAndroidFreeLaunch: false);

    expect(policy.hasFreePremiumFeatures, isFalse);
    expect(policy.usesAppleSubscription, isTrue);
  });

  for (final scenario in [
    (
      platform: TargetPlatform.android,
      androidFree: true,
      appleSubscription: false,
    ),
    (platform: TargetPlatform.iOS, androidFree: false, appleSubscription: true),
  ]) {
    test('default provider follows ${scenario.platform.name}', () {
      debugDefaultTargetPlatformOverride = scenario.platform;
      try {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final policy = container.read(appCommercialPolicyProvider);
        expect(policy.isAndroidFreeLaunch, scenario.androidFree);
        expect(policy.usesAppleSubscription, scenario.appleSubscription);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
