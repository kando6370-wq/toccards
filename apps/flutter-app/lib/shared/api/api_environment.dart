enum AppEnvironment { test, production }

abstract final class AppConfig {
  static const environmentName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  static const environment = environmentName == 'production'
      ? AppEnvironment.production
      : AppEnvironment.test;

  static const apiOrigin = environment == AppEnvironment.production
      ? 'https://api.tcgcard.fun'
      : 'http://192.168.50.201:8080';

  static const apiBaseUrl = '$apiOrigin/api/v1';
  static const cardShareBaseUrl = '$apiOrigin/share/cards';

  static const isTestEnvironment = environment == AppEnvironment.test;
  static const isDebugData = isTestEnvironment;

  static void validate() {
    if (environmentName != 'test' && environmentName != 'production') {
      throw StateError(
        'Unsupported APP_ENV "$environmentName". Use "test" or "production".',
      );
    }
  }
}

const kandoApiBaseUrl = AppConfig.apiBaseUrl;
