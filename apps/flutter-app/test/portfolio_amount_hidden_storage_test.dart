import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('amount visibility survives a cold-start storage instance', () async {
    SharedPreferences.setMockInitialValues({});

    const firstLaunch = PreferencesPortfolioAmountHiddenStorage();
    expect(await firstLaunch.readAmountHidden(), isFalse);

    await firstLaunch.writeAmountHidden(true);

    const restartedApp = PreferencesPortfolioAmountHiddenStorage();
    expect(await restartedApp.readAmountHidden(), isTrue);
  });

  test('preloaded local visibility initializes the shared provider', () {
    final container = ProviderContainer(
      overrides: [initialPortfolioAmountHiddenProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    expect(container.read(portfolioAmountHiddenProvider), isTrue);
  });
}
