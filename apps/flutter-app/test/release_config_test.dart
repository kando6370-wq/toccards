import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/validate_release_config.dart';

void main() {
  test(
    'release config requires every v1.1 subscription and attribution key',
    () {
      expect(validateReleaseConfig({'APP_ENV': 'production'}, 'production'), [
        'SUBSCRIPTION_APP_STORE_WEEKLY_ID must be a non-empty string.',
        'SUBSCRIPTION_APP_STORE_YEARLY_ID must be a non-empty string.',
        'SUBSCRIPTION_APP_STORE_LIFETIME_ID must be a non-empty string.',
        'SINGULAR_API_KEY must be a non-empty string.',
        'SINGULAR_SECRET_KEY must be a non-empty string.',
      ]);
    },
  );

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
}

Map<String, Object?> validConfig() => {
  'APP_ENV': 'production',
  'SUBSCRIPTION_APP_STORE_WEEKLY_ID': 'example.weekly',
  'SUBSCRIPTION_APP_STORE_YEARLY_ID': 'example.yearly',
  'SUBSCRIPTION_APP_STORE_LIFETIME_ID': 'example.lifetime',
  'SINGULAR_API_KEY': 'api-key',
  'SINGULAR_SECRET_KEY': 'secret-key',
};
