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

  static const httpTransportName = String.fromEnvironment(
    'APP_HTTP_TRANSPORT',
    defaultValue: 'native',
  );

  static const isTestEnvironment = environment == AppEnvironment.test;
  static const isDebugData = isTestEnvironment;

  static void validate() {
    if (environmentName != 'test' && environmentName != 'production') {
      throw StateError(
        'Unsupported APP_ENV "$environmentName". Use "test" or "production".',
      );
    }
    if (httpTransportName != 'native' && httpTransportName != 'io') {
      throw StateError(
        'Unsupported APP_HTTP_TRANSPORT "$httpTransportName". '
        'Use "native" or "io".',
      );
    }
  }
}

const kandoApiBaseUrl = AppConfig.apiBaseUrl;
