import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_environment.dart';

void main() {
  test('app environment selects the matching API', () {
    final production = AppConfig.environment == AppEnvironment.production;

    expect(
      kandoApiBaseUrl,
      production
          ? 'https://api.tcgcard.fun/api/v1'
          : 'https://api-dev.tcgcard.fun/api/v1',
    );
    expect(AppConfig.isTestEnvironment, !production);
    expect(AppConfig.isDebugData, !production);
  });

  test('app environment is one of the supported build values', () {
    expect(AppConfig.environmentName, anyOf('test', 'production'));
    expect(() => AppConfig.validate(), returnsNormally);
  });
}
