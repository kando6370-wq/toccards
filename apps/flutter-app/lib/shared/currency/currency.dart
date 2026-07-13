import 'package:flutter_riverpod/flutter_riverpod.dart';

const hiddenMoneyText = '••••••';

enum AppCurrency {
  usd('USD', 'US Dollar', r'$', 1),
  eur('EUR', 'Euro', '€', 0.91),
  jpy('JPY', 'Japanese Yen', '¥', 155.32),
  gbp('GBP', 'British Pound', '£', 0.79),
  cad('CAD', 'Canadian Dollar', r'C$', 1.37),
  aud('AUD', 'Australian Dollar', r'A$', 1.52),
  nzd('NZD', 'New Zealand Dollar', r'NZ$', 1.66),
  sgd('SGD', 'Singapore Dollar', r'S$', 1.35);

  const AppCurrency(this.code, this.label, this.symbol, this.usdRate);

  final String code;
  final String label;
  final String symbol;
  final double usdRate;

  static AppCurrency fromCode(String code) {
    return AppCurrency.values.firstWhere(
      (currency) => currency.code == code,
      orElse: () => AppCurrency.usd,
    );
  }
}

class CurrencyFormatter {
  const CurrencyFormatter({required this.currency});

  final AppCurrency currency;

  String formatUsd(
    double? valueUsd, {
    int quantity = 1,
    bool hidden = false,
    bool allowZero = true,
  }) {
    if (hidden) {
      return hiddenMoneyText;
    }
    if (valueUsd == null || (!allowZero && valueUsd <= 0)) {
      return '--';
    }

    final normalizedQuantity = quantity < 1 ? 1 : quantity;
    final converted = valueUsd * normalizedQuantity * currency.usdRate;
    return _format(converted);
  }

  String _format(double value) {
    final sign = value < 0 ? '-' : '';
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    return '$sign${currency.symbol}${_withThousands(parts[0])}.${parts[1]}';
  }

  String _withThousands(String value) {
    final buffer = StringBuffer();
    for (var index = 0; index < value.length; index++) {
      final remaining = value.length - index;
      buffer.write(value[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

final selectedCurrencyProvider =
    NotifierProvider<SelectedCurrencyController, AppCurrency>(
      SelectedCurrencyController.new,
    );

class SelectedCurrencyController extends Notifier<AppCurrency> {
  @override
  AppCurrency build() {
    return AppCurrency.usd;
  }

  void select(AppCurrency currency) {
    state = currency;
  }

  void selectCode(String code) {
    select(AppCurrency.fromCode(code));
  }
}
