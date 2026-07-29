import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_environment.dart';

void main() {
  test('app environment selects API and Mixpanel configuration together', () {
    final production = AppConfig.environment == AppEnvironment.production;

    expect(
      kandoApiBaseUrl,
      production
          ? 'https://api.tcgcard.fun/api/v1'
          : 'https://api-dev.tcgcard.fun/api/v1',
    );
    expect(
      AppConfig.mixpanelProjectToken,
      production
          ? '4ee4af25991c3da8108024123b790de6'
          : '80efe7f0b927af80a3048e382269ba9e',
    );
    expect(
      AppConfig.mixpanelApiSecret,
      production
          ? '5cf8e46443d4445cea7dc4619412455d'
          : '56663617c8e32d6eda2dc3776020f7ae',
    );
    expect(AppConfig.isDebugData, !production);
  });

  test('app environment is one of the supported build values', () {
    expect(AppConfig.environmentName, anyOf('test', 'production'));
    expect(() => AppConfig.validate(), returnsNormally);
  });
}
