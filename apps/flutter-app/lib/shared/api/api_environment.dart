enum AppEnvironment { test, production }

abstract final class AppConfig {
  static const environmentName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  static const environment = environmentName == 'production'
      ? AppEnvironment.production
      : AppEnvironment.test;

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8787/api/v1',
  );

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

const appApiBaseUrl = AppConfig.apiBaseUrl;
