import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_environment.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/subscription/apple_current_entitlements.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_api.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';

void main() {
  test('iOS IPA validation expects the API used by the selected build', () {
    final script = File('tool/release_ios.sh').readAsStringSync();
    final environment = AppConfig.environmentName;
    final assignment = RegExp(
      '$environment\\)\\s+API_BASE_URL="([^"]+)"',
    ).firstMatch(script);

    expect(assignment, isNotNull);
    expect(assignment!.group(1), kandoApiBaseUrl);
  });

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

  test('business API clients use the configured network timeouts', () {
    final auth = createAuthDio();
    final cardData = createCardDataDio();
    final portfolio = createPortfolioDio();
    final scan = createScanDio();
    addTearDown(() {
      auth.close();
      cardData.close();
      portfolio.close();
      scan.close();
    });

    expect(auth.options.connectTimeout, const Duration(seconds: 10));
    expect(auth.options.receiveTimeout, const Duration(seconds: 10));
    expect(authRequestDeadline, const Duration(seconds: 25));
    expect(cardData.options.connectTimeout, const Duration(seconds: 10));
    expect(cardData.options.receiveTimeout, const Duration(seconds: 10));
    expect(cardDataRequestDeadline, const Duration(seconds: 25));
    expect(portfolio.options.connectTimeout, const Duration(seconds: 10));
    expect(portfolio.options.receiveTimeout, const Duration(seconds: 15));
    expect(portfolioRequestDeadline, const Duration(seconds: 25));
    expect(scan.options.connectTimeout, const Duration(seconds: 10));
    expect(scan.options.receiveTimeout, isNull);
    expect(scanRequestDeadline, const Duration(seconds: 25));
    expect(currencyRateRequestDeadline, const Duration(seconds: 25));
    expect(subscriptionEntitlementRequestDeadline, const Duration(seconds: 25));
    expect(
      const AppleSubscriptionRestorer(
        reader: _UnusedEntitlementReader(),
      ).deadline,
      const Duration(seconds: 25),
    );
  });

  test('app environment is one of the supported build values', () {
    expect(AppConfig.environmentName, anyOf('test', 'production'));
    expect(AppConfig.httpTransportName, anyOf('native', 'io'));
    expect(() => AppConfig.validate(), returnsNormally);
  });
}

class _UnusedEntitlementReader implements AppleCurrentEntitlementReader {
  const _UnusedEntitlementReader();

  @override
  Future<List<AppleCurrentEntitlement>> read(Set<String> productIds) async =>
      const [];

  @override
  Future<void> synchronize() async {}
}
