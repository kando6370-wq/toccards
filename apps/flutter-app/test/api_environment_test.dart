import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_environment.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';

void main() {
  test(
    'test business requests use Linux while production keeps its cloud API',
    () {
      final production = AppConfig.environment == AppEnvironment.production;

      expect(
        kandoApiBaseUrl,
        production
            ? 'https://api.tcgcard.fun/api/v1'
            : 'http://192.168.50.201:8080/api/v1',
      );
      expect(AppConfig.isTestEnvironment, !production);
      expect(AppConfig.isDebugData, !production);
      final clients = [
        createAuthDio(),
        createCardDataDio(),
        createPortfolioDio(),
        createScanDio(),
      ];
      for (final client in clients) {
        expect(client.options.baseUrl, kandoApiBaseUrl);
        client.close();
      }
      expect(appUpgradeApiBaseUrl, kandoApiBaseUrl);
    },
  );

  test('app environment is one of the supported build values', () {
    expect(AppConfig.environmentName, anyOf('test', 'production'));
    expect(() => AppConfig.validate(), returnsNormally);
  });
}
