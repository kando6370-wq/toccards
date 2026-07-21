import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/market/market_change.dart';

void main() {
  test('calculates amount and percent from current and previous prices', () {
    final change = MarketChange.fromPrices(current: 120, previous: 100);

    expect(change.amount, 20);
    expect(change.percent, 20);
    expect(change.amountText, r'$20.00');
    expect(change.percentText, '+20.00%');
  });

  test('quantity changes amount but not percentage', () {
    final change = MarketChange.fromPrices(
      current: 120,
      previous: 100,
      quantity: 3,
    );

    expect(change.amount, 60);
    expect(change.percent, 20);
    expect(change.amountText, r'$60.00');
    expect(change.percentText, '+20.00%');
  });

  test(
    'formats a server-provided percent without recalculating it from prices',
    () {
      final change = MarketChange.fromPercent(12.34);

      expect(change.percent, 12.34);
      expect(change.percentText, '+12.34%');
    },
  );

  test('missing or invalid previous price falls back loudly', () {
    for (final previous in <double?>[null, 0, -1]) {
      final change = MarketChange.fromPrices(current: 120, previous: previous);

      expect(change.amountText, '--');
      expect(change.percentText, '-/-');
    }
  });

  test('missing or invalid current price falls back loudly', () {
    for (final current in <double?>[null, 0, -1]) {
      final change = MarketChange.fromPrices(current: current, previous: 100);

      expect(change.currentValueText, '--');
      expect(change.amountText, '--');
      expect(change.percentText, '-/-');
    }
  });

  test('tiny non-zero percentage uses less-than display', () {
    final up = MarketChange.fromPrices(current: 100.004, previous: 100);
    final down = MarketChange.fromPrices(current: 99.996, previous: 100);

    expect(up.percentText, '<0.01%');
    expect(down.percentText, '-<0.01%');
  });
}
