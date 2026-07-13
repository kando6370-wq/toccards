import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/currency/currency.dart';

void main() {
  test('supported currencies match the PRD currency picker list', () {
    expect(AppCurrency.values.map((currency) => currency.code), [
      'USD',
      'EUR',
      'JPY',
      'GBP',
      'CAD',
      'AUD',
      'NZD',
      'SGD',
    ]);
  });

  test('formats USD money with cents and thousands separators', () {
    final formatter = CurrencyFormatter(currency: AppCurrency.usd);

    expect(formatter.formatUsd(12840), r'$12,840.00');
    expect(formatter.formatUsd(0), r'$0.00');
  });

  test('converts USD amounts through mock rates before formatting', () {
    final formatter = CurrencyFormatter(currency: AppCurrency.eur);

    expect(formatter.formatUsd(12840), '€11,684.40');
    expect(formatter.formatUsd(780, quantity: 2), '€1,419.60');
  });

  test('keeps minus before the currency symbol', () {
    final formatter = CurrencyFormatter(currency: AppCurrency.eur);

    expect(formatter.formatUsd(-420), '-€382.20');
  });

  test('missing money and hidden money use global fallback copy', () {
    final formatter = CurrencyFormatter(currency: AppCurrency.usd);

    expect(formatter.formatUsd(null, allowZero: false), '--');
    expect(formatter.formatUsd(12840, hidden: true), hiddenMoneyText);
  });

  test('selected currency provider defaults to USD and can be changed', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(selectedCurrencyProvider), AppCurrency.usd);

    container.read(selectedCurrencyProvider.notifier).select(AppCurrency.gbp);

    expect(container.read(selectedCurrencyProvider), AppCurrency.gbp);
  });
}
