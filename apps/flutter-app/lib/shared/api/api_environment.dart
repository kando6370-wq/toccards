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
