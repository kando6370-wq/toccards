import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';

void main() {
  test(
    'the minimum boundary is inclusive while numeric version ordering avoids forcing already newer builds',
    () {
      const config = AppUpgradeConfig(
        upgradePrompt: UpgradePrompt(
          latestVersion: '1.0.10',
          minVersion: '1.0.2',
          forceUpdate: true,
          title: 'Update available',
          message: 'A new version is available.',
          storeUrl: 'https://apps.apple.com/app/kando',
        ),
      );
      expect(
        AppUpgradePolicy.evaluate(
          currentVersion: '1.0.1',
          config: config,
        ).forceUpdate,
        isTrue,
      );
      final minimum = AppUpgradePolicy.evaluate(
        currentVersion: '1.0.2+125',
        config: config,
      );
      expect(minimum.showUpdate, isTrue);
      expect(minimum.forceUpdate, isFalse);
      expect(
        AppUpgradePolicy.evaluate(
          currentVersion: '1.0.10',
          config: config,
        ).showUpdate,
        isFalse,
      );
      expect(
        AppUpgradePolicy.evaluate(
          currentVersion: '1.0.11',
          config: config,
        ).showUpdate,
        isFalse,
      );
    },
  );

  test(
    'an inconsistent minimum cannot be bypassed by matching a lower recommendation',
    () {
      expect(
        () => AppUpgradePolicy.evaluate(
          currentVersion: '1.0.1',
          config: const AppUpgradeConfig(
            upgradePrompt: UpgradePrompt(
              latestVersion: '1.0.1',
              minVersion: '2.0.0',
              forceUpdate: true,
              title: 'Update required',
              message: 'Update to continue.',
              storeUrl: 'https://apps.apple.com/app/kando',
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'missing store targets must fail explicitly instead of silently disabling mandatory updates',
    () {
      expect(
        () => AppUpgradePolicy.evaluate(
          currentVersion: '1.0.0',
          config: const AppUpgradeConfig(
            upgradePrompt: UpgradePrompt(
              latestVersion: '1.0.1',
              forceUpdate: true,
              title: 'Update required',
              message: 'Update to continue.',
              storeUrl: null,
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'config parses Profile links because legal and store actions must use operations-owned URLs',
    () {
      final config = AppUpgradeConfig.fromJson(const {
        'app_store_url': 'https://apps.apple.com/app/kando/id123',
        'card_share_base_url': 'https://api.tcgcard.fun/share/cards',
        'terms_url': 'https://www.tcgcard.fun/terms',
        'privacy_url': 'https://www.tcgcard.fun/privacy',
      });

      expect(config.appStoreUrl, 'https://apps.apple.com/app/kando/id123');
      expect(config.cardShareBaseUrl, 'https://api.tcgcard.fun/share/cards');
      expect(config.termsUrl, 'https://www.tcgcard.fun/terms');
      expect(config.privacyUrl, 'https://www.tcgcard.fun/privacy');
    },
  );

  test(
    'policy requires forced update because operations marked this release as mandatory',
    () {
      final decision = AppUpgradePolicy.evaluate(
        currentVersion: '1.0.0+1',
        config: const AppUpgradeConfig(
          upgradePrompt: UpgradePrompt(
            latestVersion: '1.0.1',
            forceUpdate: true,
            title: 'Update required',
            message: 'Install the latest Kando build.',
            storeUrl: 'https://apps.apple.com/app/kando',
          ),
          appStoreUrl: 'https://apps.apple.com/app/kando',
        ),
      );

      expect(decision.forceUpdate, isTrue);
      expect(decision.title, 'Update required');
      expect(decision.message, 'Install the latest Kando build.');
      expect(decision.storeUrl, 'https://apps.apple.com/app/kando');
    },
  );

  test(
    'policy shows optional update because operations did not mark this release as mandatory',
    () {
      final decision = AppUpgradePolicy.evaluate(
        currentVersion: '1.0.0+1',
        config: const AppUpgradeConfig(
          upgradePrompt: UpgradePrompt(
            latestVersion: '1.0.1',
            forceUpdate: false,
            title: 'Update available',
            message: 'Install the latest Kando build.',
            storeUrl: 'https://apps.apple.com/app/kando',
          ),
          appStoreUrl: 'https://apps.apple.com/app/kando',
        ),
      );

      expect(decision.showUpdate, isTrue);
      expect(decision.forceUpdate, isFalse);
      expect(decision.storeUrl, 'https://apps.apple.com/app/kando');
    },
  );

  test(
    'policy forces only versions below the minimum because newer supported builds may defer the recommendation',
    () {
      const config = AppUpgradeConfig(
        upgradePrompt: UpgradePrompt(
          latestVersion: '2.0.0',
          minVersion: '1.2.0',
          forceUpdate: true,
          title: 'Update available',
          message: 'A newer version is available.',
          forcedMessage: 'Update to continue.',
          storeUrl: 'https://apps.apple.com/app/kando',
        ),
      );

      final supported = AppUpgradePolicy.evaluate(
        currentVersion: '1.5.0',
        config: config,
      );
      final unsupported = AppUpgradePolicy.evaluate(
        currentVersion: '1.0.0',
        config: config,
      );

      expect(supported.forceUpdate, isFalse);
      expect(supported.message, 'A newer version is available.');
      expect(unsupported.forceUpdate, isTrue);
      expect(unsupported.title, 'Update required');
      expect(unsupported.message, 'Update to continue.');
    },
  );

  test(
    'policy allows matching version because users already satisfy the minimum supported build',
    () {
      final decision = AppUpgradePolicy.evaluate(
        currentVersion: '1.0.1+4',
        config: const AppUpgradeConfig(
          upgradePrompt: UpgradePrompt(
            latestVersion: '1.0.1',
            forceUpdate: true,
            title: 'Update required',
            message: 'Install the latest Kando build.',
            storeUrl: 'https://apps.apple.com/app/kando',
          ),
          appStoreUrl: 'https://apps.apple.com/app/kando',
        ),
      );

      expect(decision.forceUpdate, isFalse);
    },
  );

  test(
    'policy uses app store fallback because operations may keep the shared URL outside the prompt JSON',
    () {
      final decision = AppUpgradePolicy.evaluate(
        currentVersion: '1.0.0',
        config: const AppUpgradeConfig(
          upgradePrompt: UpgradePrompt(
            latestVersion: '1.0.1',
            forceUpdate: true,
            title: 'Update required',
            message: 'Install the latest Kando build.',
            storeUrl: null,
          ),
          appStoreUrl: 'https://apps.apple.com/app/kando',
        ),
      );

      expect(decision.forceUpdate, isTrue);
      expect(decision.storeUrl, 'https://apps.apple.com/app/kando');
    },
  );

  test(
    'policy rejects malformed targets because invalid rules cannot prove that the installed version is supported',
    () {
      expect(
        () => AppUpgradePolicy.evaluate(
          currentVersion: '1.0.0',
          config: const AppUpgradeConfig(
            upgradePrompt: UpgradePrompt(
              latestVersion: 'latest',
              forceUpdate: true,
              title: 'Update required',
              message: 'Install the latest Kando build.',
              storeUrl: 'https://apps.apple.com/app/kando',
            ),
            appStoreUrl: 'https://apps.apple.com/app/kando',
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
