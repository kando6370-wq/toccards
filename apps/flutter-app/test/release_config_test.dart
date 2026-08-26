import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/validate_release_config.dart';

void main() {
  test('production release requires every subscription product ID', () {
    expect(validateReleaseConfig({'APP_ENV': 'production'}, 'production'), [
      'SUBSCRIPTION_APP_STORE_WEEKLY_ID must be a non-empty string.',
      'SUBSCRIPTION_APP_STORE_YEARLY_ID must be a non-empty string.',
      'SUBSCRIPTION_APP_STORE_LIFETIME_ID must be a non-empty string.',
    ]);
  });

  test(
    'release config rejects the wrong environment and duplicate products',
    () {
      final config = validConfig()..['APP_ENV'] = 'test';
      config['SUBSCRIPTION_APP_STORE_YEARLY_ID'] =
          config['SUBSCRIPTION_APP_STORE_WEEKLY_ID'];

      expect(validateReleaseConfig(config, 'production'), [
        'APP_ENV must equal production.',
        'Subscription Product IDs must be unique.',
      ]);
    },
  );

  test('complete environment-specific release config passes', () {
    expect(validateReleaseConfig(validConfig(), 'production'), isEmpty);
  });

  test('release config does not contain runtime Singular credentials', () {
    final config = validConfig()..['APP_ENV'] = 'test';

    expect(validateReleaseConfig(config, 'test'), isEmpty);
    expect(config, isNot(contains('SINGULAR_API_KEY')));
    expect(config, isNot(contains('SINGULAR_SECRET_KEY')));
  });

  test('dev and production builds use their own verified Apple products', () {
    final testConfig =
        jsonDecode(File('config/test.json').readAsStringSync())
            as Map<String, Object?>;
    final productionConfig =
        jsonDecode(File('config/production.json').readAsStringSync())
            as Map<String, Object?>;

    expect(testConfig, isNot(contains('SINGULAR_API_KEY')));
    expect(testConfig, isNot(contains('SINGULAR_SECRET_KEY')));
    expect(productionConfig, isNot(contains('SINGULAR_API_KEY')));
    expect(productionConfig, isNot(contains('SINGULAR_SECRET_KEY')));
    expect(
      testConfig,
      containsPair('SUBSCRIPTION_APP_STORE_WEEKLY_ID', 'cardx.week'),
    );
    expect(
      testConfig,
      containsPair('SUBSCRIPTION_APP_STORE_YEARLY_ID', 'cardx.year'),
    );
    expect(
      testConfig,
      containsPair('SUBSCRIPTION_APP_STORE_LIFETIME_ID', 'cardx.lifetime'),
    );
    expect(
      productionConfig,
      containsPair('SUBSCRIPTION_APP_STORE_WEEKLY_ID', 'CardAi.weekly'),
    );
    expect(
      productionConfig,
      containsPair('SUBSCRIPTION_APP_STORE_YEARLY_ID', 'CardAi.yearly'),
    );
    expect(
      productionConfig,
      containsPair('SUBSCRIPTION_APP_STORE_LIFETIME_ID', 'CardAi.lifetime'),
    );
    expect(
      productionConfig.values.toSet().intersection(testConfig.values.toSet()),
      isEmpty,
      reason: 'dev Product IDs must not authorize production purchases',
    );
  });

  test(
    'iOS release invokes the standard-library validator without workspace build hooks',
    () {
      final script = File('tool/release_ios.sh').readAsStringSync();

      expect(
        script,
        contains(
          'dart "\$APP_DIR/tool/validate_release_config.dart" '
          '"\$ENV_CONFIG" "\$ENVIRONMENT"',
        ),
      );
      expect(
        script,
        isNot(
          contains('dart run "\$APP_DIR/tool/validate_release_config.dart"'),
        ),
      );
    },
  );

  test(
    'iOS test builds use the beta bundle and keep the existing Google client',
    () {
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final firebaseConfig = File(
        'ios/Runner/Firebase/test/GoogleService-Info.plist',
      ).readAsStringSync();
      final oauthAuthorizer = File(
        'lib/features/auth/oauth_authorizer.dart',
      ).readAsStringSync();
      final releaseScript = File('tool/release_ios.sh').readAsStringSync();

      expect(
        'PRODUCT_BUNDLE_IDENTIFIER = com.kando.kandoApp.beta;'.allMatches(
          project,
        ),
        hasLength(3),
      );
      expect(
        'APP_ATTEST_ENVIRONMENT = development;'.allMatches(project),
        hasLength(3),
      );
      expect(
        'APP_ATTEST_ENVIRONMENT = production;'.allMatches(project),
        hasLength(3),
      );
      expect(
        firebaseConfig,
        contains('<string>com.kando.kandoApp.beta</string>'),
      );
      expect(
        oauthAuthorizer,
        contains(
          '1030914046373-j0ihp89joii8c9k66v89l9dske6mp0mc.apps.googleusercontent.com',
        ),
      );
      expect(
        releaseScript,
        contains('BUNDLE_ID="\${BUNDLE_ID:-com.kando.kandoApp.beta}"'),
      );
    },
  );

  test(
    'unconfigured builds default to production because the default app identity is production',
    () {
      final apiEnvironment = File(
        'lib/shared/api/api_environment.dart',
      ).readAsStringSync();
      final iosProject = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final androidBuild = File(
        'android/app/build.gradle.kts',
      ).readAsStringSync();

      expect(apiEnvironment, contains("defaultValue: 'production'"));
      expect(
        'PRODUCT_BUNDLE_IDENTIFIER = com.cardai.tcg;'.allMatches(iosProject),
        hasLength(3),
      );
      expect(androidBuild, contains('applicationId = "com.cardai.tcg"'));
    },
  );
}

Map<String, Object?> validConfig() => {
  'APP_ENV': 'production',
  'SUBSCRIPTION_APP_STORE_WEEKLY_ID': 'example.weekly',
  'SUBSCRIPTION_APP_STORE_YEARLY_ID': 'example.yearly',
  'SUBSCRIPTION_APP_STORE_LIFETIME_ID': 'example.lifetime',
};
