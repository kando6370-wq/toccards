enum AppEnvironment { test, production }

abstract final class AppConfig {
  static const environmentName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'test',
  );

  static const environment = environmentName == 'production'
      ? AppEnvironment.production
      : AppEnvironment.test;

  static const apiBaseUrl = environment == AppEnvironment.production
      ? 'https://api.tcgcard.fun/api/v1'
      : 'https://api-dev.tcgcard.fun/api/v1';

  static const mixpanelProjectToken = environment == AppEnvironment.production
      ? '4ee4af25991c3da8108024123b790de6'
      : '80efe7f0b927af80a3048e382269ba9e';

  static const mixpanelApiSecret = environment == AppEnvironment.production
      ? '5cf8e46443d4445cea7dc4619412455d'
      : '56663617c8e32d6eda2dc3776020f7ae';

  static const isDebugData = environment == AppEnvironment.test;

  static void validate() {
    if (environmentName != 'test' && environmentName != 'production') {
      throw StateError(
        'Unsupported APP_ENV "$environmentName". Use "test" or "production".',
      );
    }
  }
}

const kandoApiBaseUrl = AppConfig.apiBaseUrl;
